variable "project_name" {
  description = "Project name - used as prefix for all resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (EC2 lives here)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr_1" {
  description = "CIDR for private subnet 1 (RDS)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr_2" {
  description = "CIDR for private subnet 2 (RDS requires two AZs)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "availability_zones" {
  description = "List of AZs to use - needs at least 2 for the RDS subnet group"
  type        = list(string)
}
