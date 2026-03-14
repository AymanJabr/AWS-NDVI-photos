variable "project_name" { type = string }
variable "public_subnet_id" { type = string }
variable "ec2_security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "key_name" { type = string }
variable "repo_url" { type = string }
variable "aws_region" { type = string }
variable "sqs_queue_url" { type = string }
variable "s3_input_bucket" { type = string }
variable "s3_output_bucket" { type = string }
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "log_group_name" { type = string }

variable "ami_id" {
  description = "Amazon Linux 2 AMI ID for your region. eu-west-1: ami-0905a3c97561e0b69"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
