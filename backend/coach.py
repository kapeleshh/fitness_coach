"""LLM coach — provider-agnostic streaming client + grounded context.

The coach's job is narrow: take numbers the deterministic layers already
computed and present them as natural-language briefings / answer questions
about them. It NEVER invents figures — every number in a reply comes from the
context this module assembles server-side.

Transport is an OpenAI-compatible /v1/chat/completions endpoint, so the model
host is swappable by config (Ollama on a Mac, mlx-lm, LM Studio, llama.cpp):
set LLM_BASE_URL / LLM_MODEL / LLM_API_KEY. Nothing here is host-specific.

Grounding is assembled in build_context(): today's readiness verdict, the
recent wellness summary, and training load (fitness/fatigue/form and recent
sessions) — all deterministic numbers the model only rephrases.

Strava data never reaches the model. Strava's API Policy (effective
2026-06-01) bars using Strava Data — including anything derived from it — in
the operation or grounding of an AI application, so the coach's training
load is computed from Garmin-recorded activities alone (AI_EXCLUDED_SOURCES).
The deterministic /api/training-load endpoints still use every source.
"""

import json
import os
from collections.abc import AsyncIterator

import httpx

import db

DEFAULT_BASE_URL = "http://localhost:11434/v1"
DEFAULT_MODEL = "llama3.1:8b"
_TIMEOUT = httpx.Timeout(60.0, connect=5.0)

# Activity sources whose rows, and anything derived from them, must stay out
# of the model's context (see the module docstring).
AI_EXCLUDED_SOURCES = ("strava",)

_METHOD_LABEL = {
    "garmin_load": "Garmin training load",
    "trimp": "heart-rate TRIMP",
    "relative_effort": "relative effort",
    "duration_estimate": "estimated from duration",
    "none": "no load data",
}

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
    """Assemble the grounding block from the most recent wellness records
    and training load.

    Uses NULL-aware records (missing metrics are omitted, not shown as 0) so
    the model never sees a fabricated zero.
    """
    records = db.get_all_days()[:days]
    if not records:
        return "\n".join(["No wellness data has been synced yet.", *_training_load_lines(None)])

    # Today's readiness verdict (deterministic) leads the context so the model
    # grounds on the computed score/band and never recomputes it.
    lines: list[str] = []
    readiness = None
    try:
        import readiness_engine
        r = readiness_engine.readiness_today()
        if r.get("score") is not None:
            readiness = r
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
    lines.extend(_training_load_lines(readiness))
    return "\n".join(lines)


def _training_load_lines(readiness: dict | None) -> list[str]:
    """Training-load section, Garmin-recorded activities only. Activity names
    are omitted: they are free text the athlete (or anyone) can edit."""
    lines = [(
        "Training load (computed from Garmin-recorded activities only; "
        "activities recorded only on Strava are not visible to you):"
    )]
    try:
        import training_load_engine as tle
        data = tle.compute(exclude_sources=AI_EXCLUDED_SOURCES)
    except Exception:  # noqa: BLE001 — best-effort context, like readiness above
        return [*lines, "- unavailable"]
    if not data["series"]:
        return [*lines, "- no Garmin-recorded activities yet"]

    state = None
    if readiness is not None:
        state = tle.state_on(readiness["date"], data)
    if state is None:
        state = tle.describe(data["series"][-1], data["sessions"])
    note = (tle.readiness_note(readiness["band"], state)
            if readiness is not None and state["date"] == readiness["date"]
            else state["summary"])
    lines.append(f"- as of {state['date']}: {note} Confidence: {state['confidence']}.")
    week = state["last_7_days"]
    lines.append(
        f"- last 7 days: {week['sessions']} sessions, {week['minutes']} min, "
        f"total load {week['load']:.0f}"
    )
    for s in state["recent_sessions"]:
        minutes = f"{s['minutes']:.0f} min" if s["minutes"] else "duration unknown"
        lines.append(
            f"- {s['local_date']}: {s['sport_family']}, {minutes}, load {s['load']:.0f} "
            f"({_METHOD_LABEL.get(s['method'], s['method'])})"
        )
    return lines


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
