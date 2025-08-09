import os
import sys
from pathlib import Path
from typing import Dict, Any

import requests
from dotenv import load_dotenv


def load_api_key() -> str:
    """Load STABILITY_API_KEY from environment (.env supported)."""
    # Load variables from .env if present
    load_dotenv()
    api_key = os.getenv("STABILITY_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError(
            "Missing STABILITY_API_KEY. Set it in your environment or in a .env file."
        )
    return api_key


def make_multipart_fields(params: Dict[str, Any]) -> Dict[str, Any]:
    """Convert params to a multipart/form-data dict, excluding empty values."""
    files: Dict[str, Any] = {}
    for key in [
        "prompt",
        "negative_prompt",
        "aspect_ratio",
        "seed",
        "output_format",
        "style_preset",
    ]:
        value = params.get(key, None)
        if value is None:
            continue
        value_str = str(value)
        if value_str == "":
            continue
        files[key] = (None, value_str)
    return files


def send_generation_request(host: str, params: Dict[str, Any]) -> requests.Response:
    """Send a text-to-image generation request to Stability API and return the raw response.

    Expects image bytes on success with headers containing 'finish-reason' and 'seed'.
    """
    api_key = load_api_key()

    headers = {
        "Authorization": f"Bearer {api_key}",
        # Prefer image bytes; server returns image on success
        "Accept": "image/*",
    }

    # The SD3/SD3.5 endpoint expects multipart/form-data, even for text fields
    files = make_multipart_fields(params)

    response = requests.post(host, headers=headers, files=files, timeout=120)

    # If not 200, try to surface any JSON error details
    if response.status_code != 200:
        content_type = response.headers.get("Content-Type", "")
        if "application/json" in content_type:
            try:
                err = response.json()
            except Exception:
                err = {"error": response.text}
            raise RuntimeError(
                f"Generation failed {response.status_code}: {err}"
            )
        raise RuntimeError(
            f"Generation failed {response.status_code}: {response.text[:500]}"
        )

    return response


def main() -> int:
    # Themed 16-bit 2D pixel-art style constraints
    base_style = (
        "16-bit 2D pixel art sprite, SNES/Genesis-era aesthetic, limited 16-color palette, "
        "strong black outline, clean dithering, sharp pixels, no anti-aliasing, flat shading, "
        "high-contrast readable shapes, single sprite centered, plain background."
    )
    enforce_theme = (
        "Do NOT make 3D, photorealistic, painterly, vector, or smooth gradients. "
        "No text, watermark, UI, borders, or frames."
    )

    # Asset-specific prompts
    assets: Dict[str, str] = {
        "pixel_knight": (
            "Generate a sprite sheet for a knight character in pixel art style: short, stout, very small chibi proportions, "
            "wearing simple steel armor with a small red plume, side view facing right. Include 4 frames of a walking animation "
            "and 3 frames of an idle pose; also include frames of taking damage and a death animation. Each frame is 32x32 pixels, "
            "clean black outlines, transparent background, arranged in a neat grid with equal spacing; consistent 16-bit palette."
        ),
        "pixel_slime": (
            "Generate a sprite sheet for a green, slightly menacing slime enemy in pixel art style, side view facing right. "
            "Include 4 frames of a sliding/walking animation and 3 frames of an idle wobble; also include damage and death frames. "
            "Each frame is 32x32 pixels with clean black outline and a transparent background, arranged in a neat grid; consistent 16-bit palette."
        ),
        "pixel_tileset": (
            "Create a square 1:1 image containing a compact tileset: a grid of small 2D 16-bit pixel blocks (square tiles seen straight-on, not isometric), "
            "designed for a 2D platformer. Include multiple terrains: grass with dirt, stone/brick, sand, snow/ice, wood, and metal. "
            "Each tile is seamless and perfectly square with high-contrast readable edges, consistent limited palette, and clearly separated in a regular grid on a plain or transparent background."
        ),
        "pixel_platforms": (
            "set of platform sprites for a 2D platformer: small tileable platform segments with metal and stone variants, "
            "clearly separated pieces on a plain background, readable edges for movement"
        ),
        "pixel_coin": (
            "tiny coin item facing right: bright gold coin with black outline, high contrast, single sprite centered"
        ),
    }

    negative_prompt = (
        "photorealistic, realistic, 3d, rendering, soft gradients, blurry, low-contrast, noise, "
        "text, watermark, signature, frame, border, background scene, detailed scenery"
    )

    aspect_ratio = "1:1"
    # Use PNG for pixel art
    output_format = "png"

    host = "https://api.stability.ai/v2beta/stable-image/generate/ultra"

    # Iterate and generate each asset
    for asset_name, asset_desc in assets.items():
        prompt = f"{base_style} {enforce_theme} {asset_desc}"

        params = {
            "prompt": prompt,
            "negative_prompt": negative_prompt,
            "aspect_ratio": aspect_ratio,
            # Omit seed to allow API to choose a random seed
            # "seed": None,
            "output_format": output_format,
            # Ultra supports an optional style preset; keep pixel-art to reinforce theme
            "style_preset": "pixel-art",
        }

        print(f"Generating {asset_name}...", flush=True)
        response = send_generation_request(host, params)

        # Decode response
        output_image = response.content
        finish_reason = response.headers.get("finish-reason")
        resp_seed = response.headers.get("seed")

        if finish_reason == "CONTENT_FILTERED":
            raise Warning("Generation failed NSFW classifier")

        # Save per-asset file
        suffix = f"_{resp_seed}" if resp_seed else ""
        filename = f"{asset_name}{suffix}.{output_format}"
        out_path = Path.cwd() / filename
        with open(out_path, "wb") as f:
            f.write(output_image)

        print(f"Saved image: {out_path}")
        if finish_reason:
            print(f"finish-reason: {finish_reason}")
        if resp_seed:
            print(f"seed: {resp_seed}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
