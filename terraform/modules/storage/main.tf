# Input bucket — raw drone images land here
resource "aws_s3_bucket" "input" {
  bucket = "${var.project_name}-input-${var.bucket_suffix}"

  tags = {
    Name    = "${var.project_name}-input"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket                  = aws_s3_bucket.input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output bucket — processed NDVI heatmaps go here
resource "aws_s3_bucket" "output" {
  bucket = "${var.project_name}-output-${var.bucket_suffix}"

  tags = {
    Name    = "${var.project_name}-output"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    id     = "expire-processed-images"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Dead-letter queue — messages land here after 3 failed processing attempts
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Project = var.project_name
  }
}

# Main queue — S3 events flow in here, EC2 worker polls this
resource "aws_sqs_queue" "main" {
  name                       = "${var.project_name}-queue"
  visibility_timeout_seconds = 300 # 5 min — enough time to process a large image
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Project = var.project_name
  }
}

# Allow S3 to send messages to SQS
data "aws_iam_policy_document" "sqs_allow_s3" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main.arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.input.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.sqs_allow_s3.json
}

# S3 event notification: any .jpg or .png uploaded → SQS
resource "aws_s3_bucket_notification" "input_to_sqs" {
  bucket = aws_s3_bucket.input.id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".jpg"
  }

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".png"
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
