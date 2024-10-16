resource "aws_instance" "web_app_instance" {
  ami                    = var.custom_ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.application_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false  # Allows termination via API

  tags = {
    Name = "web-app-instance"
  }
}
