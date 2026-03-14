"""
NDVI (Normalised Difference Vegetation Index) calculation from standard RGB images.

Real multispectral sensors measure a dedicated Near-Infrared (NIR) band.
For this demo we approximate NIR with the Green channel — a recognized proxy
used when only RGB data is available (sometimes called "visible NDVI" or VNDVI).

    NDVI = (NIR - Red) / (NIR + Red)
    VNDVI ≈ (Green - Red) / (Green + Red)

Result range: [-1.0, 1.0]
  > 0.3  healthy vegetation (greens)
  ~ 0.0  bare soil / rock (yellow)
  < 0.0  water / shadow (reds)
"""

import numpy as np
from PIL import Image
import matplotlib
import matplotlib.pyplot as plt

# Use non-interactive backend — safe for running headless on EC2
matplotlib.use("Agg")


def calculate_ndvi(image_path: str) -> np.ndarray:
    """
    Load an RGB image and return a 2D float32 array of NDVI values in [-1, 1].
    """
    img = Image.open(image_path).convert("RGB")
    arr = np.array(img, dtype=np.float32)

    red   = arr[:, :, 0]
    green = arr[:, :, 1]  # used as NIR proxy

    # Small epsilon avoids division by zero for pure black pixels
    ndvi = (green - red) / (green + red + 1e-6)
    return ndvi.astype(np.float32)


def render_heatmap(ndvi: np.ndarray, output_path: str) -> None:
    """
    Save a colour-mapped NDVI heatmap as a PNG file.
    RdYlGn: red (stressed/bare) → yellow (moderate) → green (healthy).
    """
    fig, ax = plt.subplots(figsize=(10, 8))
    im = ax.imshow(ndvi, cmap="RdYlGn", vmin=-1, vmax=1)
    plt.colorbar(im, ax=ax, label="NDVI (approx.)")
    ax.set_title("Vegetation Index — NDVI (RGB approximation)")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def ndvi_stats(ndvi: np.ndarray) -> dict:
    """Return a summary dict of NDVI statistics for storing in the database."""
    return {
        "ndvi_mean":  float(np.mean(ndvi)),
        "ndvi_min":   float(np.min(ndvi)),
        "ndvi_max":   float(np.max(ndvi)),
        "ndvi_std":   float(np.std(ndvi)),
        # % of pixels above 0.3 = approximate healthy vegetation cover
        "veg_cover_pct": float(np.mean(ndvi > 0.3) * 100),
    }
