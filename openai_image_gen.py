import os
import sys
import base64
from pathlib import Path
from typing import Dict

from dotenv import load_dotenv

from openai import OpenAI


def load_openai_key() -> str:
    load_dotenv()
    api_key = os.getenv("OPENAI_KEY", "").strip()
    if not api_key:
        raise RuntimeError(
            "Missing OPENAI_KEY. Set it in your environment or in a .env file."
        )
    return api_key


def generate_openai_image(prompt: str) -> bytes:
    if OpenAI is None:
        raise RuntimeError(
            "The openai package is not installed. Run: pip3 install -r requirements.txt"
        )
    client = OpenAI(api_key=load_openai_key())
    result = client.images.generate(
        model="gpt-image-1",
        prompt=prompt,
    )
    image_base64 = result.data[0].b64_json
    return base64.b64decode(image_base64)


def main() -> int:
    # Style and constraints aligned with our SD prompts
    base_style = (
        "16-bit 2D pixel art sprite, SNES/Genesis-era aesthetic, limited 16-color palette, "
        "strong black outline, clean dithering, sharp pixels, no anti-aliasing, flat shading, "
        "high-contrast readable shapes."
    )
    enforce_theme = (
        "Do NOT make 3D, photorealistic, painterly, vector, or smooth gradients. "
        "No text, watermark, UI, borders, or frames."
    )

    # Asset-specific prompts (sprite sheets and tileset)
    assets: Dict[str, str] = {
        "pixel_knight": (
            "Generate a sprite sheet for a knight character in pixel art style: short, stout, very small chibi proportions, "
            "wearing simple steel armor with a small red plume, side view facing right. Include 4 frames of a walking animation "
            "and 3 frames of an idle pose; also include frames of taking damage and a death animation. Each frame is 32x32 pixels, "
            "clean black outlines and a transparent background, organized in a neat grid with equal spacing; consistent 16-bit palette."
        ),
        "pixel_slime": (
            "Generate a sprite sheet for a green, slightly menacing slime enemy in pixel art style, side view facing right. "
            "Include 4 frames of a sliding/walking animation and 3 frames of an idle wobble; also include damage and death frames. "
            "Each frame is 32x32 pixels with clean black outline and a transparent background, organized in a neat grid; consistent 16-bit palette."
        ),
        "pixel_tileset": (
            "Create a square 1:1 image containing a compact tileset: a grid of small 2D 16-bit pixel blocks (square tiles seen straight-on, not isometric), "
            "designed for a 2D platformer. Include multiple terrains: grass with dirt, stone/brick, sand, snow/ice, wood, and metal. "
            "Each tile is seamless and perfectly square with high-contrast readable edges, consistent limited palette, and clearly separated in a regular grid on a plain or transparent background."
        ),
        "pixel_platforms": (
            "Set of platform sprites for a 2D platformer: small tileable platform segments with metal and stone variants, "
            "clearly separated pieces on a plain or transparent background, readable edges for movement, 16-bit palette."
        ),
        "pixel_coin": (
            "Generate a tiny coin sprite sheet in pixel art style. Include 4 frames of a spin/rotation animation and 2 frames of an idle state. "
            "Each frame is 32x32 pixels with a transparent background, bright gold coin with black outline; organized in a neat grid; consistent 16-bit palette."
        ),
    }

    for asset_name, asset_desc in assets.items():
        prompt = f"{base_style} {enforce_theme} {asset_desc}"
        print(f"Generating (OpenAI) {asset_name}...")
        image_bytes = generate_openai_image(prompt)

        out_path = Path.cwd() / f"openai_{asset_name}.png"
        with open(out_path, "wb") as f:
            f.write(image_bytes)
        print(f"Saved image: {out_path}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1) 