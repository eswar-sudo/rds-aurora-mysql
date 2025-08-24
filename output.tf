output "mysql_endpoint" {
  value = try(
    aws_db_instance.mysql[0].endpoint,
    aws_rds_cluster.aurora[0].endpoint,
    ""
  )
}

output "db_port" {
  value = 3306
}

output "engine_type" {
  value = var.engine_type
}
