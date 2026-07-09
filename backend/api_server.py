"""FastAPI server for parsed Garmin health data.

Same endpoint contract as the original stdlib http.server implementation
(verified by golden contract tests in tests/test_contract.py), now backed
by SQLite (db.py) instead of parsed_health_data.json.

Also runs a background scheduler that keeps Garmin wellness data fresh
when credentials are configured.
"""

import os
import threading
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

import coach
import db
import readiness_engine
from analytics_engine import (
    analyze_trends,
    analyze_weekly_patterns,
    calculate_correlation_matrix,
    calculate_lagged_correlations,
    calculate_personal_baselines,
    detect_anomalies,
    load_data,
    run_full_analysis,
)

# Import sync module (optional — only available if garminconnect is installed)
try:
    from garmin_sync import (
        get_garmin_client,
        sync_date_range,
        sync_full,
        sync_latest,
    )
    SYNC_AVAILABLE = True
except ImportError:
    SYNC_AVAILABLE = False

LEGACY_JSON = Path(__file__).parent / "parsed_health_data.json"

ENDPOINT_LIST = [
    "GET  /api/health-data",
    "GET  /api/health-data/YYYY-MM-DD",
    "GET  /api/summary",
    "GET  /api/analytics",
    "GET  /api/analytics/correlations",
    "GET  /api/analytics/lagged",
    "GET  /api/analytics/anomalies",
    "GET  /api/analytics/weekly",
    "GET  /api/analytics/baselines",
    "GET  /api/analytics/trends",
    "GET  /api/readiness",
    "GET  /api/readiness/history",
    "GET  /api/readiness/YYYY-MM-DD",
    "GET  /api/sync/status",
    "POST /api/sync/latest",
    "POST /api/sync/full",
    "POST /api/sync/range",
    "POST /api/coach/chat",
]

# ---- Background sync state (thread-safe) ----
_sync_lock = threading.Lock()
_sync_state = {
    "running": False,
    "last_result": None,
    "last_error": None,
    "last_run_at": None,
}


def _start_sync(job) -> bool:
    """Atomically claim the sync slot and run `job` in a daemon thread.
    Returns False if a sync is already running."""
    with _sync_lock:
        if _sync_state["running"]:
            return False
        _sync_state["running"] = True
        _sync_state["last_error"] = None

    def run():
        try:
            _sync_state["last_result"] = job()
        except (Exception, SystemExit) as e:
            # get_garmin_client() calls sys.exit(1) on missing/expired
            # credentials; SystemExit is a BaseException, so it would slip
            # past a bare `except Exception` and the sync would fail silently
            # with last_error left None while status implied success.
            _sync_state["last_error"] = str(e) or f"sync exited: {e!r}"
        finally:
            _sync_state["last_run_at"] = datetime.now().isoformat(timespec="seconds")
            with _sync_lock:
                _sync_state["running"] = False

    threading.Thread(target=run, daemon=True).start()
    return True


def _scheduled_sync():
    """Periodic freshness sync — skipped silently if one is already running."""
    _start_sync(lambda: sync_latest(get_garmin_client(), days=3))


