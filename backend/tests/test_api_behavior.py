"""Behavior tests for endpoints not covered by byte-parity goldens
(empty-database states, sync trigger guards)."""

from fastapi.testclient import TestClient

import api_server


def _client():
    return TestClient(api_server.app)


class TestEmptyDatabase:
    def test_summary_empty(self, temp_db):
        with _client() as client:
            res = client.get("/api/summary")
        assert res.status_code == 200
        assert res.json() == {"error": "No data available"}

    def test_health_data_empty(self, temp_db):
        with _client() as client:
            res = client.get("/api/health-data")
        assert res.status_code == 200
        assert res.json() == []

    def test_sync_status_empty(self, temp_db):
        with _client() as client:
            res = client.get("/api/sync/status")
        assert res.status_code == 200
        body = res.json()
        assert body["status"] == "no_data"
        assert "sync_available" in body
        assert body["sync_running"] is False

    def test_sync_status_unavailable(self, temp_db, monkeypatch):
        monkeypatch.setattr(api_server, "SYNC_AVAILABLE", False)
        with _client() as client:
            res = client.get("/api/sync/status")
        assert res.status_code == 200
        body = res.json()
        assert body["status"] == "unavailable"
        assert body["sync_available"] is False


class TestSyncGuards:
    def test_sync_unavailable(self, temp_db, monkeypatch):
        monkeypatch.setattr(api_server, "SYNC_AVAILABLE", False)
        with _client() as client:
            for path in ("/api/sync/latest", "/api/sync/full", "/api/sync/range"):
                res = client.post(path, json={"start": "2026-01-01"})
                assert res.status_code == 500
                assert "garminconnect" in res.json()["error"]

    def test_sync_range_requires_start(self, temp_db, monkeypatch):
        monkeypatch.setattr(api_server, "SYNC_AVAILABLE", True)
        with _client() as client:
            res = client.post("/api/sync/range", json={})
        assert res.status_code == 400
        assert "start" in res.json()["error"]

    def test_sync_conflict_when_running(self, temp_db, monkeypatch):
        monkeypatch.setattr(api_server, "SYNC_AVAILABLE", True)
        monkeypatch.setitem(api_server._sync_state, "running", True)
        with _client() as client:
            res = client.post("/api/sync/latest", json={})
        assert res.status_code == 409
        assert res.json() == {"error": "Sync already running"}

    def test_unknown_post_404(self, temp_db):
        with _client() as client:
            res = client.post("/api/nope")
        assert res.status_code == 404
        assert res.json() == {"error": "Not found"}

    def test_wrong_method_uses_404_contract(self, temp_db):
        # GET on a POST-only route falls through to the legacy 404 endpoints
        # list, not FastAPI's default 405 {"detail": ...}.
        with _client() as client:
            res = client.get("/api/sync/latest")
        assert res.status_code == 404
        body = res.json()
        assert "endpoints" in body
        assert "error" in body


class TestErrorContract:
    def test_unhandled_exception_returns_json_error(self, populated_db, monkeypatch):
        # An analytics failure must surface as the legacy {"error": ...} JSON
        # (500), not Starlette's text/plain body that breaks client json.decode.
        def boom():
            raise ValueError("analytics blew up")

        monkeypatch.setattr(api_server, "load_data", boom)
        client = TestClient(api_server.app, raise_server_exceptions=False)
        with client:
            res = client.get("/api/analytics/correlations")
        assert res.status_code == 500
        assert res.headers["content-type"].startswith("application/json")
        assert res.json() == {"error": "analytics blew up"}


class TestTrailingSlash:
    def test_health_data_trailing_slash_redirects(self, populated_db):
        with _client() as client:
            res = client.get("/api/health-data/", follow_redirects=True)
        assert res.status_code == 200
        assert len(res.json()) == 90
