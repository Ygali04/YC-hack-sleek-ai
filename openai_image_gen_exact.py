import sys
import base64
import os
from dotenv import load_dotenv

# Ensure the modern OpenAI SDK is available
try:
    from openai import OpenAI  # requires openai>=1.x
except Exception:
    print(
        "OpenAI SDK not available. Install/upgrade with: pip3 install --upgrade openai",
        file=sys.stderr,
    )
    sys.exit(1)

# Load API key from environment
load_dotenv()
api_key = os.environ.get("OPENAI_API_KEY")
org_id = os.environ.get("OPENAI_ORG_ID") or os.environ.get("OPENAI_ORGANIZATION")
if not api_key:
    print(
        "Missing OPENAI_API_KEY. Set it in your environment or .env.",
        file=sys.stderr,
    )
    sys.exit(1)

client = OpenAI(api_key=api_key, organization=org_id) if org_id else OpenAI(api_key=api_key)

result = client.images.generate(
    model="gpt-image-1",
    prompt="Draw a 2D pixel art style sprite sheet of a tabby gray cat",
    size="1024x1024",
    background="transparent",
    quality="high",
)

# Access model fields directly (no deprecated .json())
image_base64 = result.data[0].b64_json
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("sprite.png", "wb") as f:
    f.write(image_bytes)