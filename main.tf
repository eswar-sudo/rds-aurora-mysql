provider "aws" {
  region = var.region
}

# Step 1: Generate random password
resource "random_password" "rds_password" {
  length  = 16
  special = true
}

# Step 2: Create Secrets Manager secret
resource "aws_secretsmanager_secret" "rds_secret" {
  name = "${var.db_identifier}-credentials"
}

resource "aws_secretsmanager_secret_version" "rds_secret_version" {
  secret_id     = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.rds_password.result
  })
}

# 3. IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-secretsmanager-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attach policies
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_secrets" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# 4. Local file for Lambda code
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<PYTHON
import boto3, json, string, secrets

secrets_client = boto3.client('secretsmanager')

def lambda_handler(event, context):
    step = event['Step']
    if step == "createSecret":
        return create_secret(event)
    elif step == "setSecret":
        return set_secret(event)
    elif step == "testSecret":
        return test_secret(event)
    elif step == "finishSecret":
        return finish_secret(event)
    else:
        raise ValueError("Invalid step parameter")

def create_secret(event):
    print("Generating new password")
    alphabet = string.ascii_letters + string.digits
    password = ''.join(secrets.choice(alphabet) for i in range(16))
    secrets_client.put_secret_value(
        SecretId=event['SecretId'],
        SecretString=json.dumps({"username": "admin", "password": password}),
        VersionStages=['AWSPENDING']
    )
    return True

def set_secret(event):
    print("Setting secret in target system (mock)")
    # Normally update DB password here
    return True

def test_secret(event):
    print("Testing secret works (mock)")
    return True

def finish_secret(event):
    print("Promoting secret to AWSCURRENT")
    return True
PYTHON
}

# 5. Zip file for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function_payload.zip"
}

# 6. Lambda function
resource "aws_lambda_function" "rotation" {
  function_name    = "inline-secret-rotation"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
}

# 7. Attach Lambda to secret for rotation
resource "aws_secretsmanager_secret_rotation" "example" {
  secret_id           = aws_secretsmanager_secret.example.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.db_identifier}-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.db_identifier}-sg"
  description = "Allow MySQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }
}

# 1. Aurora MySQL Cluster
resource "aws_rds_cluster" "aurora" {
  count                  = var.engine_type == "aurora-mysql" ? 1 : 0
  cluster_identifier     = var.db_identifier
  engine                 = "aurora-mysql"
  engine_version         = var.engine_version
  master_username        = var.db_username
  master_password        = random_password.rds_password.result
  database_name          = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count               = var.engine_type == "aurora-mysql" ? var.instance_count : 0
  identifier          = "${var.db_identifier}-aurora-${count.index}"
  cluster_identifier  = aws_rds_cluster.aurora[0].id
  instance_class      = var.instance_class
  engine              = aws_rds_cluster.aurora[0].engine
}

# 2. Standard MySQL (Single Instance)
resource "aws_db_instance" "mysql" {
  count                  = var.engine_type == "mysql" ? 1 : 0
  identifier             = var.db_identifier
  engine                 = "mysql"
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  allocated_storage      = var.storage_gb
  username               = var.db_username
  password               = random_password.rds_password.result
  db_name                = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
  multi_az               = true
}

# 3. MySQL Multi-AZ DB Cluster (New Standard Cluster)
resource "aws_rds_cluster" "mysql_cluster" {
  count                  = var.engine_type == "mysql-cluster" ? 1 : 0
  cluster_identifier     = var.db_identifier
  engine                 = "mysql"
  engine_version         = var.engine_version
  master_username        = var.db_username
  master_password        = random_password.rds_password.result
  database_name          = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  allocated_storage = var.storage_gb
  db_cluster_instance_class = var.instance_class
  skip_final_snapshot    = true
}

resource "aws_rds_cluster_instance" "mysql_cluster_instances" {
  count               = var.engine_type == "mysql-cluster" ? var.instance_count : 0
  identifier          = "${var.db_identifier}-cluster-${count.index}"
  cluster_identifier  = aws_rds_cluster.mysql_cluster[0].id
  instance_class      = var.instance_class
  engine              = "mysql"
  publicly_accessible = false
}
