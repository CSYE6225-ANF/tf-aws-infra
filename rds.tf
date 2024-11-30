resource "aws_db_parameter_group" "db_parameter_group" {
  name        = "custom-db-parameter-group"
  family      = "postgres14"
  description = "Custom parameter group for the RDS instance"

  tags = {
    Name = "csye6225-db-parameter-group"
  }
}

# Apply KMS key to RDS
resource "aws_db_instance" "csye6225_rds_instance" {
  identifier             = "csye6225"
  engine                 = "postgres"
  engine_version         = 14.13
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "csye6225"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.csye6225_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_security_group.id]
  multi_az               = false
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.db_parameter_group.name
  skip_final_snapshot    = true
  kms_key_id             = aws_kms_key.rds_key.arn
  storage_encrypted      = true

  tags = {
    Name = "csye6225-db-instance"
  }
}

resource "aws_db_subnet_group" "csye6225_db_subnet_group" {
  name       = "csye6225-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "csye6225-db-subnet-group"
  }
}
