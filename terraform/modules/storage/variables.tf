variable "project_name" {
  type = string
}

variable "bucket_suffix" {
  description = "Suffix to make bucket names globally unique — use your AWS account ID"
  type        = string
}
