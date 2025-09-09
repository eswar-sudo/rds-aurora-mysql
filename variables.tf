variable "region" {
  description = "AWS Region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the DB subnet group"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the DB instances"
  type        = list(string)
}

varibale "cidr_blocks" {
  description = "cidr blocks for the rds SG"
  type        = string
  default     = ["10.0.0.0/8"]
}

variable "engine_type" {
  description = "Engine type: 'aurora-mysql' or 'mysql'"
  type        = string
  default     = "mysql"
}

variable "db_identifier" {
  description = "DB Identifier"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Master username"
  type        = string
}

#variable "db_password" {
 # description = "Master password"
 # type        = string
 # sensitive   = true
#}

variable "instance_class" {
  description = "Instance type"
  type        = string
  default     = "db.t3.medium"
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
}

variable "storage_gb" {
  description = "Allocated storage (only for MySQL)"
  type        = number
  default     = 20
}

variable "instance_count" {
  description = "Number of instances for Aurora MySQL or MySQL Cluster"
  type        = number
  default     = 2
}
