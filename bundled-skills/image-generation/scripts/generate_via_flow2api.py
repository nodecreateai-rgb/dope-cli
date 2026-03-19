#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib import error, request

DEFAULT_CONFIG_PATH = os.environ.get("OPENCLAW_CONFIG_PATH", str(Path.home() / ".openclaw" / "openclaw.json"))
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


def load_openclaw_provider_defaults(config_path: str = DEFAULT_CONFIG_PATH) -> dict:
    path = Path(config_path)
    if not path.exists():
        return {}
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    models = cfg.get("models") or {}
    providers = models.get("providers") or {}
    provider_name = (models.get("default") or models.get("provider") or "default")
    provider_cfg = providers.get(provider_name) or providers.get("default") or {}
    model_name = ""
    model_list = provider_cfg.get("models") or []
    if model_list and isinstance(model_list[0], dict):
        model_name = str(model_list[0].get("id") or "").strip()
    return {
        "base_url": str(provider_cfg.get("baseUrl") or "").strip(),
        "api_key": str(provider_cfg.get("apiKey") or "").strip(),
        "model": model_name,
    }


def resolve_runtime_defaults() -> dict:
    cfg = load_openclaw_provider_defaults()
    base_url = (
        os.environ.get("IMAGE_GENERATION_BASE_URL")
        or os.environ.get("FLOW2API_BASE_URL")
        or cfg.get("base_url")
        or DEFAULT_BASE_URL
    )
    api_key = (
        os.environ.get("IMAGE_GENERATION_API_KEY")
        or os.environ.get("FLOW2API_API_KEY")
        or cfg.get("api_key")
        or ""
    )
    model = (
        os.environ.get("IMAGE_GENERATION_MODEL")
        or os.environ.get("FLOW2API_MODEL")
        or cfg.get("model")
        or ""
    )
    return {
        "base_url": normalize_base_url(base_url),
        "api_key": api_key,
        "model": model,
    }


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


def pick_model(requested_model: str, ratio: str, default_model: str) -> tuple[str, str | None]:
    model = (requested_model or "").strip()
    if model:
        return model, None
    configured_default = (default_model or "").strip()
    if configured_default:
        return configured_default, None
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
    runtime_defaults = resolve_runtime_defaults()
    parser = argparse.ArgumentParser(description="Generate images through Flow2API/OpenAI-compatible image endpoint")
    parser.add_argument("--base-url", default=runtime_defaults["base_url"])
    parser.add_argument("--api-key", default=runtime_defaults["api_key"])
    parser.add_argument("--model", default="")
    parser.add_argument("--ratio", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--prompt-file", default="")
    parser.add_argument("--style", default="")
    parser.add_argument("--out", default="")
    parser.add_argument("--list-models", action="store_true")
    args = parser.parse_args()

    if not args.api_key:
        raise SystemExit("api key is required; pass --api-key or configure OpenClaw provider/api env vars")

    if args.list_models:
        print(json.dumps(list_models(args.base_url, args.api_key), ensure_ascii=False, indent=2))
        return

    prompt = read_prompt(args)
    ratio = normalize_ratio(args.ratio)
    model, fallback_note = pick_model(args.model, ratio, runtime_defaults["model"])
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
        "baseUrlSource": args.base_url,
    }
    if args.out:
        save_text(args.out, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not image_url:
        raise SystemExit("no image URL found in model response")


if __name__ == "__main__":
    main()
