"""LLM coach — provider-agnostic streaming client + grounded context.

The coach's job is narrow: take numbers the deterministic layers already
computed and present them as natural-language briefings / answer questions
about them. It NEVER invents figures — every number in a reply comes from the
context this module assembles server-side.

Transport is an OpenAI-compatible /v1/chat/completions endpoint, so the model
host is swappable by config (Ollama on a Mac, mlx-lm, LM Studio, llama.cpp):
set LLM_BASE_URL / LLM_MODEL / LLM_API_KEY. Nothing here is host-specific.

Grounding today is the recent wellness summary that already lives in SQLite.
When the readiness and training-load engines land, add their numbers to
build_context() — the transport, endpoint, and client stay unchanged.
"""

import json
import os
from collections.abc import AsyncIterator

import httpx

import db

DEFAULT_BASE_URL = "http://localhost:11434/v1"
DEFAULT_MODEL = "llama3.1:8b"
_TIMEOUT = httpx.Timeout(60.0, connect=5.0)

SYSTEM_PROMPT = (
    "You are a personal fitness coach. You are given the athlete's recent "
    "health metrics as structured data. Base every statement on those numbers "
    "— never invent or estimate values that are not provided. If the data is "
    "insufficient to answer, say so plainly. Keep replies concise and practical."
)


class LLMNotConfigured(RuntimeError):
    """Raised when no model host is reachable/configured."""


def llm_config() -> dict:
    """Resolve LLM connection settings. Env wins; DB user_settings overrides
    are allowed so the host can be changed without editing .env."""
    settings = db.get_all_settings()
    return {
        "base_url": os.getenv("LLM_BASE_URL")
        or settings.get("llm_base_url")
        or DEFAULT_BASE_URL,
        "model": os.getenv("LLM_MODEL") or settings.get("llm_model") or DEFAULT_MODEL,
        "api_key": os.getenv("LLM_API_KEY") or settings.get("llm_api_key") or "ollama",
    }


def build_context(days: int = 7) -> str:
    """Assemble the grounding block from the most recent wellness records.

    Uses NULL-aware records (missing metrics are omitted, not shown as 0) so
    the model never sees a fabricated zero. Readiness score and CTL/ATL/TSB
    will be appended here once those engines exist.
    """
    records = db.get_all_days()[:days]
    if not records:
        return "No wellness data has been synced yet."

    # Today's readiness verdict (deterministic) leads the context so the model
    # grounds on the computed score/band and never recomputes it.
    lines: list[str] = []
    try:
        import readiness_engine
        r = readiness_engine.readiness_today()
        if r.get("score") is not None:
            lines.append(
                f"Today's readiness: {r['score']}/100 ({r['band']}, "
                f"{r['confidence']} confidence). {r['briefing']}"
            )
    except Exception:
        pass  # readiness is best-effort context; never block the coach on it

    metrics = [
        ("sleep_score", "sleep score"),
        ("hrv", "HRV (ms)"),
        ("resting_hr", "resting HR (bpm)"),
        ("body_battery_start", "body battery (morning)"),
        ("avg_stress", "avg stress"),
        ("steps", "steps"),
    ]
    lines.append(f"Recent {len(records)} days of wellness data (newest first):")
    for r in records:
        parts = [
            f"{label} {r[key]}" for key, label in metrics if r.get(key) is not None
        ]
        lines.append(f"- {r['date']}: " + (", ".join(parts) if parts else "no data"))
    return "\n".join(lines)


async def stream_chat(
    messages: list[dict],
    *,
    client: httpx.AsyncClient | None = None,
) -> AsyncIterator[str]:
    """Stream assistant text deltas from an OpenAI-compatible chat endpoint.

    `client` is injectable for tests (httpx.MockTransport). Raises
    LLMNotConfigured on connection failure so callers can surface a clean error.
    """
    cfg = llm_config()
    payload = {"model": cfg["model"], "messages": messages, "stream": True}
    headers = {"Authorization": f"Bearer {cfg['api_key']}"}
    url = cfg["base_url"].rstrip("/") + "/chat/completions"

    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=_TIMEOUT)
    try:
        async with client.stream("POST", url, json=payload, headers=headers) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.startswith("data:"):
                    continue
                data = line[len("data:"):].strip()
                if data == "[DONE]":
                    break
                try:
                    delta = json.loads(data)["choices"][0]["delta"].get("content")
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
                if delta:
                    yield delta
    except httpx.HTTPError as e:
        raise LLMNotConfigured(
            f"Could not reach the LLM at {cfg['base_url']}: {e}"
        ) from e
    finally:
        if owns_client:
            await client.aclose()


async def stream_answer(
    question: str,
    *,
    client: httpx.AsyncClient | None = None,
) -> AsyncIterator[str]:
    """Grounded coach answer: server-assembled context + the user's question.

    The client only supplies the question — the grounding context is built here
    so it is the single source of truth across web and future phone clients.
    """
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": build_context()},
        {"role": "user", "content": question},
    ]
    async for delta in stream_chat(messages, client=client):
        yield delta
