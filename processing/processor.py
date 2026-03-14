"""
Main processing loop.

Flow:
  1. Poll SQS(Simple Queue Service) for S3 upload events (long polling, 20s wait)
  2. For each message: download image → calculate NDVI → upload heatmap → save to DB
  3. On success: delete SQS message
  4. On failure: leave message in queue — it will retry up to 3 times then go to DLQ(Dead Letter Queue)
"""

import json
import logging
import os
import tempfile
from pathlib import Path

import boto3 #AWS SDK for Python, named after an Amazonian dolphin
import watchtower #AWS CloudWatch for Python

from ndvi import calculate_ndvi, render_heatmap, ndvi_stats
import db


# ---- Logging setup ----
# Routes Python's standard logging to CloudWatch Logs via watchtower
log_group = os.environ.get("CLOUDWATCH_LOG_GROUP", "/drone-pipeline/processing")
region    = os.environ.get("AWS_REGION", "eu-west-1")

cw_handler = watchtower.CloudWatchLogHandler(
    log_group=log_group,
    stream_name="processor",
    boto3_client=boto3.client("logs", region_name=region),
)
cw_handler.setFormatter(logging.Formatter(
    '{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
))

logger = logging.getLogger("processor")
logger.setLevel(logging.INFO)
logger.addHandler(cw_handler)
logger.addHandler(logging.StreamHandler())  # also print to stdout → journald


# ---- AWS clients ----
sqs = boto3.client("sqs",    region_name=region)
s3  = boto3.client("s3",     region_name=region)
cw  = boto3.client("cloudwatch", region_name=region)

QUEUE_URL        = os.environ["SQS_QUEUE_URL"]
INPUT_BUCKET     = os.environ["S3_INPUT_BUCKET"]
OUTPUT_BUCKET    = os.environ["S3_OUTPUT_BUCKET"]


def _parse_s3_event(body: str) -> list[tuple[str, str]]:
    """
    Extract (bucket, key) pairs from an S3 event notification.
    S3 → SQS notifications wrap Records directly in the message body.
    """
    event = json.loads(body)
    records = event.get("Records", [])
    return [(r["s3"]["bucket"]["name"], r["s3"]["object"]["key"]) for r in records]


def _emit_custom_metric(name: str, value: float, unit: str = "Count") -> None:
    """Push a custom metric to CloudWatch for the dashboard."""
    try:
        cw.put_metric_data(
            Namespace="DronePipeline",
            MetricData=[{
                "MetricName": name,
                "Value": value,
                "Unit": unit,
            }],
        )
    except Exception:
        pass  # metrics are best-effort; never crash the main loop over this


def process_image(bucket: str, key: str, db_conn) -> None:
    """Download, process, and store results for a single image."""
    logger.info(f"Starting job | input_key={key}")
    job_id = db.insert_job(db_conn, key)

    with tempfile.TemporaryDirectory() as tmpdir:
        local_input  = str(Path(tmpdir) / Path(key).name)
        local_output = str(Path(tmpdir) / ("ndvi_" + Path(key).stem + ".png"))

        # 1. Download from S3
        s3.download_file(bucket, key, local_input)
        logger.info(f"Downloaded | job_id={job_id} key={key}")

        # 2. NDVI calculation
        ndvi    = calculate_ndvi(local_input)
        stats   = ndvi_stats(ndvi)
        render_heatmap(ndvi, local_output)
        logger.info(f"Processed | job_id={job_id} ndvi_mean={stats['ndvi_mean']:.4f} "
                    f"veg_cover={stats['veg_cover_pct']:.1f}%")

        # 3. Upload heatmap to output bucket
        output_key = f"heatmaps/{Path(local_output).name}"
        s3.upload_file(local_output, OUTPUT_BUCKET, output_key)
        logger.info(f"Uploaded heatmap | job_id={job_id} output_key={output_key}")

        # 4. Persist metadata to RDS
        db.update_job_success(db_conn, job_id, output_key, stats)

        # 5. Custom CloudWatch metric (visible in dashboard)
        _emit_custom_metric("ImagesProcessed", 1)
        _emit_custom_metric("NDVIMean", stats["ndvi_mean"], "None")

    logger.info(f"Job complete | job_id={job_id}")


def run() -> None:
    logger.info("Drone processor starting up...")

    db_conn = db.get_connection()
    db.ensure_table_exists(db_conn)
    logger.info("DB connection established, jobs table ready")

    while True:
        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,   # long polling — reduces empty-receive costs
            AttributeNames=["ApproximateReceiveCount"],
        )

        messages = response.get("Messages", [])
        if not messages:
            continue

        message = messages[0]
        receipt = message["ReceiptHandle"]

        try:
            pairs = _parse_s3_event(message["Body"])
            if not pairs:
                logger.warning("SQS message contained no S3 records — deleting")
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt)
                continue

            for bucket, key in pairs:
                process_image(bucket, key, db_conn)

            # Delete only after successful processing
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt)

        except Exception as exc:
            logger.error(f"Processing failed: {exc}", exc_info=True)
            _emit_custom_metric("ProcessingErrors", 1)
            # Do NOT delete the message — SQS will redeliver it (up to maxReceiveCount=3)
            # After 3 failures it automatically moves to the DLQ


if __name__ == "__main__":
    run()
