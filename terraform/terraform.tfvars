
project_name = "drone-pipeline"
aws_region   = "us-east-1"

availability_zones = ["us-east-1a", "us-east-1b"]

# Your 12-digit AWS account ID (makes S3 bucket names globally unique)
bucket_suffix = "137378241202"

# RDS password - use something strong
db_password = "|zO+!IhH.2<e"
db_name     = "dronedb"
db_username = "droneadmin"

# Amazon Linux 2 AMI (us-east-1) - update this if you change region
ami_id        = "ami-02dfbd4ff395f2a1b"
instance_type = "t3.micro"

# Name of the EC2 key pair you created in the AWS console
key_name = "drone-pipeline-key"

# Your GitHub repo (EC2 pulls code from here on boot)
repo_url = "https://github.com/AymanJabr/AWS-NDVI-photos"

# Email for CloudWatch alarm notifications
alert_email = "aymanjaber2012@gmail.com"