def _credentials_configured() -> bool:
    from garmin_sync import TOKEN_STORE
    if os.getenv("GARMIN_EMAIL") and os.getenv("GARMIN_PASSWORD"):
        return True
    return TOKEN_STORE.exists() and any(TOKEN_STORE.glob("*.json"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()

    # One-time migration: adopt a legacy JSON file if the DB is empty.
    # Disabled under tests (FITNESS_COACH_IMPORT_LEGACY=0) so an empty temp
    # database never ingests the developer's real parsed_health_data.json.
    if (
        os.getenv("FITNESS_COACH_IMPORT_LEGACY", "1") != "0"
        and db.count_days() == 0
        and LEGACY_JSON.exists()
    ):
        imported = db.import_json(LEGACY_JSON)
        print(f"📦 Imported {imported} days from {LEGACY_JSON.name} into SQLite")

    scheduler = None
    if SYNC_AVAILABLE and _credentials_configured() and os.getenv(
        "GARMIN_AUTO_SYNC", "1"
    ) != "0":
        from apscheduler.schedulers.background import BackgroundScheduler
        interval_hours = float(os.getenv("GARMIN_SYNC_INTERVAL_HOURS", "6"))
        scheduler = BackgroundScheduler()
        scheduler.add_job(_scheduled_sync, "interval", hours=interval_hours)
        scheduler.start()
        print(f"⏰ Auto-sync every {interval_hours}h enabled")

    yield

    if scheduler:
        scheduler.shutdown(wait=False)


app = FastAPI(title="Fitness Coach API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tightened in Phase 7 when the app is served by FastAPI
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)


def _not_found_response(request: Request) -> JSONResponse:
    # Legacy contract: GET on an unrouted path lists all endpoints; anything
    # else gets a bare {"error": "Not found"}.
    if request.method == "GET":
        return JSONResponse(
            status_code=404,
            content={"error": "Not found", "endpoints": ENDPOINT_LIST},
        )
    return JSONResponse(status_code=404, content={"error": "Not found"})


@app.exception_handler(404)
async def not_found_handler(request: Request, exc):
    return _not_found_response(request)


@app.exception_handler(405)
async def method_not_allowed_handler(request: Request, exc):
    # The old stdlib server had no routing table, so a wrong-method request
    # (e.g. GET /api/sync/latest) fell through to its 404 contract rather than
    # a 405. Preserve that: no consumer should have to handle a new 405 shape.
    return _not_found_response(request)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc):
    # Preserve the legacy JSON error contract ({"error": str(e)} with 500)
    # instead of Starlette's default text/plain "Internal Server Error", which
    # would make the Flutter client's json.decode throw.
    return JSONResponse(status_code=500, content={"error": str(exc)})


def _error(message: str, status: int = 500) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": message})


# ========== HEALTH DATA ENDPOINTS ==========

@app.get("/api/health-data")
def health_data():
    return db.get_all_days(legacy_zero_fill=True)


@app.get("/api/health-data/{date_str}")
def health_data_single(date_str: str):
    day = db.get_day(date_str, legacy_zero_fill=True)
    if day is None:
        return _error(f"No data for {date_str}", status=404)
    return day


@app.get("/api/summary")
def summary():
    data = db.get_all_days(legacy_zero_fill=True)

    def _safe_avg(items, key):
        vals = [d[key] for d in items if (d.get(key) or 0) > 0]
        return sum(vals) / len(vals) if vals else 0

    if not data:
        return {"error": "No data available"}

    return {
        "total_days": len(data),
        "date_range": {"start": data[-1]["date"], "end": data[0]["date"]},
        "averages": {
            "sleep_score": round(_safe_avg(data, "sleep_score"), 1),
            "hrv": round(_safe_avg(data, "hrv"), 1),
            "stress": round(_safe_avg(data, "avg_stress"), 1),
            "steps": round(_safe_avg(data, "steps"), 0),
        },
        "recent_day": data[0],
    }


# ========== ANALYTICS ENDPOINTS ==========

@app.get("/api/analytics")
def analytics_full():
    return run_full_analysis()


@app.get("/api/analytics/correlations")
def analytics_correlations():
    return calculate_correlation_matrix(load_data())


@app.get("/api/analytics/lagged")
def analytics_lagged():
    return calculate_lagged_correlations(load_data())


@app.get("/api/analytics/anomalies")
def analytics_anomalies():
    return detect_anomalies(load_data())


@app.get("/api/analytics/weekly")
def analytics_weekly():
    return analyze_weekly_patterns(load_data())


@app.get("/api/analytics/baselines")
def analytics_baselines():
    return calculate_personal_baselines(load_data())


@app.get("/api/analytics/trends")
def analytics_trends():
    return analyze_trends(load_data())


# ========== READINESS ENDPOINTS ==========

@app.get("/api/readiness")
def readiness_today():
    return readiness_engine.readiness_today()


@app.get("/api/readiness/history")
def readiness_history(days: int = 30):
    return readiness_engine.readiness_history(days=days)


@app.get("/api/readiness/{date_str}")
def readiness_for_date(date_str: str):
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        return _error("Date must be YYYY-MM-DD", status=400)
    return readiness_engine.score_date(db.get_all_days(), date_str)


# ========== SYNC ENDPOINTS ==========

@app.get("/api/sync/status")
def sync_status():
    if not SYNC_AVAILABLE:
        status = {"status": "unavailable", "message": "garminconnect not installed"}
    else:
        status = db.get_status()
    status["sync_available"] = SYNC_AVAILABLE
    status["sync_running"] = _sync_state["running"]
    status["last_sync_result"] = _sync_state["last_result"]
    status["last_sync_error"] = _sync_state["last_error"]
    status["last_sync_run_at"] = _sync_state["last_run_at"]
    return status


async def _json_body(request: Request) -> dict:
    try:
        body = await request.json()
        return body if isinstance(body, dict) else {}
    except Exception:
        return {}


@app.post("/api/sync/latest")
async def sync_latest_endpoint(request: Request):
    if not SYNC_AVAILABLE:
        return _error("garminconnect not installed. Run: uv sync in backend/")
    body = await _json_body(request)
    days = body.get("days", 7)

    if not _start_sync(lambda: sync_latest(get_garmin_client(), days=days)):
        return _error("Sync already running", status=409)
    return JSONResponse(
        status_code=202,
        content={
            "message": f"Sync started for last {days} days",
            "status_url": "/api/sync/status",
        },
    )


@app.post("/api/sync/full")
async def sync_full_endpoint():
    if not SYNC_AVAILABLE:
        return _error("garminconnect not installed. Run: uv sync in backend/")

    if not _start_sync(lambda: sync_full(get_garmin_client())):
        return _error("Sync already running", status=409)
    return JSONResponse(
        status_code=202,
        content={
            "message": "Full historical sync started",
            "status_url": "/api/sync/status",
        },
    )


@app.post("/api/sync/range")
async def sync_range_endpoint(request: Request):
    if not SYNC_AVAILABLE:
        return _error("garminconnect not installed. Run: uv sync in backend/")
    body = await _json_body(request)
    if "start" not in body:
        return _error("Body must include 'start' date (YYYY-MM-DD)", status=400)

    start_str = body["start"]
    end_str = body.get("end", datetime.today().strftime("%Y-%m-%d"))
    overwrite = body.get("overwrite", False)

    def job():
        start = datetime.strptime(start_str, "%Y-%m-%d").date()
        end = datetime.strptime(end_str, "%Y-%m-%d").date()
        return sync_date_range(get_garmin_client(), start, end, overwrite=overwrite)

    if not _start_sync(job):
        return _error("Sync already running", status=409)
    return JSONResponse(
        status_code=202,
        content={
            "message": f"Range sync started: {start_str} → {end_str}",
            "status_url": "/api/sync/status",
        },
    )


# ========== COACH ENDPOINT ==========

@app.post("/api/coach/chat")
async def coach_chat(request: Request):
    """Stream a grounded coach reply to a user question.

    The grounding context is assembled server-side (coach.stream_answer), so
    the client only sends {"question": "..."}. Returns a plain-text token
    stream; if the LLM host is unreachable, returns a clean 503 JSON error
    before any streaming starts (so the client can fall back to a cached
    briefing rather than parse a broken stream).
    """
    body = await _json_body(request)
    question = (body.get("question") or "").strip()
    if not question:
        return _error("Body must include a non-empty 'question'", status=400)

    stream = coach.stream_answer(question)
    # Pull the first token eagerly so a connection failure becomes a 503 JSON
    # error instead of a 200 with an empty/broken body.
    try:
        first = await anext(stream)
    except StopAsyncIteration:
        first = None
    except coach.LLMNotConfigured as e:
        return _error(str(e), status=503)

    async def body_stream():
        if first is not None:
            yield first
        async for delta in stream:
            yield delta

    return StreamingResponse(body_stream(), media_type="text/plain; charset=utf-8")


def run_server(port: int = 8081):
    print(f"🚀 Health Data API Server running at http://localhost:{port}")
    print("\n📊 Endpoints:")
    for line in ENDPOINT_LIST:
        print(f"   {line}")
    sync_txt = "✅ available" if SYNC_AVAILABLE else "❌ unavailable (run: cd backend && uv sync)"
    print(f"\n   Garmin sync: {sync_txt}")
    print("\n⏹️  Press Ctrl+C to stop")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")


if __name__ == "__main__":
    run_server()
