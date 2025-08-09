#!/usr/bin/env python3
import os
import json
import sys
import time
import urllib.request
from dotenv import load_dotenv
#load openrouter key from .env
load_dotenv()
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")

PROMPT = (
    "Please build a mario 2d platformer. generate mario, goomba, coins, and the flag at the end of the level.  "
    "Make sprites and spritesheets fro each. add proper interactins between objects according to standard playstyle "
    "of mario 2D  16-bit pixel platformer. Make 16-bit skya dn ground backgrounds, green grass, etc."
)

MODEL = "openai/gpt-5-chat"
API_URL = "https://openrouter.ai/api/v1/chat/completions"

def call_openrouter(prompt: str) -> dict:
    if not OPENROUTER_API_KEY:
        print("Missing OPENROUTER_API_KEY in environment", file=sys.stderr)
        sys.exit(1)
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
    }
    data = {
        "model": MODEL,
        "messages": [
            {"role": "user", "content": prompt}
        ],
        # Encourage models that support it to surface chain-of-thought markers
        "extra_body": {
            "reasoning": {"effort": "high"}
        },
        "temperature": 0.7,
        "max_tokens": 2048,
    }
    req = urllib.request.Request(API_URL, data=json.dumps(data).encode("utf-8"), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8")
    return json.loads(body)


def extract_think_blocks(text: str):
    out = []
    tags = [("<think>", "</think>"), ("<thinking>", "</thinking>"), ("<reasoning>", "</reasoning>")]
    for start, end in tags:
        idx = 0
        while True:
            s = text.find(start, idx)
            if s == -1:
                break
            e = text.find(end, s + len(start))
            if e == -1:
                out.append(text[s+len(start):])
                break
            else:
                out.append(text[s+len(start):e])
                idx = e + len(end)
    return out


def main():
    print("Calling OpenRouter with model:", MODEL)
    res = call_openrouter(PROMPT)
    print("Raw JSON keys:", list(res.keys()))
    choices = res.get("choices", [])
    if choices:
        content = choices[0].get("message", {}).get("content", "")
        print("\n--- Assistant Content (raw) ---\n")
        print(content)
        thinks = extract_think_blocks(content)
        if thinks:
            print("\n--- Extracted <think> blocks (raw) ---\n")
            for i, block in enumerate(thinks, 1):
                print(f"[Block {i}]\n{block}\n")
        else:
            print("\n(No <think> blocks found in content)\n")
    else:
        print("No choices in response. Full JSON:\n", json.dumps(res, indent=2))


if __name__ == "__main__":
    main() 