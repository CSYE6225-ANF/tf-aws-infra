variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "application_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 8080
}

variable "custom_ami_id" {
  description = "Custom AMI ID for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  default     = "t2.micro"
}

variable "key_pair_name" {
  description = "The name of the key pair to access the EC2 instance"
  type        = string
  default     = "keypair"
}

variable "database_port" {
  description = "Port on which the database runs"
  type        = number
  default     = 5432
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
}

variable "zone_id" {
  description = "Hosted Zone ID"
  type        = string
}

variable "subdomain_name" {
  description = "Subdomain Name"
  type        = string
}

# variable "domain_name" {
#   description = "Subdomain Name"
#   type        = string
#   default     = "anfcsye6225.me"
# }

variable "app_port" {
  type    = number
  default = 8080 # or 80
}

variable "aws_account_id" {
  type = number
}
