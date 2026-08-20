import boto3
import json
import logging
import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    secret_arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    client = boto3.client('secretsmanager')

    if step == "createSecret":
        create_secret(client, secret_arn, token)
    elif step == "setSecret":
        set_secret(client, secret_arn, token)
    elif step == "testSecret":
        test_secret(client, secret_arn, token)
    elif step == "finishSecret":
        finish_secret(client, secret_arn, token)

def create_secret(client, arn, token):
    # Idempotency check
    try:
        client.get_secret_value(SecretId=arn, VersionId=token)
        logger.info(f"Secret version for token {token} already exists. Skipping.")
        return
    except client.exceptions.ResourceNotFoundException:
        logger.info(f"Creating new pending secret for token {token}")

    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")['SecretString']
    )
    new_password = client.get_random_password(
        PasswordLength=32,
        ExcludeCharacters='"@/\\'
    )['RandomPassword']
    current['password'] = new_password
    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current),
        VersionStages=['AWSPENDING']
    )
    logger.info(f"Successfully created pending secret for token {token}")

def set_secret(client, arn, token):
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING")['SecretString']
    )

    # Idempotency: Try first with AWSPENDING credentials
    try:
        conn = pymysql.connect(
            host=pending['host'],
            user=pending['username'],
            password=pending['password'],
            db=pending['dbname']
        )
        try:
            logger.info("Connected with AWSPENDING - ALTER USER already done. Skipping.")
            return
        finally:
            conn.close()
    except pymysql.OperationalError:
        logger.info("Cannot connect with AWSPENDING - proceeding with ALTER USER")

    # Connection with AWSCURRENT
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")['SecretString']
    )
    conn = pymysql.connect(
        host=current['host'],
        user=current['username'],
        password=current['password'],
        db=current['dbname']
    )
    try:
        with conn.cursor() as cursor:
            # Escape backticks for protection from Identifier Injection
            safe_username = pending['username'].replace("`", "``")
            sql = f"ALTER USER `{safe_username}`@'%%' IDENTIFIED BY %s"
            cursor.execute(sql, (pending['password'],))
        conn.commit()
        logger.info("Successfully altered user password")
    finally:
        conn.close()

def test_secret(client, arn, token):
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING")['SecretString']
    )
    conn = pymysql.connect(
        host=pending['host'],
        user=pending['username'],
        password=pending['password'],
        db=pending['dbname']
    )
    try:
        logger.info("Successfully tested AWSPENDING credentials")
    finally:
        conn.close()

def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)

    # Idempotency check - If it's already marked as AWSCURRENT
    current_version = None
    for v, stages in metadata['VersionIdsToStages'].items():
        if 'AWSCURRENT' in stages:
            if v == token:
                logger.info("Version already marked as AWSCURRENT. Skipping.")
                return
            current_version = v
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
    logger.info(f"Successfully promoted version {token} to AWSCURRENT")