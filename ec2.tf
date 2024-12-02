data "aws_caller_identity" "current" {}

# Define SNS Topic
resource "aws_sns_topic" "my_topic" {
  name = "csye6225_sns_topic"
}

# Define IAM role for S3 access, CloudWatch, and SNS publish
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ],
        Resource = "arn:aws:logs:*:*:*"
        }, {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      },
    ]
  })
}

# Define IAM policy for SNS publish access
resource "aws_iam_policy" "sns_publish_policy" {
  name        = "SNSPublishPolicy"
  description = "Policy to allow publishing messages to the SNS topic"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = aws_sns_topic.my_topic.arn
      }
    ]
  })
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy to allow Lambda function to log to CloudWatch
resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "LambdaLoggingPolicy"
  description = "Policy for Lambda function to log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach the logging policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_logging_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}


# Attach S3 access policy to the role
resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Attach CloudWatch agent policy to the role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.cloudwatch_agent_policy.arn
}

# Attach SNS publish policy to the role
resource "aws_iam_role_policy_attachment" "sns_publish_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

# Create an instance profile for the combined role
resource "aws_iam_instance_profile" "s3_and_cloudwatch_instance_profile" {
  name = "S3AndCloudWatchInstanceProfile"
  role = aws_iam_role.s3_and_cloudwatch_role.name
}

resource "aws_lambda_function" "sns_lambda_function" {
  function_name = "SNSLambdaFunction"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "app.handler" # Update based on the actual handler in your Lambda code
  runtime       = "nodejs20.x"  # Update to the runtime your Lambda code uses

  # Source of the Lambda code
  filename         = "serverless.zip"
  source_code_hash = filebase64sha256("serverless.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.my_topic.arn
      # DOMAIN          = var.subdomain_name #"anfcsye6225.me"
      # MAILGUN_API_KEY = var.MAILGUN_API_KEY
      DB_HOST     = aws_db_instance.csye6225_rds_instance.address
      DB_PORT     = 5432
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      DB_NAME     = "csye6225"
      DB_DIALECT  = "postgres"
    }
  }
}

resource "aws_sns_topic_subscription" "lambda_sns_subscription" {
  topic_arn = aws_sns_topic.my_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_lambda_function.arn
}

# Allow SNS to invoke the Lambda function
resource "aws_lambda_permission" "allow_sns_invoke_lambda" {
  statement_id  = "AllowSNSToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_lambda_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.my_topic.arn
}


# Launch Template for Auto Scaling Group
resource "aws_launch_template" "csye6225_launch_template" {
  name          = "csye6225_asg"
  image_id      = var.custom_ami_id
  instance_type = "t2.micro"
  key_name      = var.key_pair_name
  iam_instance_profile {
    name = aws_iam_instance_profile.s3_and_cloudwatch_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.application_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt-get install -y amazon-cloudwatch-agent awscli jq

    # Fetch database credentials from Secrets Manager
    SECRET_NAME="db_credentials"
    REGION="${var.region}"

    # Retrieve the secret value
    SECRET=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION | jq -r '.SecretString')
    DB_USER=$(echo $SECRET | jq -r '.username')
    DB_PASSWORD=$(echo $SECRET | jq -r '.password')

    touch /home/csye6225/.env
    echo "NODE_ENV=production" >> /home/csye6225/.env
    echo "DB_HOST=$(echo ${aws_db_instance.csye6225_rds_instance.endpoint} | cut -d ':' -f 1)" >> /home/csye6225/.env
    echo "DB_PORT=5432" >> /home/csye6225/.env
    echo "DB_USER=$DB_USER" >> /home/csye6225/.env
    echo "DB_PASSWORD=$DB_PASSWORD" >> /home/csye6225/.env
    echo "DB_NAME=csye6225" >> /home/csye6225/.env
    echo "AWS_REGION=${var.region}" >> /home/csye6225/.env
    echo "APP_PORT=${var.app_port}" >> /home/csye6225/.env
    echo "S3_BUCKET_NAME=${aws_s3_bucket.csye6225_bucket.bucket}" >> /home/csye6225/.env
    echo "SNS_TOPIC_ARN=${aws_sns_topic.my_topic.arn}" >> /home/csye6225/.env

    # Install the required AWS SDK package
    npm install @aws-sdk/client-sns

    # Configure and start the CloudWatch agent
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/home/csye6225/cloudwatch-config.json \
        -s

    # Start the amazon cloudwatch service
    sudo systemctl start amazon-cloudwatch-agent

    # Reload systemd to recognize the new service
    sudo systemctl daemon-reload
    
    # Enable the service to start on boot
    sudo systemctl enable webapp.service
    
    # Start the webapp service
    sudo systemctl start webapp.service
    
    # Check the status of the service
    sudo systemctl status webapp.service --no-pager
    
    echo "Web application and CloudWatch agent setup complete."
    EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 25
      volume_type           = "gp2"
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2_key.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ec2_kms_policy_attachment,
    aws_kms_key_policy.ec2_key_policy,
    aws_kms_key.ec2_key
  ]

  disable_api_termination = false

  tags = {
    Name = "web-app-instance"
  }

}

