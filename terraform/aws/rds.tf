resource "aws_db_subnet_group" "mysql" {
  name       = "dbsubnet-${var.project_name}-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
  tags       = var.tags
}

resource "aws_security_group" "mysql" {
  name_prefix = "mysql-${var.environment}-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_instance" "mysql" {
  identifier                      = "rds-${var.project_name}-${var.environment}"
  engine                          = "mysql"
  engine_version                  = var.rds_mysql_version
  instance_class                  = var.rds_instance_class
  allocated_storage               = var.rds_storage_gb
  db_name                         = var.mysql_database_name
  username                        = var.mysql_admin_username
  password                        = var.mysql_admin_password
  db_subnet_group_name            = aws_db_subnet_group.mysql.name
  vpc_security_group_ids          = [aws_security_group.mysql.id]
  parameter_group_name            = aws_db_parameter_group.mysql.name
  storage_encrypted               = true
  skip_final_snapshot             = true # dev project — no final snapshot needed on destroy
  backup_retention_period         = 1
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = var.tags
}
resource "aws_db_parameter_group" "mysql" {
  name   = "pg-${var.project_name}-${var.environment}"
  family = "mysql8.0"

  parameter {
    name  = "general_log"
    value = "1"
  }
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  parameter {
    name  = "long_query_time"
    value = "1"
  }

  tags = var.tags
}
