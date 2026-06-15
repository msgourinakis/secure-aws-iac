# Random password for RDS
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secret inside Secrets Manager
resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.environment}/rds/mysql"
  description             = "RDS MySQL credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.environment}-rds-secret"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = var.db_name
  })

  depends_on = [aws_db_instance.main]
}

# Rotation Lambda for automatic secret rotation
resource "aws_secretsmanager_secret_rotation" "rds" {
  secret_id           = aws_secretsmanager_secret.rds.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.rotation]
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.environment}-db-subnet-group"
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]

  # Storage
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Security
  publicly_accessible    = false
  deletion_protection    = false # true
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.environment}-mysql-final-snapshot"

  # Patching
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.environment}-mysql"
  }
}

# IAM Role for Rotation Lambda
resource "aws_iam_role" "rotation_lambda" {
  name = "${var.environment}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_vpc" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "rotation_lambda_secrets" {
  name = "${var.environment}-rotation-lambda-secrets-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.rds.arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetRandomPassword"]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for rotation
data "archive_file" "rotation_lambda" {
  type        = "zip"
  output_path = "${path.module}/rotation_lambda.zip"
  source {
    content  = file("${path.module}/rotation_lambda.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "rotation" {
  filename         = data.archive_file.rotation_lambda.output_path
  function_name    = "${var.environment}-rds-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256
  timeout          = 30

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.rds_sg_id]
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    }
  }

  tags = {
    Name = "${var.environment}-rds-rotation"
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.rotation_lambda_basic,
    aws_iam_role_policy_attachment.rotation_lambda_vpc
  ]
}

resource "aws_lambda_permission" "rotation" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}