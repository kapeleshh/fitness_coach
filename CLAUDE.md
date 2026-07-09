# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal fitness coach that turns Garmin health data (sleep, HRV, stress, body battery, activity) into insights. Two independent parts:

- `backend/` — Python 3.12+ (FastAPI + uvicorn, APScheduler, SQLite via stdlib `sqlite3`, optional `garminconnect`), managed with `uv`
- `mobile_app/` — Flutter app (Material 3), currently targeting web; all screens read from the `healthApiService` singleton (no Provider)

They communicate only over HTTP. The API base URL lives in `mobile_app/lib/config.dart` (default `http://localhost:8081`), overridable at build/run time with `--dart-define=API_BASE_URL=...`.

## Commands

### Backend (run from `backend/`)

```bash
uv sync                        # install deps (fastapi, uvicorn, apscheduler, garminconnect, ...)
python api_server.py           # start FastAPI on port 8081 (uvicorn)
python garmin_sync.py          # live-sync last 7 days from Garmin Connect into SQLite (needs backend/.env)
python garmin_sync.py --full   # sync all history; --start/--end for a range
python garmin_parser.py        # parse a manual Garmin export in data/ → parsed_health_data.json (legacy; auto-imported into SQLite on server start when the DB is empty)
python db.py --coverage        # field-coverage audit of the wellness data
python db.py --import-json parsed_health_data.json   # manual legacy-JSON import
pytest                         # run tests (golden contract + db + behavior)
ruff check .                   # lint
```

Golden contract files in `backend/tests/goldens/` were captured from the original stdlib server on a synthetic dataset — they pin the API contract across refactors. Don't regenerate them from the FastAPI implementation.

### Mobile app (run from `mobile_app/`)

```bash
flutter run -d chrome          # run the app (dev)
flutter analyze                # lint (flutter_lints)
flutter test                   # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter build web              # production web build
```

Serving a built app: `python -m http.server 8080` from `mobile_app/build/web`.

## Data Flow (the big picture)

1. **Ingest** — daily wellness records land in SQLite (`backend/fitness.db`, table `daily_wellness`):
   - `garmin_sync.py` pulls from the Garmin Connect API via `garminconnect`, using `GARMIN_EMAIL`/`GARMIN_PASSWORD` from `backend/.env` (tokens cached in `~/.garminconnect`), upserting one transaction per day
   - `garmin_parser.py` (legacy path) parses a manual Garmin Connect export in `data/` into `parsed_health_data.json`, which the server auto-imports into SQLite on startup when the DB is empty
   - **Missing-data policy** (`db.py`): metric columns are nullable; physiologically impossible zeros (HRV 0, sleep score 0, resting HR 0, ...) are stored as NULL. The legacy API contract is preserved via `get_all_days(legacy_zero_fill=True)`, which restores the old 0-filled shape — new analytics (readiness/load) must read the raw NULL-aware records instead.
2. **Serve** — `api_server.py` is a FastAPI app (uvicorn, port 8081, CORS enabled) with the same endpoint contract as the original stdlib server (pinned by golden tests). Analytics endpoints are backed by `analytics_engine.py`; sync-trigger endpoints by `garmin_sync.py` (optional import — the server runs without `garminconnect`, with sync disabled). A background APScheduler job auto-syncs every `GARMIN_SYNC_INTERVAL_HOURS` (default 6) when credentials exist; disable with `GARMIN_AUTO_SYNC=0`. Unknown GET paths return the full endpoint list.
3. **Display** — Flutter screens fetch from the API and render dashboards with hand-built Material widgets (no chart packages; fl_chart will be re-added when real charts land).

The daily record schema is defined in the `DailyHealthData` dataclass in `backend/garmin_parser.py`; the Flutter side consumes raw JSON maps (no mirrored Dart model).

## Key Architecture Notes

- **Single data layer**: all screens read from the `healthApiService` singleton (`lib/services/health_api_service.dart`) — no Provider, no mock services (dead mock/typed-model code was deleted; see git history if needed). The API base URL lives in `lib/config.dart` and is overridable with `--dart-define=API_BASE_URL=...`.
- **Tests**: `test/widget_test.dart` holds a navigation smoke test plus unit tests for `HealthApiService` computations. Keep `flutter analyze` and `flutter test` green.
- **`analytics_engine.py` is pure stdlib** — correlations, anomaly detection, trends etc. are hand-rolled (Pearson via `math`). It still consumes legacy zero-filled records (missing = 0); its statistical cleanup is a backlog item. Don't add heavy deps casually.
- **New endpoints** go in `api_server.py` (FastAPI routes) and must be added to `ENDPOINT_LIST` (the 404 body). The `unknown_path` golden treats `ENDPOINT_LIST` as a superset check, so adding an endpoint doesn't break the contract test.
- **Readiness engine** (`readiness_engine.py`, `GET /api/readiness`, `/api/readiness/history`, `/api/readiness/{date}`): pure-stdlib, NULL-aware daily readiness (0-100, green/amber/red) from wellness only. Two-axis composite — autonomic (ln-HRV 7-day vs 60-day baseline + SWC deadband + CV penalty, morning body battery, resting-HR) 0.65 and sleep 0.35 — with Garmin `hrv_status` cold-start fallback, illness/severe-HRV overrides, and a deterministic templated `briefing`. Reads `db.get_all_days(legacy_zero_fill=False)`; baselines are point-in-time (no lookahead). It intentionally does **not** reuse `analytics_engine.py` (that module is legacy zero-fill). Constants/methodology are literature-grounded (Plews/Buchheit) — retune constants at the top of the module, not scattered.
- **LLM coach** (`coach.py`, `POST /api/coach/chat`): streams a reply from an OpenAI-compatible endpoint (`LLM_BASE_URL`/`LLM_MODEL`/`LLM_API_KEY`, default local Ollama) — host-swappable (Ollama/mlx-lm/LM Studio/llama.cpp). Grounding is assembled **server-side** in `coach.build_context()` from NULL-aware wellness records; the model must never invent numbers. Readiness/training-load numbers get added to that context when those engines land. Clients send only `{"question": ...}`.

## Privacy Constraints

`data/`, `backend/parsed_health_data.json`, `backend/fitness.db`, and `.env` files are gitignored because they contain personal health data and Garmin credentials. Never commit them, and never paste real health data values or credentials into code, tests, or docs — tests use the synthetic generator in `backend/tests/synthetic.py`.
