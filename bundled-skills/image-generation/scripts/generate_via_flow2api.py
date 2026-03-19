#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib import error, request

DEFAULT_BASE_URL = "http://127.0.0.1:38080"
DEFAULT_MODEL = "gemini-3.1-flash-image-square"
RATIO_MODEL_MAP = {
    "1:1": "square",
    "16:9": "landscape",
    "9:16": "portrait",
    "4:3": "four-three",
    "3:4": "three-four",
    "4:5": "three-four",
}


def normalize_base_url(raw: str) -> str:
    text = (raw or "").strip().rstrip("/")
    return text or DEFAULT_BASE_URL


def read_prompt(args: argparse.Namespace) -> str:
    if args.prompt:
        return args.prompt.strip()
    if args.prompt_file:
        return Path(args.prompt_file).read_text(encoding="utf-8").strip()
    data = sys.stdin.read().strip()
    if data:
        return data
    raise SystemExit("prompt is required")


def normalize_ratio(raw: str) -> str:
    text = (raw or "").strip().lower().replace("：", ":")
    aliases = {
        "square": "1:1",
        "landscape": "16:9",
        "portrait": "9:16",
        "four-three": "4:3",
        "three-four": "3:4",
        "four-five": "4:5",
    }
    return aliases.get(text, text)


def pick_model(requested_model: str, ratio: str) -> tuple[str, str | None]:
    model = (requested_model or "").strip()
    if model:
        return model, None
    suffix = RATIO_MODEL_MAP.get(ratio or "", "square")
    chosen = f"gemini-3.1-flash-image-{suffix}"
    note = None
    if ratio == "4:5":
        note = "backend has no native 4:5 model; fell back to three-four and compensated in prompt"
    return chosen, note


def enhance_prompt(prompt: str, ratio: str, style: str) -> str:
    extras: list[str] = []
    if style:
        extras.append(style.strip())
    if ratio == "4:5":
        extras.append("偏竖版构图，尽量贴近4:5社交媒体封面观感")
    if extras:
        return prompt.strip() + "\n\n补充要求：" + "；".join(x for x in extras if x)
    return prompt.strip()


def api_post(base_url: str, api_key: str, path: str, payload: dict) -> dict:
    url = normalize_base_url(base_url) + path
    req = request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with request.urlopen(req, timeout=420) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return json.loads(body)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {detail}")


def list_models(base_url: str, api_key: str) -> dict:
    url = normalize_base_url(base_url) + "/v1/models"
    req = request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
    try:
        with request.urlopen(req, timeout=60) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return json.loads(body)
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {detail}")


def extract_image_url(content: str) -> str | None:
    patterns = [
        r"!\[Generated Image\]\((https?://[^)]+)\)",
        r"(https://storage\.googleapis\.com/[^\s)]+)",
        r"(https?://[^\s]+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            return match.group(1)
    return None


def save_text(path: str | None, text: str) -> None:
    if not path:
        return
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate images through Flow2API/OpenAI-compatible image endpoint")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", default="")
    parser.add_argument("--ratio", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--prompt-file", default="")
    parser.add_argument("--style", default="")
    parser.add_argument("--out", default="")
    parser.add_argument("--list-models", action="store_true")
    args = parser.parse_args()

    if args.list_models:
        print(json.dumps(list_models(args.base_url, args.api_key), ensure_ascii=False, indent=2))
        return

    prompt = read_prompt(args)
    ratio = normalize_ratio(args.ratio)
    model, fallback_note = pick_model(args.model, ratio)
    final_prompt = enhance_prompt(prompt, ratio, args.style)

    payload = {
        "model": model or DEFAULT_MODEL,
        "stream": False,
        "messages": [{"role": "user", "content": final_prompt}],
    }
    data = api_post(args.base_url, args.api_key, "/v1/chat/completions", payload)
    choice = (((data.get("choices") or [{}])[0]).get("message") or {})
    content = str(choice.get("content") or "")
    image_url = extract_image_url(content)
    result = {
        "ok": bool(image_url),
        "model": payload["model"],
        "ratio": ratio,
        "fallbackNote": fallback_note,
        "imageUrl": image_url,
        "rawContent": content,
    }
    if args.out:
        save_text(args.out, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not image_url:
        raise SystemExit("no image URL found in model response")


if __name__ == "__main__":
    main()