# Auto Scaling Group
resource "aws_autoscaling_group" "csye6225_asg" {
  name                = "csye6225_asg"
  desired_capacity    = 3
  max_size            = 5
  min_size            = 3
  default_cooldown    = 60
  vpc_zone_identifier = aws_subnet.public_subnets[*].id # Ensure all desired subnets are included
  launch_template {
    id      = aws_launch_template.csye6225_launch_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_target_group.arn]

  tag {
    key                 = "Name"
    value               = "web-app-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale-up"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.csye6225_asg.name
  policy_type            = "StepScaling"

  step_adjustment {
    metric_interval_lower_bound = 5.0 # Average CPU usage above 5%
    scaling_adjustment          = 1   # Increment by 1 instance
  }
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale-down"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.csye6225_asg.name
  policy_type            = "StepScaling"

  # step_adjustment {
  #   metric_interval_upper_bound = 3.0  # Trigger when CPU usage is below 3%
  #   scaling_adjustment          = -1   # Decrement by 1 instance
  # }
  step_adjustment {
    metric_interval_upper_bound = null # Remove bound to satisfy AWS's requirement
    metric_interval_lower_bound = 0.0  # Optional, but keeps it explicit for < 3%
    scaling_adjustment          = -1   # Decrement by 1 instance
  }
}

# Application Load Balancer
resource "aws_lb" "app_load_balancer" {
  name               = "csye6225-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer_sg.id]
  subnets            = aws_subnet.public_subnets[*].id
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "app_target_group" {
  name     = "app-target-group"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.csye6225_vpc.id

  health_check {
    path     = "/healthz"
    port     = var.app_port
    protocol = "HTTP"
    interval = 60
    timeout  = 10
    matcher  = "200" # Explicitly look for a 200 OK response
    # healthy_threshold   = 2
    # unhealthy_threshold = 2
  }
}

# Listener for Load Balancer
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_load_balancer.arn
  port              = 443 #80
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn # Imported SSL certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}

# CloudWatch Metric Alarm for CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  alarm_name          = "HighCPUUtilizationAlarm"
  alarm_description   = "Alarm when CPU utilization exceeds threshold for scaling up"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 12 # Set threshold to 12% CPU utilization
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]
  ok_actions          = [aws_autoscaling_policy.scale_down_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.csye6225_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization_low" {
  alarm_name          = "LowCPUUtilizationAlarm"
  alarm_description   = "Alarm when CPU utilization drops below threshold for scaling down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 8 # Set threshold to 8% CPU utilization
  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]
  ok_actions          = [aws_autoscaling_policy.scale_up_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.csye6225_asg.name
  }
}

#### AWS Key Management Service ####

# KMS Keys for Resource Encryption
resource "aws_kms_key" "ec2_key" {
  description              = "KMS key for EC2 encryption"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = 90

  tags = {
    Name    = "KMS-EC2-Key"
    Project = "CSYE6225"
  }
}

resource "aws_kms_key" "rds_key" {
  description              = "KMS key for RDS encryption"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = 90

  tags = {
    Name    = "KMS-RDS-Key"
    Project = "CSYE6225"
  }
}

resource "aws_kms_key" "s3_key" {
  description              = "KMS key for S3 bucket encryption"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = 90

  tags = {
    Name    = "KMS-S3-Key"
    Project = "CSYE6225"
  }
}

