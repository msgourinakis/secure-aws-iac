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

def set_secret(client, arn, token):
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING")['SecretString']
    )
    conn = pymysql.connect(
        host=pending['host'],
        user=pending['username'],
        password=json.loads(
            client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")['SecretString']
        )['password'],
        db=pending['dbname']
    )
    with conn.cursor() as cursor:
        cursor.execute(
            "ALTER USER %s@'%%' IDENTIFIED BY %s",
            (pending['username'], pending['password'])
        )
    conn.commit()
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
    conn.close()

def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    current_version = next(
        v for v, stages in metadata['VersionIdsToStages'].items()
        if 'AWSCURRENT' in stages
    )
    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )