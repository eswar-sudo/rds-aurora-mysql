provider "aws" {
  region = var.region
}

# Step 1: Generate random password
#resource "random_password" "rds_password" {
 # length  = 16
 # special = true
#}

# Step 2: Create Secrets Manager secret
#resource "aws_secretsmanager_secret" "rds_secret" {
#  name = "${var.db_identifier}-credentials"
#}

resource "aws_secretsmanager_secret_version" "rds_secret_version" {
  secret_id     = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
  username = var.db_username
 # password = random_password.rds_password.result
  })
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
    cidr_blocks = var.cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.cidr_blocks
  }
}

# 1. Aurora MySQL Cluster
resource "aws_rds_cluster" "aurora" {
  count                  = var.engine_type == "aurora-mysql" ? 1 : 0
  cluster_identifier     = var.db_identifier
  engine                 = "aurora-mysql"
  engine_version         = var.engine_version
  master_username        = var.db_username
 # master_password        = random_password.rds_password.result
  database_name          = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
  manage_master_user_password = true

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
  #password               = random_password.rds_password.result
  db_name                = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
  multi_az               = true
  manage_master_user_password = true

}

# 3. MySQL Multi-AZ DB Cluster (New Standard Cluster)
resource "aws_rds_cluster" "mysql_cluster" {
  count                  = var.engine_type == "mysql-cluster" ? 1 : 0
  cluster_identifier     = var.db_identifier
  engine                 = "mysql"
  engine_version         = var.engine_version
  master_username        = var.db_username
  #master_password        = random_password.rds_password.result
  database_name          = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  allocated_storage = var.storage_gb
  db_cluster_instance_class = var.instance_class
  skip_final_snapshot    = true
  manage_master_user_password = true

}

resource "aws_rds_cluster_instance" "mysql_cluster_instances" {
  count               = var.engine_type == "mysql-cluster" ? var.instance_count : 0
  identifier          = "${var.db_identifier}-cluster-${count.index}"
  cluster_identifier  = aws_rds_cluster.mysql_cluster[0].id
  instance_class      = var.instance_class
  engine              = "mysql"
  publicly_accessible = false
}
