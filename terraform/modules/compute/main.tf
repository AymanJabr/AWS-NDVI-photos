locals {
  user_data = templatefile("${path.module}/bootstrap.sh.tpl", {
    repo_url         = var.repo_url
    aws_region       = var.aws_region
    sqs_queue_url    = var.sqs_queue_url
    s3_input_bucket  = var.s3_input_bucket
    s3_output_bucket = var.s3_output_bucket
    db_host          = var.db_host
    db_name          = var.db_name
    db_user          = var.db_user
    project_name     = var.project_name
    log_group_name   = var.log_group_name
  })
}

resource "aws_instance" "worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.ec2_security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name

  user_data = base64encode(local.user_data)

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-worker"
    Project = var.project_name
  }
}
