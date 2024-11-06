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
    touch /home/csye6225/.env
    echo "NODE_ENV=production" >> /home/csye6225/.env
    echo "DB_HOST=$(echo ${aws_db_instance.csye6225_rds_instance.endpoint} | cut -d ':' -f 1)" >> /home/csye6225/.env
    echo "DB_PORT=5432" >> /home/csye6225/.env
    echo "DB_USER=${var.db_username}" >> /home/csye6225/.env
    echo "DB_PASSWORD=${var.db_password}" >> /home/csye6225/.env
    echo "DB_NAME=csye6225" >> /home/csye6225/.env
    echo "AWS_REGION=${var.region}" >> /home/csye6225/.env
    echo "APP_PORT=${var.app_port}" >> /home/csye6225/.env
    echo "S3_BUCKET_NAME=${aws_s3_bucket.csye6225_bucket.bucket}" >> /home/csye6225/.env

    sudo apt update -y

    sudo apt install -y amazon-cloudwatch-agent

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

  # Root block device configuration
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 25
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

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
  port              = 80
  protocol          = "HTTP"

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
