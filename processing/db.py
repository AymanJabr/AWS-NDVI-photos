"""
RDS PostgreSQL connection and job metadata persistence.

The DB password is never stored in plaintext — it is fetched at runtime
from AWS SSM(Systems Manager - (was Simple Systems Manager)) Parameter Store using the EC2 instance role.
"""

import os
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor


def _fetch_db_password() -> str:
    """Read the DB password from SSM Parameter Store."""
    param_name = os.environ["DB_PASSWORD_SSM_PARAM"]
    ssm = boto3.client("ssm", region_name=os.environ["AWS_REGION"])
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    return response["Parameter"]["Value"]


def get_connection():
    """Return a psycopg2 connection using environment variables + SSM for password."""
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=_fetch_db_password(),
        connect_timeout=10,
    )


def ensure_table_exists(conn) -> None:
    """Create the jobs table if it doesn't exist yet."""
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS jobs (
                id           SERIAL PRIMARY KEY,
                input_key    TEXT        NOT NULL,
                output_key   TEXT,
                status       TEXT        NOT NULL DEFAULT 'processing',
                ndvi_mean    FLOAT,
                ndvi_min     FLOAT,
                ndvi_max     FLOAT,
                ndvi_std     FLOAT,
                veg_cover_pct FLOAT,
                error_msg    TEXT,
                created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
    conn.commit()


def insert_job(conn, input_key: str) -> int:
    """Insert a new job record and return its ID."""
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO jobs (input_key, status) VALUES (%s, 'processing') RETURNING id",
            (input_key,),
        )
        job_id = cur.fetchone()[0]
    conn.commit()
    return job_id


def update_job_success(conn, job_id: int, output_key: str, stats: dict) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE jobs SET
                status        = 'completed',
                output_key    = %s,
                ndvi_mean     = %s,
                ndvi_min      = %s,
                ndvi_max      = %s,
                ndvi_std      = %s,
                veg_cover_pct = %s,
                updated_at    = NOW()
            WHERE id = %s
            """,
            (
                output_key,
                stats["ndvi_mean"],
                stats["ndvi_min"],
                stats["ndvi_max"],
                stats["ndvi_std"],
                stats["veg_cover_pct"],
                job_id,
            ),
        )
    conn.commit()


def update_job_failure(conn, job_id: int, error_msg: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE jobs SET status = 'failed', error_msg = %s, updated_at = NOW() WHERE id = %s",
            (error_msg, job_id),
        )
    conn.commit()
