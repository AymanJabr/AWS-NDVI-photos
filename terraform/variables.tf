variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "drone-pipeline"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1" # Ireland — closest to Chiavari, Italy
}

variable "availability_zones" {
  description = "Two AZs are required for the RDS subnet group"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr_1" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_cidr_2" {
  type    = string
  default = "10.0.3.0/24"
}

variable "bucket_suffix" {
  description = "Unique suffix for S3 bucket names — use your 12-digit AWS account ID"
  type        = string
}

variable "db_password" {
  description = "Password for RDS PostgreSQL — use a strong password, minimum 8 chars"
  type        = string
  sensitive   = true
}

variable "db_name" {
  type    = string
  default = "dronedb"
}

variable "db_username" {
  type    = string
  default = "droneadmin"
}

variable "ami_id" {
  description = "Amazon Linux 2 AMI for your region. eu-west-1: ami-0905a3c97561e0b69"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access from Jenkins"
  type        = string
}

variable "repo_url" {
  description = "Public GitHub repo URL (EC2 clones this on first boot)"
  type        = string
}

variable "alert_email" {
  description = "Email to receive CloudWatch alarm notifications"
  type        = string
}
