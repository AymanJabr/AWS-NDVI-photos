#!/bin/bash
# -----------------------------------------------------------------------
# upload_test_image.sh
# Quick demo helper: upload a sample image to S3 to trigger the pipeline.
#
# Usage:
#   ./scripts/upload_test_image.sh [path/to/image.jpg]
#
# If no image is provided, a small synthetic RGB test image is generated
# using Python so you can demo without needing a real drone photo.
# -----------------------------------------------------------------------

set -e

# Read bucket name from terraform output (or override with env var)
INPUT_BUCKET="${INPUT_BUCKET:-$(cd terraform && terraform output -raw s3_input_bucket)}"
IMAGE_PATH="${1:-}"

if [ -z "$IMAGE_PATH" ]; then
    echo "No image provided — generating synthetic test image..."

    TMPFILE=$(mktemp /tmp/test_image_XXXX.jpg)
    python3 - <<EOF
from PIL import Image
import numpy as np

# Synthetic aerial field image: mix of green (vegetation) and brown (soil)
width, height = 512, 512
arr = np.zeros((height, width, 3), dtype=np.uint8)

# Background: brownish soil
arr[:, :] = [120, 90, 60]

# Patches of green vegetation
import random
random.seed(42)
for _ in range(30):
    cx, cy = random.randint(50, 460), random.randint(50, 460)
    r = random.randint(20, 80)
    Y, X = np.ogrid[:height, :width]
    mask = (X - cx)**2 + (Y - cy)**2 <= r**2
    green_val = random.randint(120, 200)
    arr[mask] = [40, green_val, 40]

img = Image.fromarray(arr, mode='RGB')
img.save("$TMPFILE", quality=90)
print(f"Saved synthetic image to $TMPFILE ({width}x{height}px)")
EOF
    IMAGE_PATH="$TMPFILE"
fi

FILENAME=$(basename "$IMAGE_PATH")
S3_KEY="uploads/$(date +%Y-%m-%d_%H-%M-%S)_${FILENAME}"

echo ""
echo "Uploading: $IMAGE_PATH"
echo "Bucket:    $INPUT_BUCKET"
echo "S3 key:    $S3_KEY"
echo ""

aws s3 cp "$IMAGE_PATH" "s3://${INPUT_BUCKET}/${S3_KEY}"

echo ""
echo "Upload complete. The pipeline should now:"
echo "  1. S3 → SQS notification fires automatically"
echo "  2. EC2 worker picks up the SQS message"
echo "  3. NDVI heatmap saved to the output bucket"
echo "  4. Job metadata written to RDS"
echo ""
echo "Watch it happen:"
echo "  CloudWatch logs:  aws logs tail /drone-pipeline/processing --follow"
echo "  SQS queue depth:  aws sqs get-queue-attributes \\"
echo "      --queue-url \$(cd terraform && terraform output -raw sqs_queue_url) \\"
echo "      --attribute-names ApproximateNumberOfMessagesVisible"
echo ""
echo "Query results from RDS (SSH into EC2 first):"
echo "  psql -h \$DB_HOST -U droneadmin -d dronedb -c 'SELECT * FROM jobs ORDER BY created_at DESC LIMIT 5;'"
