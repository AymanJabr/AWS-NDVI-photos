# Project Plan: Drone Image Processing Pipeline on AWS

## Concept

Simulate what Wesii actually does: a pipeline that ingests aerial/drone images,
runs multispectral analysis (NDVI — Normalized Difference Vegetation Index),
and stores the results. All infrastructure is managed with Terraform, deployed
via Jenkins CI/CD, with full observability via CloudWatch.

**The "hook" for the interview:** NDVI is the exact type of analysis used in
precision agriculture and solar farm vegetation monitoring — Wesii's core domain.

You don't need real multispectral hardware; you can simulate it from a standard
RGB image, which is scientifically valid as a demonstration.
---

## Architecture Overview

```
Developer pushes code
        │
        ▼
  [Jenkins CI/CD]
  - Run tests
  - Deploy updated processing script to EC2 via SSH
        │
        ▼
  User uploads image
        │
        ▼
  [S3 Input Bucket]
        │ (Event Notification)
        ▼
    [SQS Queue]
        │ (EC2 worker polls)
        ▼
    [EC2 Worker]
    - Download image from S3
    - Run NDVI(Normalized Difference Vegetation Index) processing (Python)
    - Save result image to S3 Output Bucket
    - Save job metadata to RDS PostgreSQL
        │
        ├──► [S3 Output Bucket]  (heatmap image)
        │
        └──► [RDS PostgreSQL]    (job_id, filename, status, ndvi_mean, timestamp)
                │
                ▼
        [CloudWatch]
        - EC2 system metrics
        - Application logs (processing start/end/error)
        - Alarm: if SQS queue depth > threshold → SNS email alert
        - Alarm: if EC2 CPU > 80% for 5 min → alert
```

**VPC Layout:**
- Public subnet: EC2 (needs internet for Jenkins SSH + package installs), Jenkins
- Private subnet: RDS (never exposed to internet)
- Security groups: EC2 can reach RDS on port 5432; RDS blocks all else

---

## Tech Stack

| Tool | Role |
|---|---|
| Terraform | Provision all AWS infrastructure (IaC) |
| AWS EC2 | Worker server that runs the image processing |
| AWS S3 | Input bucket (raw images) + Output bucket (results) |
| AWS SQS | Message queue: decouples S3 upload from EC2 processing |
| AWS RDS (PostgreSQL) | Stores job metadata |
| AWS IAM | EC2 instance role — least-privilege access to S3, SQS, RDS |
| AWS VPC | Isolated network, public/private subnets |
| AWS CloudWatch | Logs, metrics dashboards, alarms |
| Jenkins | CI/CD: test → deploy processing code to EC2 |
| Python (Pillow/NumPy) | Image processing logic (NDVI calculation) |
| Git/GitHub | Source control, triggers Jenkins builds |

---

## What NDVI Looks Like in Code (The Core Logic)

NDVI = (NIR - Red) / (NIR + Red)

For a standard RGB image we simulate NIR with the Green channel:
  NDVI_approx = (G - R) / (G + R + ε)

Result: a float array in [-1, 1] range, visualized as a heatmap
(red = stressed/bare soil, green = healthy vegetation).

This is a known technique used when real multispectral sensors aren't available.
It's not perfect science, but it's a valid and recognized proxy — good enough to
explain the pipeline architecture, which is the real subject of the interview.

---

## Project File Structure

