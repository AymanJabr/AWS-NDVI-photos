output "input_bucket_name" {
  value = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  value = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  value = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  value = aws_s3_bucket.output.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.main.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.main.arn
}

output "sqs_queue_name" {
  value = aws_sqs_queue.main.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
