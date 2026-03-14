"""
Integration tests for the processor loop.
All AWS calls are mocked — no real AWS account needed to run these.
"""

import json
from unittest.mock import MagicMock, patch, call

import numpy as np
import pytest

import processor


SAMPLE_S3_EVENT = {
    "Records": [
        {
            "s3": {
                "bucket": {"name": "drone-pipeline-input-123"},
                "object": {"key": "field_photo.jpg"},
            }
        }
    ]
}


class TestParseS3Event:
    def test_extracts_bucket_and_key(self):
        body = json.dumps(SAMPLE_S3_EVENT)
        pairs = processor._parse_s3_event(body)
        assert pairs == [("drone-pipeline-input-123", "field_photo.jpg")]

    def test_empty_records_returns_empty_list(self):
        body = json.dumps({"Records": []})
        assert processor._parse_s3_event(body) == []

    def test_multiple_records(self):
        event = {
            "Records": [
                {"s3": {"bucket": {"name": "b"}, "object": {"key": "a.jpg"}}},
                {"s3": {"bucket": {"name": "b"}, "object": {"key": "b.jpg"}}},
            ]
        }
        pairs = processor._parse_s3_event(json.dumps(event))
        assert len(pairs) == 2


class TestProcessImage:
    """Tests process_image() with mocked S3, NDVI, and DB calls."""

    def _make_mock_db(self):
        conn = MagicMock()
        return conn

    @patch("processor.s3")
    @patch("processor.db")
    @patch("processor.calculate_ndvi")
    @patch("processor.render_heatmap")
    @patch("processor.ndvi_stats")
    @patch("processor._emit_custom_metric")
    def test_happy_path(self, mock_metric, mock_stats, mock_render, mock_ndvi,
                        mock_db_mod, mock_s3):
        mock_ndvi.return_value = np.zeros((10, 10), dtype=np.float32)
        mock_stats.return_value = {
            "ndvi_mean": 0.4, "ndvi_min": -0.1, "ndvi_max": 0.9,
            "ndvi_std": 0.2, "veg_cover_pct": 60.0,
        }
        mock_db_mod.insert_job.return_value = 42
        conn = self._make_mock_db()

        processor.process_image("drone-input-bucket", "photo.jpg", conn)

        mock_s3.download_file.assert_called_once()
        mock_ndvi.assert_called_once()
        mock_render.assert_called_once()
        mock_s3.upload_file.assert_called_once()
        mock_db_mod.update_job_success.assert_called_once()
        mock_db_mod.update_job_failure.assert_not_called()

    @patch("processor.s3")
    @patch("processor.db")
    @patch("processor.calculate_ndvi", side_effect=Exception("corrupt image"))
    @patch("processor._emit_custom_metric")
    def test_processing_failure_propagates(self, mock_metric, mock_ndvi,
                                           mock_db_mod, mock_s3):
        mock_db_mod.insert_job.return_value = 99
        conn = self._make_mock_db()

        with pytest.raises(Exception, match="corrupt image"):
            processor.process_image("bucket", "bad.jpg", conn)