```
satellite-image-pipeline/
│
├── terraform/
│   ├── main.tf              # Root module: ties everything together
│   ├── variables.tf         # Input variables (region, instance type, db password...)
│   ├── outputs.tf           # EC2 IP, S3 bucket names, RDS endpoint
│   │
│   └── modules/
│       ├── networking/      # VPC, subnets (public/private), IGW, route tables, SGs
│       ├── compute/         # EC2 instance, key pair, user_data bootstrap script
│       ├── storage/         # S3 input + output buckets, SQS queue, S3→SQS notification
│       ├── database/        # RDS PostgreSQL, subnet group, parameter group
│       ├── monitoring/      # CloudWatch log group, metric alarms, SNS topic
│       └── iam/             # EC2 instance profile, role, policies (S3+SQS+CloudWatch)
│
├── processing/
│   ├── processor.py         # Main worker: poll SQS → download → process → upload → save to DB
│   ├── ndvi.py              # NDVI calculation logic (pure functions, easy to unit test)
│   ├── db.py                # RDS connection + insert job metadata
│   ├── requirements.txt     # Pillow, numpy, boto3, psycopg2-binary
│   └── tests/
│       ├── test_ndvi.py     # Unit tests for NDVI logic
│       └── test_processor.py # Integration tests (mocked AWS)
│
├── jenkins/
│   └── Jenkinsfile          # Pipeline: checkout → test → deploy to EC2 via SSH
│
├── scripts/
│   ├── bootstrap_ec2.sh     # User-data: install Python, deps, set up systemd service
│   └── upload_test_image.sh # Quick demo: upload a sample image to S3 to trigger pipeline
│
└── README.md                # Architecture diagram + setup instructions
```

---

## Build Phases

### Phase 1 — Terraform Infrastructure (Start here)

**Goal:** `terraform apply` stands up the entire environment from zero.

Steps:
1. Write `modules/networking`: VPC (10.0.0.0/16), public subnet (10.0.1.0/24),
   private subnet (10.0.2.0/24), Internet Gateway, route tables, security groups.
2. Write `modules/iam`: EC2 instance role with policies for:
   - S3: GetObject, PutObject on specific buckets
   - SQS: ReceiveMessage, DeleteMessage on specific queue
   - CloudWatch: PutLogEvents, PutMetricData
   - SSM (optional): for parameter store access to DB password
3. Write `modules/storage`:
   - S3 input bucket (private)
   - S3 output bucket (private, with lifecycle rule: delete after 90 days)
   - SQS queue (with dead-letter queue for failed messages)
   - S3 event notification → SQS on `s3:ObjectCreated:*`
4. Write `modules/database`:
   - RDS PostgreSQL (db.t3.micro — free tier eligible)
   - In private subnet, no public access
   - Store DB password in AWS SSM Parameter Store (or just variable for demo)
5. Write `modules/compute`:
   - EC2 (t2.micro or t3.micro), in public subnet
   - Attach IAM instance profile from step 2
   - `user_data` script: install Python 3, pip, clone repo from GitHub, install deps,
     set up `processor.py` as a systemd service that auto-starts
6. Write `modules/monitoring`:
   - CloudWatch Log Group: `/drone-pipeline/processing`
   - Alarm: SQSApproximateNumberOfMessagesVisible > 10 for 5 min → SNS email
   - Alarm: EC2 CPUUtilization > 80% for 5 min → SNS email
   - Dashboard: SQS depth, EC2 CPU, processed image count (custom metric)

**Deliverable:** Run `terraform apply`, get a live EC2 + RDS + S3 + SQS.

---

### Phase 2 — Processing Script

**Goal:** Python worker that reads from SQS, processes the image, writes results.

`ndvi.py`:
```python
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt

def calculate_ndvi(image_path: str) -> np.ndarray:
    img = Image.open(image_path).convert("RGB")
    arr = np.array(img, dtype=np.float32)
    r, g = arr[:,:,0], arr[:,:,1]
    ndvi = (g - r) / (g + r + 1e-6)  # epsilon avoids div by zero
    return ndvi

def render_heatmap(ndvi: np.ndarray, output_path: str) -> None:
    plt.figure(figsize=(10, 8))
    plt.imshow(ndvi, cmap="RdYlGn", vmin=-1, vmax=1)
    plt.colorbar(label="NDVI")
    plt.title("Vegetation Index (NDVI)")
    plt.axis("off")
    plt.savefig(output_path, bbox_inches="tight")
    plt.close()
```

`processor.py` (main loop):
```
while True:
    messages = sqs.receive_message(QueueUrl=..., MaxNumberOfMessages=1, WaitTimeSeconds=20)
    for message in messages:
        - parse S3 key from message body
        - download image from S3 input bucket to /tmp/
        - calculate NDVI → render heatmap → save to /tmp/
        - upload heatmap to S3 output bucket
        - insert job metadata into RDS: (job_id, input_key, output_key, ndvi_mean, status, timestamp)
        - send log to CloudWatch Logs
        - delete message from SQS
```

