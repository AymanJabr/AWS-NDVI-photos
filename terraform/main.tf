terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Hard-coded here so compute and monitoring modules can share it without a circular dep
locals {
  log_group_name = "/drone-pipeline/processing"
}

module "networking" {
  source = "./modules/networking"

  project_name          = var.project_name
  availability_zones    = var.availability_zones
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidr    = var.public_subnet_cidr
  private_subnet_cidr_1 = var.private_subnet_cidr_1
  private_subnet_cidr_2 = var.private_subnet_cidr_2
}

module "storage" {
  source = "./modules/storage"

  project_name  = var.project_name
  bucket_suffix = var.bucket_suffix
}

module "iam" {
  source = "./modules/iam"

  project_name         = var.project_name
  s3_input_bucket_arn  = module.storage.input_bucket_arn
  s3_output_bucket_arn = module.storage.output_bucket_arn
  sqs_queue_arn        = module.storage.sqs_queue_arn
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.networking.rds_security_group_id
  db_password           = var.db_password
  db_name               = var.db_name
  db_username           = var.db_username
}

module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  public_subnet_id      = module.networking.public_subnet_id
  ec2_security_group_id = module.networking.ec2_security_group_id
  instance_profile_name = module.iam.instance_profile_name
  ami_id                = var.ami_id
  instance_type         = var.instance_type
  key_name              = var.key_name
  repo_url              = var.repo_url
  aws_region            = var.aws_region
  sqs_queue_url         = module.storage.sqs_queue_url
  s3_input_bucket       = module.storage.input_bucket_name
  s3_output_bucket      = module.storage.output_bucket_name
  db_host               = module.database.db_host
  db_name               = var.db_name
  db_user               = var.db_username
  log_group_name        = local.log_group_name
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name    = var.project_name
  ec2_instance_id = module.compute.instance_id
  sqs_queue_name  = module.storage.sqs_queue_name
  alert_email     = var.alert_email
  aws_region      = var.aws_region
  log_group_name  = local.log_group_name
}
