"""
Unit tests for NDVI calculation logic.
No AWS calls — pure numpy/image math.
"""

import tempfile
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from ndvi import calculate_ndvi, render_heatmap, ndvi_stats


def _make_rgb_image(r: int, g: int, b: int, size=(64, 64)) -> str:
    """Create a solid-colour PNG in a temp file and return the path."""
    arr = np.full((*size, 3), [r, g, b], dtype=np.uint8)
    path = tempfile.mktemp(suffix=".png")
    Image.fromarray(arr).save(path)
    return path


class TestCalculateNDVI:
    def test_pure_green_image_gives_positive_ndvi(self):
        # Green > Red → positive NDVI → healthy vegetation
        path = _make_rgb_image(r=50, g=200, b=50)
        ndvi = calculate_ndvi(path)
        assert ndvi.mean() > 0

    def test_pure_red_image_gives_negative_ndvi(self):
        # Red > Green → negative NDVI → bare soil / stressed
        path = _make_rgb_image(r=200, g=50, b=50)
        ndvi = calculate_ndvi(path)
        assert ndvi.mean() < 0

    def test_equal_red_green_gives_near_zero(self):
        path = _make_rgb_image(r=128, g=128, b=0)
        ndvi = calculate_ndvi(path)
        assert abs(ndvi.mean()) < 0.01

    def test_pure_black_does_not_crash(self):
        # Epsilon prevents division by zero
        path = _make_rgb_image(r=0, g=0, b=0)
        ndvi = calculate_ndvi(path)
        assert np.isfinite(ndvi).all()

    def test_output_shape_matches_input(self):
        path = _make_rgb_image(r=100, g=150, b=80, size=(32, 48))
        ndvi = calculate_ndvi(path)
        assert ndvi.shape == (32, 48)

    def test_output_values_within_range(self):
        path = _make_rgb_image(r=120, g=180, b=60)
        ndvi = calculate_ndvi(path)
        assert ndvi.min() >= -1.0
        assert ndvi.max() <= 1.0


class TestNDVIStats:
    def test_stats_keys_present(self):
        ndvi = np.array([[0.5, 0.3], [-0.1, 0.8]], dtype=np.float32)
        stats = ndvi_stats(ndvi)
        assert {"ndvi_mean", "ndvi_min", "ndvi_max", "ndvi_std", "veg_cover_pct"} == set(stats)

    def test_veg_cover_pct_range(self):
        ndvi = np.array([[0.5, 0.1], [0.4, -0.2]], dtype=np.float32)
        stats = ndvi_stats(ndvi)
        assert 0.0 <= stats["veg_cover_pct"] <= 100.0

    def test_all_high_ndvi_gives_100_pct_cover(self):
        ndvi = np.full((10, 10), 0.8, dtype=np.float32)
        stats = ndvi_stats(ndvi)
        assert stats["veg_cover_pct"] == pytest.approx(100.0)

    def test_all_negative_ndvi_gives_0_pct_cover(self):
        ndvi = np.full((10, 10), -0.5, dtype=np.float32)
        stats = ndvi_stats(ndvi)
        assert stats["veg_cover_pct"] == pytest.approx(0.0)


class TestRenderHeatmap:
    def test_creates_output_file(self):
        ndvi = np.random.uniform(-1, 1, (64, 64)).astype(np.float32)
        output = tempfile.mktemp(suffix=".png")
        render_heatmap(ndvi, output)
        assert Path(output).exists()
        assert Path(output).stat().st_size > 0
