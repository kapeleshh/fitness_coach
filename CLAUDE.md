# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal fitness coach that turns Garmin health data (sleep, HRV, stress, body battery, activity) plus workout history from Strava and Garmin into insights. Two independent parts:

- `backend/` — Python 3.12+ (FastAPI + uvicorn, APScheduler, SQLite via stdlib `sqlite3`, optional `garminconnect`), managed with `uv`
- `mobile_app/` — Flutter app (Material 3), currently targeting web; all screens read from the `healthApiService` singleton (no Provider)

They communicate only over HTTP. The API base URL lives in `mobile_app/lib/config.dart` (default `http://localhost:8081`), overridable at build/run time with `--dart-define=API_BASE_URL=...`.

## Commands

### Backend (run from `backend/`)

```bash
uv sync                        # install deps (fastapi, uvicorn, apscheduler, garminconnect, ...)
python api_server.py           # start FastAPI on port 8081 (uvicorn)
python garmin_sync.py          # live-sync last 7 days from Garmin Connect into SQLite (needs backend/.env)
python garmin_sync.py --full   # sync all history; --start/--end for a range (wellness + activities)
python strava_import.py data/<export>.zip --tz Asia/Tokyo   # backfill activity history from a Strava bulk export
python strava_sync.py --auth   # one-time Strava OAuth (needs STRAVA_CLIENT_ID/SECRET in backend/.env)
python strava_sync.py          # incremental Strava activity sync; --status for counts
python garmin_parser.py        # parse a manual Garmin export in data/ → parsed_health_data.json (legacy; auto-imported into SQLite on server start when the DB is empty)
python db.py --coverage        # field-coverage audit of the wellness data + activity counts per source
python db.py --import-json parsed_health_data.json   # manual legacy-JSON import
pytest                         # run tests (golden contract + db + readiness + coach + behavior)
pytest tests/test_readiness.py -k <name>   # single file / single test
ruff check .                   # lint
```

Prefix with `uv run` if the venv isn't activated.

Golden contract files in `backend/tests/goldens/` were captured from the original stdlib server on a synthetic dataset — they pin the API contract across refactors. Don't regenerate them from the FastAPI implementation.

