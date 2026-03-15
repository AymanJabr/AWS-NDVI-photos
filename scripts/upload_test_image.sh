# Quick demo helper: upload a sample image to S3 to trigger the pipeline.
#
# Usage:
#   ./scripts/upload_test_image.sh [path/to/image.jpg]
#
# If no image is provided, pass one from scripts/image_examples/

set -e

# Read bucket name from terraform output (or override with env var)
INPUT_BUCKET="drone-pipeline-input-137378241202"
IMAGE_PATH="${1:?Usage: ./scripts/upload_test_image.sh path/to/image.jpg}"

FILENAME=$(basename "$IMAGE_PATH")
S3_KEY="uploads/$(date +%Y-%m-%d_%H-%M-%S)_${FILENAME}"

echo ""
echo "Uploading: $IMAGE_PATH"
echo "Bucket:    $INPUT_BUCKET"
echo "S3 key:    $S3_KEY"
echo ""

aws s3 cp "$IMAGE_PATH" "s3://${INPUT_BUCKET}/${S3_KEY}"

# Wait for the heatmap to appear in the output bucket then download it
OUTPUT_BUCKET="drone-pipeline-output-137378241202"
STEM=$(basename "${S3_KEY%.jpg}")
STEM=$(basename "${STEM%.png}")
OUTPUT_KEY="heatmaps/ndvi_${STEM}.png"
DEST_DIR="$(dirname "$0")/example_outputs"
mkdir -p "$DEST_DIR"

echo "Waiting for heatmap..."
for i in $(seq 1 30); do
    if aws s3 ls "s3://${OUTPUT_BUCKET}/${OUTPUT_KEY}" --region us-east-1 > /dev/null 2>&1; then
        aws s3 cp "s3://${OUTPUT_BUCKET}/${OUTPUT_KEY}" "$DEST_DIR/" --region us-east-1
        echo "Saved to $DEST_DIR/$(basename "$OUTPUT_KEY")"
        exit 0
    fi
    sleep 2
done

echo "Timed out waiting for heatmap — check CloudWatch logs for errors"
