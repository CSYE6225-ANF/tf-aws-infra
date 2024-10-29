# Define IAM role for S3 access and CloudWatch
resource "aws_iam_role" "s3_and_cloudwatch_role" {
  name = "S3AndCloudWatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Define IAM policy for S3 access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "S3AccessPolicy"
  description = "Policy to allow full S3 access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = "*"
      }
    ]
  })
}

# Define IAM policy for CloudWatch agent access
resource "aws_iam_policy" "cloudwatch_agent_policy" {
  name        = "CloudWatchAgentPolicy"
  description = "Policy to allow CloudWatch Agent to write metrics and logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = "*"
      }
    ]
  })
}

# Attach both policies to the role
resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.cloudwatch_agent_policy.arn
}

# Create an instance profile for the combined role
resource "aws_iam_instance_profile" "s3_and_cloudwatch_instance_profile" {
  name = "S3AndCloudWatchInstanceProfile"
  role = aws_iam_role.s3_and_cloudwatch_role.name
}

# Use the instance profile in your EC2 instance definition
resource "aws_instance" "web_app_instance" {
  ami                         = var.custom_ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.application_sg.id]
  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.s3_and_cloudwatch_instance_profile.name

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
             echo "AWS_REGION=${var.region}" >> /home/csye622/.env
             echo "APP_PORT=${var.app_port}" >> /home/csye6225/.env
             echo "S3_BUCKET_NAME=${aws_s3_bucket.csye6225_bucket.bucket}" >> /home/csye6225/.env

             # Reload systemd to recognize the new service
             sudo systemctl daemon-reload

             # Enable the service to start on boot
             sudo systemctl enable webapp.service

             # Start the webapp service
             sudo systemctl start webapp.service

             # Check the status of the service
             sudo systemctl status webapp.service --no-pager

             # Configure and start the CloudWatch agent
             sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                 -a fetch-config \
                 -m ec2 \
                 -c file:/home/csye6225/cloudwatch-config.json \
                 -s

             echo "Web application and CloudWatch agent setup complete."
             EOF

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false

  tags = {
    Name = "web-app-instance"
  }
}
