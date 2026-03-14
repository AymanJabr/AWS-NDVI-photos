data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# S3: read from input, write to output — scoped to specific buckets
data "aws_iam_policy_document" "s3_access" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${var.s3_input_bucket_arn}/*",
      "${var.s3_output_bucket_arn}/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.s3_input_bucket_arn, var.s3_output_bucket_arn]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.project_name}-s3-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.s3_access.json
}

# SQS: receive and delete from the processing queue only
data "aws_iam_policy_document" "sqs_access" {
  statement {
    effect  = "Allow"
    actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "sqs_access" {
  name   = "${var.project_name}-sqs-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.sqs_access.json
}

# CloudWatch: write logs and custom metrics
data "aws_iam_policy_document" "cloudwatch_access" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/drone-pipeline/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch_access" {
  name   = "${var.project_name}-cloudwatch-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.cloudwatch_access.json
}

# SSM Parameter Store: read DB credentials at runtime
data "aws_iam_policy_document" "ssm_access" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:*:*:parameter/${var.project_name}/*"]
  }
}

resource "aws_iam_role_policy" "ssm_access" {
  name   = "${var.project_name}-ssm-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_access.json
}
