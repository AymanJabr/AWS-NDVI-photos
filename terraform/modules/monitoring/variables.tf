variable "project_name" { type = string }
variable "ec2_instance_id" { type = string }
variable "sqs_queue_name" { type = string }
variable "alert_email" { type = string }
variable "aws_region" { type = string }

variable "log_group_name" {
  type    = string
  default = "/drone-pipeline/processing"
}
