output "ec2_public_ip" {
  description = "SSH / Jenkins deploy target: ssh ec2-user@<this IP>"
  value       = module.compute.public_ip
}

output "s3_input_bucket" {
  description = "Upload drone images here to trigger the pipeline"
  value       = module.storage.input_bucket_name
}

output "s3_output_bucket" {
  description = "Processed NDVI heatmaps are stored here"
  value       = module.storage.output_bucket_name
}

output "sqs_queue_url" {
  description = "SQS queue bridging S3 events to the EC2 worker"
  value       = module.storage.sqs_queue_url
}

output "rds_endpoint" {
  description = "PostgreSQL endpoint (accessible from EC2 only)"
  value       = module.database.db_endpoint
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.dashboard_name}"
}