resource "aws_kms_key" "secrets_key" {
  description              = "KMS key for Secrets Manager encryption"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = 90

  tags = {
    Name    = "KMS-Secrets-Key"
    Project = "CSYE6225"
  }
}

# resource "aws_kms_key_policy" "lambda_kms_policy" {
#   key_id = aws_kms_key.secrets_key.key_id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect    = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaExecutionRole"
#         },
#         Action    = [
#           "kms:Decrypt",
#           "kms:GenerateDataKey"
#         ],
#         Resource  = "*"
#       }
#     ]
#   })
# }

resource "aws_kms_key_policy" "lambda_kms_policy" {
  key_id = aws_kms_key.secrets_key.key_id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Grant permissions to the root account for full key management
      {
        Sid    = "EnableRootPermissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      # Grant permissions to the Lambda execution role
      {
        Sid    = "AllowLambdaAccess",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaExecutionRole"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "*"
      }
    ]
  })
}


# Generate a random database password
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

# Apply KMS key to Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name       = "db_credentials_demo"
  kms_key_id = aws_kms_key.secrets_key.arn

  tags = {
    Name    = "DB-Credentials"
    Project = "CSYE6225"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}

resource "aws_secretsmanager_secret" "email_credentials" {
  name       = "email_credentials_demo"
  kms_key_id = aws_kms_key.secrets_key.arn

  tags = {
    Name    = "Email-Credentials"
    Project = "CSYE6225"
  }
}

resource "aws_secretsmanager_secret_version" "email_credentials_version" {
  secret_id = aws_secretsmanager_secret.email_credentials.id
  secret_string = jsonencode({
    api_key = var.MAILGUN_API_KEY
    domain  = var.subdomain_name
  })
}


# # Apply KMS key to EC2 EBS Volumes
# resource "aws_ebs_volume" "example" {
#   availability_zone = data.aws_availability_zones.available.names[0]
#   size              = 10
#   encrypted         = true
#   kms_key_id        = aws_kms_key.ec2_key.arn
# }

# IAM Role for EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.s3_and_cloudwatch_role.name
}

# IAM Policy to Allow Lambda Function to Access Secrets Manager
resource "aws_iam_policy" "lambda_secrets_access_policy" {
  name        = "LambdaSecretsAccessPolicy"
  description = "Policy to allow Lambda function to access Secrets Manager for email credentials"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.email_credentials.arn
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt"
        ],
        Resource = aws_kms_key.secrets_key.arn
      }
    ]
  })
}

# Attach Secrets Manager Policy to Lambda Execution Role
resource "aws_iam_role_policy_attachment" "lambda_secrets_access_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_secrets_access_policy.arn
}

resource "aws_iam_policy" "s3_and_cloudwatch_kms_policy" {
  name        = "S3AndCloudWatchKMSPolicy"
  description = "Policy to allow S3 and CloudWatch Role to access KMS for GenerateDataKey"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ],
        Resource = aws_kms_key.s3_key.arn # Use the correct KMS key ARN
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_and_cloudwatch_kms_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.s3_and_cloudwatch_kms_policy.arn
}

resource "aws_kms_key_policy" "s3_key_policy" {
  key_id = aws_kms_key.s3_key.key_id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Grant root account full permissions
      {
        Sid    = "EnableRootPermissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      # Grant S3AndCloudWatchRole permissions
      {
        Sid    = "AllowS3AndCloudWatchRole",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/S3AndCloudWatchRole"
        },
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_kms_policy" {
  name        = "EC2KMSAccessPolicy"
  description = "Policy to allow EC2 role to use KMS for disk encryption"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = aws_kms_key.ec2_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_kms_policy_attachment" {
  role       = aws_iam_role.s3_and_cloudwatch_role.name
  policy_arn = aws_iam_policy.ec2_kms_policy.arn
}

resource "aws_kms_key_policy" "ec2_key_policy" {
  key_id = aws_kms_key.ec2_key.key_id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "EnableRootPermissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = aws_kms_key.ec2_key.arn
      },
      {
        Sid    = "AllowEC2RoleAccess",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.s3_and_cloudwatch_role.name}"
        },
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = aws_kms_key.ec2_key.arn
      },
      {
        Sid    = "AllowServiceLinkedRoleUseOfKey",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = aws_kms_key.ec2_key.arn
      }
    ]
  })
}
