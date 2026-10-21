"""FastAPI server for parsed Garmin health data.

Same endpoint contract as the original stdlib http.server implementation
(verified by golden contract tests in tests/test_contract.py), now backed
by SQLite (db.py) instead of parsed_health_data.json.

Also runs a background scheduler that keeps Garmin wellness/activities and
Strava activities fresh when the respective credentials are configured.
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
import insights_engine
import readiness_engine
import strava_sync
import training_load_engine
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
    "GET  /api/training-load",
    "GET  /api/training-load/history",
    "GET  /api/insights",
    "GET  /api/correlations",
    "GET  /api/correlations/pair?x=METRIC&y=METRIC&lag=0",
    "GET  /api/outlook",
    "GET  /api/activities",
    "GET  /api/activities/SOURCE:ID",
    "GET  /api/sync/status",
    "POST /api/sync/latest",
    "POST /api/sync/full",
    "POST /api/sync/range",
    "POST /api/sync/strava",
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


def _scheduled_sync(garmin: bool, strava: bool):
    """Periodic freshness sync — skipped silently if one is already running.
    Sources run sequentially in the one sync slot (one SQLite writer), and a
    failure in one never blocks the other."""
    def job():
        results, errors = {}, []
        for name, enabled, run in (
            ("garmin", garmin, lambda: sync_latest(get_garmin_client(), days=3)),
            ("strava", strava, strava_sync.sync),
        ):
            if not enabled:
                continue
            try:
                results[name] = run()
            except (Exception, SystemExit) as e:  # noqa: BLE001 — isolate sources
                # repr, not str: get_garmin_client()'s SystemExit(1) would
                # otherwise read as just "1".
                errors.append(f"{name}: {e!r}")
        if errors:
            raise RuntimeError("; ".join(errors))
        return results

    _start_sync(job)


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
    garmin_auto = (
        SYNC_AVAILABLE
        and _credentials_configured()
        and os.getenv("GARMIN_AUTO_SYNC", "1") != "0"
    )
    strava_auto = (
        strava_sync.is_configured() and os.getenv("STRAVA_AUTO_SYNC", "1") != "0"
    )
    if garmin_auto or strava_auto:
        from apscheduler.schedulers.background import BackgroundScheduler
        interval_hours = float(os.getenv("GARMIN_SYNC_INTERVAL_HOURS", "6"))
        scheduler = BackgroundScheduler()
        scheduler.add_job(
            _scheduled_sync, "interval", hours=interval_hours,
            kwargs={"garmin": garmin_auto, "strava": strava_auto},
        )
        scheduler.start()
        sources = ", ".join(n for n, on in (("Garmin", garmin_auto), ("Strava", strava_auto)) if on)
        print(f"⏰ Auto-sync every {interval_hours}h enabled ({sources})")

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
    records = db.get_all_days()
    if not records:
        return {"error": "No data available"}

    def _avg(key, digits):
        # Over the days that have the metric; null (not 0) when none do.
        vals = [d[key] for d in records if d.get(key) is not None]
        return round(sum(vals) / len(vals), digits) if vals else None

    return {
        "total_days": len(records),
        "date_range": {"start": records[-1]["date"], "end": records[0]["date"]},
        "averages": {
            "sleep_score": _avg("sleep_score", 1),
            "hrv": _avg("hrv", 1),
            "stress": _avg("avg_stress", 1),
            "steps": _avg("steps", 0),
        },
        # The day itself keeps the legacy 0-filled shape the contract pins.
        "recent_day": db.get_day(records[0]["date"], legacy_zero_fill=True),
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

def _with_training_load(readiness: dict) -> dict:
    """Attach the training-load state for the readiness date and append the
    fused load note to the briefing (readiness scoring stays wellness-only)."""
    state = training_load_engine.state_on(readiness["date"], training_load_engine.compute())
    return training_load_engine.annotate_readiness(readiness, state)


@app.get("/api/readiness")
def readiness_today():
    return _with_training_load(readiness_engine.readiness_today())


@app.get("/api/readiness/history")
def readiness_history(days: int = 30):
    return readiness_engine.readiness_history(days=days)


@app.get("/api/readiness/{date_str}")
def readiness_for_date(date_str: str):
    try:
        datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        return _error("Date must be YYYY-MM-DD", status=400)
    return _with_training_load(readiness_engine.score_date(db.get_all_days(), date_str))


# ========== TRAINING LOAD ENDPOINTS ==========

@app.get("/api/training-load")
def training_load_today():
    return training_load_engine.training_load_today()


@app.get("/api/training-load/history")
def training_load_history(days: int = 90):
    return training_load_engine.training_load_history(days=days)


# ========== INSIGHTS ENDPOINTS ==========
# The numbers behind the app's Insights, Patterns and Predictions tabs, which
# the app used to compute on the device from 0-filled data.

@app.get("/api/insights")
def insights():
    records = db.get_all_days()
    week = insights_engine.weekly_summary(records)
    readiness = readiness_engine.readiness_today(records)
    latest = records[0] if records else {}
    return {
        "date": week["date"],
        "readiness": {k: readiness.get(k) for k in ("score", "band", "label")},
        "today": {k: latest.get(k) for k in ("sleep_score", "hrv", "avg_stress")},
        "insights": insights_engine.insights(records, week),
        "weekly": week,
    }


@app.get("/api/correlations")
def correlations():
    records = db.get_all_days()
    return {"days": len(records),
            "correlations": insights_engine.discover_correlations(records)}


@app.get("/api/correlations/pair")
def correlation_pair(x: str | None = None, y: str | None = None, lag: int = 0):
    for metric in (x, y):
        if metric not in insights_engine.CORRELATION_METRICS:
            return _error(f"Unknown or missing metric: {metric!r}", status=400)
    if not 0 <= lag <= insights_engine.MAX_LAG_DAYS:
        return _error(f"lag must be 0-{insights_engine.MAX_LAG_DAYS} days", status=400)
    return {"metric1": x, "metric2": y, "lag_days": lag,
            **insights_engine.correlation(db.get_all_days(), x, y, lag)}


@app.get("/api/outlook")
def outlook():
    return insights_engine.outlook(db.get_all_days())


# ========== ACTIVITY ENDPOINTS ==========

def _valid_date(value: str | None) -> bool:
    if value is None:
        return True
    try:
        datetime.strptime(value, "%Y-%m-%d")
        return True
    except ValueError:
        return False


@app.get("/api/activities")
def list_activities(
    start: str | None = None,
    end: str | None = None,
    include_duplicates: bool = False,
):
    """Activities newest first, filtered by local date. Cross-source
    duplicates (Garmin auto-uploaded to Strava) are hidden unless asked for."""
    if not (_valid_date(start) and _valid_date(end)):
        return _error("start/end must be YYYY-MM-DD", status=400)
    return db.get_activities(start=start, end=end, include_duplicates=include_duplicates)


@app.get("/api/activities/{activity_id}")
def get_activity(activity_id: str):
    activity = db.get_activity(activity_id)
    if activity is None:
        return _error("Activity not found", status=404)
    return activity


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
    status["strava_configured"] = strava_sync.is_configured()
    status["activities"] = db.activity_summary()
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


@app.post("/api/sync/strava")
async def sync_strava_endpoint():
    if not strava_sync.is_configured():
        return _error(
            "Strava not configured. Set STRAVA_CLIENT_ID/STRAVA_CLIENT_SECRET in "
            "backend/.env and run: python strava_sync.py --auth",
            status=503,
        )
    if not _start_sync(strava_sync.sync):
        return _error("Sync already running", status=409)
    return JSONResponse(
        status_code=202,
        content={"message": "Strava sync started", "status_url": "/api/sync/status"},
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
    strava_txt = "✅ configured" if strava_sync.is_configured() else "➖ not configured"
    print(f"   Strava sync: {strava_txt}")
    print("\n⏹️  Press Ctrl+C to stop")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")


if __name__ == "__main__":
    run_server()
