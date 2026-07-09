"""Tests for the LLM coach client and endpoint.

No real model is contacted: the OpenAI-compatible endpoint is faked with an
httpx.MockTransport, and the API-level tests stub coach.stream_answer.
"""

import httpx
from fastapi.testclient import TestClient

import api_server
import coach
import db


def _sse(*chunks: str) -> bytes:
    lines = [
        'data: {"choices":[{"delta":{"content":%s}}]}' % _json_str(c) for c in chunks
    ]
    lines.append("data: [DONE]")
    return ("\n\n".join(lines) + "\n\n").encode()


def _json_str(s: str) -> str:
    import json
    return json.dumps(s)


class TestBuildContext:
    def test_contains_real_numbers_and_omits_missing(self, temp_db):
        db.upsert_days([
            {"date": "2026-07-07", "sleep_score": 81, "hrv": 63.5, "steps": 9231},
            # hrv missing (stored NULL) -> must not appear as 0 for this day
            {"date": "2026-07-06", "sleep_score": 74, "hrv": 0, "steps": 4200},
        ])
        ctx = coach.build_context()
        assert "81" in ctx and "63.5" in ctx and "9231" in ctx
        assert "2026-07-06" in ctx
        # The missing (0 -> NULL) HRV must not be rendered as "HRV (ms) 0"
        assert "HRV (ms) 0" not in ctx

    def test_no_data(self, temp_db):
        assert "No wellness data" in coach.build_context()


class TestStreamChatParsing:
    async def test_parses_openai_sse_deltas(self, temp_db):
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, content=_sse("Read", "iness ", "is high."))

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        out = [tok async for tok in coach.stream_chat(
            [{"role": "user", "content": "hi"}], client=client,
        )]
        assert "".join(out) == "Readiness is high."

    async def test_connection_failure_raises_not_configured(self, temp_db):
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("refused")

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        gen = coach.stream_chat([{"role": "user", "content": "hi"}], client=client)
        try:
            await anext(gen)
            assert False, "expected LLMNotConfigured"
        except coach.LLMNotConfigured:
            pass


class TestCoachEndpoint:
    def test_streams_grounded_reply(self, populated_db, monkeypatch):
        async def fake_answer(question, **kwargs):
            for tok in ["You slept ", "well."]:
                yield tok

        monkeypatch.setattr(coach, "stream_answer", fake_answer)
        with TestClient(api_server.app) as client:
            res = client.post("/api/coach/chat", json={"question": "how am I?"})
        assert res.status_code == 200
        assert res.headers["content-type"].startswith("text/plain")
        assert res.text == "You slept well."

    def test_requires_question(self, temp_db):
        with TestClient(api_server.app) as client:
            res = client.post("/api/coach/chat", json={})
        assert res.status_code == 400
        assert "question" in res.json()["error"]

    def test_llm_unavailable_returns_503(self, populated_db, monkeypatch):
        async def fake_answer(question, **kwargs):
            raise coach.LLMNotConfigured("host down")
            yield  # pragma: no cover - makes this an async generator

        monkeypatch.setattr(coach, "stream_answer", fake_answer)
        with TestClient(api_server.app) as client:
            res = client.post("/api/coach/chat", json={"question": "hi"})
        assert res.status_code == 503
        assert "host down" in res.json()["error"]

    def test_coach_chat_in_endpoint_list(self, temp_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/does-not-exist")
        assert "POST /api/coach/chat" in res.json()["endpoints"]
