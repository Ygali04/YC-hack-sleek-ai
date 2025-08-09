import sys
import base64
import os
from dotenv import load_dotenv

# Ensure the modern OpenAI SDK is available
try:
    from openai import OpenAI  # requires openai>=1.x
except Exception as import_err:
    try:
        import openai  # type: ignore
        version = getattr(openai, "__version__", "unknown")
    except Exception:
        version = "not installed"
    print(
        f"Your Python is importing 'openai' version {version} which does not provide the OpenAI client.\n"
        f"Fix by running: pip3 install --upgrade openai\n"
        f"Or run this script with the interpreter where openai>=1.x is installed (e.g., 'python3').",
        file=sys.stderr,
    )
    sys.exit(1)

# Load API key from environment
load_dotenv()
api_key = (
    os.environ.get("OPENAI_API_KEY")
    or os.environ.get("OPENAI_KEY")
    or os.environ.get("OPENROUTER_API_KEY")
)
if not api_key:
    print(
        "Missing OPENAI_API_KEY (or OPENAI_KEY). Set it in your environment or in a .env file.",
        file=sys.stderr,
    )
    sys.exit(1)

client = OpenAI(api_key=api_key)

result = client.images.generate(
    model="gpt-image-1",
    prompt="Draw a 2D pixel art style sprite sheet of a tabby gray cat",
    size="1024x1024",
    background="transparent",
    quality="high",
)

image_base64 = result.json()["data"][0]["b64_json"]
image_bytes = base64.b64decode(image_base64)

# Save the image to a file
with open("sprite.png", "wb") as f:
    f.write(image_bytes) 