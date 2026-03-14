#!/bin/bash
set -e

# ---- System packages ----
yum update -y
yum install -y python3 python3-pip git

# ---- Clone the app ----
mkdir -p /app
cd /app
git clone ${repo_url} .

# ---- Python dependencies ----
pip3 install -r processing/requirements.txt

# ---- Environment file (read by systemd service) ----
cat > /etc/drone-processor.env << EOF
AWS_REGION=${aws_region}
SQS_QUEUE_URL=${sqs_queue_url}
S3_INPUT_BUCKET=${s3_input_bucket}
S3_OUTPUT_BUCKET=${s3_output_bucket}
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD_SSM_PARAM=/${project_name}/db/password
CLOUDWATCH_LOG_GROUP=${log_group_name}
EOF

chmod 600 /etc/drone-processor.env

# ---- systemd service ----
cat > /etc/systemd/system/drone-processor.service << EOF
[Unit]
Description=Drone Image Processor
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/app
EnvironmentFile=/etc/drone-processor.env
ExecStart=/usr/bin/python3 processing/processor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable drone-processor
systemctl start drone-processor