Test isolation (`tests/conftest.py`): use the `temp_db` (empty) or `populated_db` (deterministic 90-day synthetic dataset) fixtures. They work by setting env vars the backend honors — `FITNESS_COACH_DB` (SQLite path override), `GARMIN_AUTO_SYNC=0`/`STRAVA_AUTO_SYNC=0` (no scheduler), and `FITNESS_COACH_IMPORT_LEGACY=0` (stops the empty-DB startup import from pulling a developer's real `parsed_health_data.json` into the test DB). Any new test touching the DB or the app must go through these fixtures. Synthetic activities (Garmin sessions each with a Strava auto-upload twin, plus pre-Garmin Strava history) come from `generate_activities()` in `tests/synthetic.py`; Strava API tests use `httpx.MockTransport`, never the network.

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
   - **Activities** (table `activities`, one row per session) come from `strava_import.py` (bulk-export `activities.csv`; duplicated headers — the last copy is SI units), `strava_sync.py` (API v3, tokens in `user_settings`, each page ingested as it arrives so a 429 keeps progress), and `garmin_sync.sync_activities()` (runs at the end of every Garmin range sync). All go through `activities.ingest()`, which normalizes and recomputes **cross-source dedup** over the whole table: same sport family + start within 5 min + duration within 10% → the Strava copy gets `duplicate_of` pointing at the Garmin row (Garmin preferred; it carries native training load). Every row is kept so re-syncs stay idempotent; `db.get_activities()` returns canonical rows only unless `include_duplicates=True`.
   - **Missing-data policy** (`db.py`): metric columns are nullable; physiologically impossible zeros (HRV 0, sleep score 0, resting HR 0, ...) are stored as NULL. The legacy API contract is preserved via `get_all_days(legacy_zero_fill=True)`, which restores the old 0-filled shape — new analytics (readiness/load) must read the raw NULL-aware records instead.
2. **Serve** — `api_server.py` is a FastAPI app (uvicorn, port 8081, CORS enabled) with the same endpoint contract as the original stdlib server (pinned by golden tests). Analytics endpoints are backed by `analytics_engine.py`; sync-trigger endpoints by `garmin_sync.py` (optional import — the server runs without `garminconnect`, with sync disabled). A background APScheduler job auto-syncs every `GARMIN_SYNC_INTERVAL_HOURS` (default 6) when credentials exist — Garmin then Strava, sequentially inside the single `_start_sync` slot (one SQLite writer; manual `/api/sync/*` triggers return 409 while it runs); disable per source with `GARMIN_AUTO_SYNC=0` / `STRAVA_AUTO_SYNC=0`. Unknown GET paths return the full endpoint list.
3. **Display** — Flutter screens fetch from the API and render dashboards with hand-built Material widgets (no chart packages; fl_chart will be re-added when real charts land).

The daily record schema is defined in the `DailyHealthData` dataclass in `backend/garmin_parser.py`; the Flutter side consumes raw JSON maps (no mirrored Dart model).

## Key Architecture Notes

- **Single data layer**: all screens read from the `healthApiService` singleton (`lib/services/health_api_service.dart`) — no Provider, no mock services (dead mock/typed-model code was deleted; see git history if needed). The API base URL lives in `lib/config.dart` and is overridable with `--dart-define=API_BASE_URL=...`. The service takes an injectable `http.Client` (tests use `package:http/testing` `MockClient`), and newer screens take an optional `service` parameter defaulting to the singleton. `fetchReadiness`/`fetchReadinessHistory`/`fetchTrainingLoad` throw `ApiException` carrying the server's `error` message; `askCoach` streams the reply text (works on web: `package:http` 1.6 uses `fetch` streams). JSON is decoded from bytes as UTF-8 because FastAPI sends no charset and briefings contain non-ASCII punctuation. No statistics are computed in Dart: Insights, Patterns and Predictions render what `/api/insights`, `/api/correlations` and `/api/outlook` return, and show missing values as "—", never 0.
- **Navigation**: bottom bar is Today | Coach | My Data | Insights | Analyze. Analyze is a hub that pushes Patterns, Predictions and AI Lab as full pages; keep the bar at five tabs.
- **Tests**: `test/widget_test.dart` holds the navigation smoke tests plus `HealthApiService` unit tests; `test/today_screen_test.dart` and `test/coach_screen_test.dart` drive those screens through a `MockClient`. The package's SDK lower bound (3.0) pins the Dart language version, so 3.7+ features such as `_` wildcard parameters don't compile. Keep `flutter analyze` and `flutter test` green.
- **`analytics_engine.py` is pure stdlib** — correlations, anomaly detection, trends etc. are hand-rolled (Pearson via `math`). It is NULL-aware: it reads `db.get_all_days()` as stored, skips `None`, and keeps real zeros (0 active minutes counts). `lagged_pairs()` pairs metric A on day d with metric B on day d + lag by calendar date, and "recent" windows are calendar days, so a day with no record never shifts a pairing. `pearson_correlation()` returns `None` (not 0) when there are under 3 pairs or a side is constant. The `/api/analytics/*` goldens use complete consecutive data, so they're unchanged by this. Don't add heavy deps casually.
- **Insights engine** (`insights_engine.py`; `GET /api/insights`, `/api/correlations`, `/api/correlations/pair?x=&y=&lag=`, `/api/outlook`): the numbers behind the app's Insights, Patterns and Predictions tabs, which used to be computed in Dart from 0-filled data. Weekly summaries use calendar weeks and need 3 days per week to report a change; insight rules are skipped when their metric is missing; a benchmark is always the week's average (the app labels it "Avg"); comparisons against a baseline need 3 readings. Correlations reuse `analytics_engine.lagged_pairs`/`pearson_correlation`/`categorize_strength`. The outlook's tomorrow-body-battery heuristic reports its accuracy as a backtest (`mean_abs_error` over the last 60 days), never an invented confidence.
- **New endpoints** go in `api_server.py` (FastAPI routes) and must be added to `ENDPOINT_LIST` (the 404 body). The `unknown_path` golden treats `ENDPOINT_LIST` as a superset check, so adding an endpoint doesn't break the contract test.
- **Readiness engine** (`readiness_engine.py`, `GET /api/readiness`, `/api/readiness/history`, `/api/readiness/{date}`): pure-stdlib, NULL-aware daily readiness (0-100, green/amber/red) from wellness only. Two-axis composite — autonomic (ln-HRV 7-day vs 60-day baseline + SWC deadband + CV penalty, morning body battery, resting-HR) 0.65 and sleep 0.35 — with Garmin `hrv_status` cold-start fallback, illness/severe-HRV overrides, and a deterministic templated `briefing`. Reads `db.get_all_days(legacy_zero_fill=False)`; baselines are point-in-time (no lookahead). It intentionally does **not** reuse `analytics_engine.py` (that module is legacy zero-fill). Constants/methodology are literature-grounded (Plews/Buchheit) — retune constants at the top of the module, not scattered.
- **Training load engine** (`training_load_engine.py`, `GET /api/training-load`, `/api/training-load/history`): pure-stdlib, deterministic. One load per dedup group, from the best signal anywhere in the group — Garmin training load > Banister TRIMP (avg HR; resting HR point-in-time from wellness, max HR from `ATHLETE_MAX_HR`/setting `athlete_max_hr` or observed; curve via `TRIMP_SEX`) > Strava Relative Effort > duration × per-sport rate — and each session records its `method`. Daily CTL (42-day) / ATL (7-day) exponential load, TSB = CTL − ATL, form % = TSB / CTL (scale-free, drives `form_band`), and a 7:28 EWMA ACWR that only raises a neutral `load_spike` flag. **Every daily metric is the state entering the day** (load through yesterday), the same moment readiness scores. Rest days are load 0; confidence comes from history length and the share of recent load that was measured rather than estimated. `/api/readiness` and `/api/readiness/{date}` gain a `training_load` object and a fused note appended to `briefing` (`annotate_readiness`); the readiness *score* stays wellness-only. Constants live at the top of the module.
- **LLM coach** (`coach.py`, `POST /api/coach/chat`): streams a reply from an OpenAI-compatible endpoint (`LLM_BASE_URL`/`LLM_MODEL`/`LLM_API_KEY`, default local Ollama) — host-swappable (Ollama/mlx-lm/LM Studio/llama.cpp). Grounding is assembled **server-side** in `coach.build_context()` from NULL-aware wellness records; the model must never invent numbers. The context carries today's readiness, recent wellness, and a training-load section. **No Strava data reaches the model**: Strava's API Policy (effective 2026-06-01) bars Strava Data and anything derived from it from grounding an AI application, so the coach computes load with `training_load_engine.compute(exclude_sources=coach.AI_EXCLUDED_SOURCES)` — Garmin rows only, which also drops effort scores borrowed from Strava twins and Strava-observed max HR. Keep any new coach context on that path. Consequence: the coach's fitness/form can differ from `/api/training-load` — while pre-Garmin Strava history still contributes (it fades with the 42-day time constant) and whenever sessions exist only on Strava. That gap is expected; don't close it by feeding Strava-derived numbers to the model. Activity names are left out (free text, an injection vector). Clients send only `{"question": ...}`. LLM config resolves env var → DB settings overrides (`db.get_all_settings()`, keys `llm_base_url`/`llm_model`/`llm_api_key`) → default. In the Flutter app, Today and Coach use the readiness, training-load and coach endpoints; Insights, Patterns and Predictions use the insights endpoints; My Data uses `/api/summary` and `/api/health-data`; AI Lab uses `/api/analytics/*`.

## Privacy Constraints

`data/`, `backend/parsed_health_data.json`, `backend/fitness.db`, and `.env` files are gitignored because they contain personal health data and Garmin/Strava credentials (Strava OAuth tokens live in `fitness.db`'s `user_settings`; Strava exports belong under `data/`). Never commit them, and never paste real health data values or credentials into code, tests, or docs — tests use the synthetic generator in `backend/tests/synthetic.py`.
