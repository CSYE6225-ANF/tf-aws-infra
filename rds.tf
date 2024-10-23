resource "aws_instance" "web_app_instance" {
  ami                         = var.custom_ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.application_sg.id]
  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              # Create .env file in the application directory
              touch /home/csye6225/.env
              echo "NODE_ENV=production" >> /home/csye6225/.env
              echo "DB_HOST=$(echo ${aws_db_instance.csye6225_rds_instance.endpoint} | cut -d ':' -f 1)" >> /home/csye6225/.env
              echo "DB_PORT=5432" >> /home/csye6225/.env
              echo "DB_USER=${var.db_username}" >> /home/csye6225/.env
              echo "DB_PASSWORD=${var.db_password}" >> /home/csye6225/.env
              echo "DB_NAME=csye6225" >> /home/csye6225/.env
              EOF

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false # Allows termination via API

  tags = {
    Name = "web-app-instance"
  }
}