`db.py`:
- Simple psycopg2 connection
- `jobs` table: id, input_key, output_key, ndvi_mean, status, created_at
- On startup: CREATE TABLE IF NOT EXISTS

---

### Phase 3 — Jenkins CI/CD Pipeline

**Goal:** Push to GitHub → Jenkins runs tests → deploys updated code to EC2.

`Jenkinsfile`:
```groovy
pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps { git 'https://github.com/YOUR_USER/satellite-image-pipeline' }
        }
        stage('Test') {
            steps {
                sh 'cd processing && pip install -r requirements.txt'
                sh 'cd processing && python -m pytest tests/ -v'
            }
        }
        stage('Deploy') {
            steps {
                // Copy updated files to EC2 and restart the systemd service
                sh '''
                    scp -i /var/jenkins/ec2-key.pem -r processing/ ec2-user@${EC2_IP}:/app/
                    ssh -i /var/jenkins/ec2-key.pem ec2-user@${EC2_IP} "sudo systemctl restart drone-processor"
                '''
            }
        }
    }
    post {
        failure {
            // In production this would send an alert; for demo just print
            echo 'Pipeline failed!'
        }
    }
}
```

Jenkins runs locally (or on a free EC2) with:
- GitHub webhook or polling every minute
- EC2 SSH key stored as a Jenkins credential

---

### Phase 4 — Demo Flow (for the interview)

1. Open CloudWatch dashboard — show it's live.
2. Run: `./scripts/upload_test_image.sh sample_field.jpg`
3. Show S3 input bucket → file appeared.
4. Show SQS console → message count briefly goes to 1.
5. Show EC2 (via SSH or CloudWatch Logs) → processing log lines appear in real-time.
6. Show S3 output bucket → heatmap image appeared.
7. Query RDS:
   ```sql
   SELECT * FROM jobs ORDER BY created_at DESC LIMIT 5;
   ```
   Show the NDVI mean value, status = 'completed'.
8. Show CloudWatch Log Group → structured log entries.
9. Show Terraform code — "this entire environment is defined in ~200 lines of HCL."
10. Show Jenkins pipeline — "CI/CD: one push deploys new processing logic in ~60 seconds."

---

## What This Demonstrates to Wesii

| Their Requirement | What You Show |
|---|---|
| Terraform IaC | Full modular Terraform (VPC, EC2, S3, RDS, SQS, IAM, CloudWatch) |
| AWS EC2 | Worker server running a live processing loop |
| AWS S3 | Input/output buckets, event notifications |
| AWS IAM | Least-privilege instance role, no hardcoded credentials |
| AWS VPC | Public/private subnets, security groups, RDS in private subnet |
| AWS RDS | PostgreSQL job metadata store |
| AWS CloudWatch | Logs, metrics, alarms, dashboard |
| Jenkins / CI/CD | Automated test → deploy pipeline on git push |
| Image processing domain | NDVI heatmap — literally their business |
| Python (nice to have) | Core processing logic |
| Resilience & observability | DLQ, CloudWatch alarms, structured logging |
| Scalability thinking | SQS decoupling means EC2 can be swapped for Auto Scaling Group trivially |

---

Next steps to make it live:
  1. Copy terraform/terraform.tfvars.example → terraform/terraform.tfvars and fill in your AWS account ID, key pair name, and a DB
  password
  2. cd terraform && terraform init && terraform apply
  3. Push the code to GitHub (EC2 will clone it on first boot)
  4. Run ./scripts/upload_test_image.sh to trigger a live demo



----

## Tips for the Interview

- **Lead with the architecture diagram.** Draw it on a whiteboard or have a diagram ready.
  It shows systems thinking before any code.
- **Emphasize NDVI.** Say: "I wanted it to map directly to your domain —
  vegetation health analysis is a core use case for multispectral drone data."
- **Show the Terraform state.** `terraform show` output proves the infra is real.
- **Have CloudWatch open live.** Real-time logs during the demo are impressive.
- **Mention what you'd add at scale:** Auto Scaling Group instead of single EC2,
  ECS/Fargate for containerized workers, Spot Instances for cost savings.
  This shows you think beyond the MVP.
