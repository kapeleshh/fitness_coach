# Personal Fitness Coach

Turns your Garmin wellness data and your Garmin and Strava workout history into a daily readiness score, a training-load picture and a coach you can ask questions. It all runs locally on your own data.

## What it does

- **Sync**: Garmin Connect wellness (sleep, HRV, resting HR, body battery, stress, steps) and activities, refreshed every 6 hours. Strava history comes from your bulk export, with optional ongoing sync through the Strava API. Activities Garmin uploads to Strava are recognised as duplicates.
- **Readiness**: a daily 0–100 score (green, amber or red) built from HRV against your own baseline, resting heart rate, body battery and sleep.
- **Training load**: fitness, fatigue and form (CTL / ATL / TSB) from every session, with the method behind each session's number recorded.
- **Coach**: ask in plain language, and a language model answers using only the numbers the backend computed. Strava data is never sent to the model, because Strava's API Policy forbids it.
- **App**: a Flutter app (web for now) with Today, Coach, My Data, Insights and Analyze tabs.

Two parts, talking only over HTTP:

- `backend/`: Python 3.12+, FastAPI on port 8081 and SQLite (`backend/fitness.db`). It holds the sync jobs, the readiness and training-load engines, and the coach.
- `mobile_app/`: the Flutter app.

## Quick start

### 1. Backend

```bash
cd backend
uv sync
cp .env.example .env                    # add GARMIN_EMAIL and GARMIN_PASSWORD
uv run python garmin_sync.py --full     # first sync; later runs fetch the last 7 days
uv run python api_server.py             # API on http://localhost:8081
```

While it runs, the server re-syncs every 6 hours (`GARMIN_SYNC_INTERVAL_HOURS`; `GARMIN_AUTO_SYNC=0` turns it off). Without Garmin credentials you can export your data from Garmin Connect into `data/` and run `uv run python garmin_parser.py`. The server imports the result the first time it starts.

### 2. Strava history (optional)

1. Request your archive in Strava (Settings → My Account → Download or Delete Your Account) and put the zip in `data/`.
2. `uv run python strava_import.py data/<export>.zip --tz <your IANA timezone>`
3. For ongoing sync, create an API application at <https://www.strava.com/settings/api> with callback domain `localhost`. Put `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` in `.env`, then run `uv run python strava_sync.py --auth` once.

### 3. Coach (optional)

Install [Ollama](https://ollama.com) and run `ollama pull llama3.1:8b`. Any OpenAI-compatible server works too: set `LLM_BASE_URL`, `LLM_MODEL` and `LLM_API_KEY` in `.env`. Without a model the Coach tab shows an error, and everything else still works.

### 4. App

```bash
cd mobile_app
flutter run -d chrome
# Backend on another machine:
#   flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.10:8081
```

## API

| Endpoint | Returns |
|---|---|
| `GET /api/readiness`, `/api/readiness/{date}`, `/api/readiness/history` | Readiness score, band and briefing, including the training-load note |
| `GET /api/training-load`, `/api/training-load/history` | Fitness, fatigue, form and recent sessions |
| `GET /api/activities`, `/api/activities/{source:id}` | Activities from Garmin and Strava, duplicates hidden |
| `POST /api/coach/chat` | A streamed coach reply to `{"question": "..."}` |
| `GET /api/insights`, `/api/correlations`, `/api/correlations/pair`, `/api/outlook` | Insights, correlations and tomorrow's body-battery outlook with its measured error |
| `GET /api/health-data`, `/api/summary`, `/api/analytics/*` | Daily wellness records and the older analytics |
| `GET /api/sync/status`, `POST /api/sync/{latest,full,range,strava}` | Sync state and manual sync triggers |

An unknown `GET` path returns the full endpoint list.

## Privacy

Your data stays on your machine. `data/`, `backend/fitness.db`, `backend/parsed_health_data.json` and `.env` are gitignored; Strava's OAuth tokens are stored in `fitness.db`. The coach's language model runs locally by default, and nothing from Strava is included in what it sees.

## Development

```bash
cd backend && uv run pytest && uv run ruff check .
cd mobile_app && flutter analyze && flutter test
```

Tests use synthetic data only (`backend/tests/synthetic.py`); no real health data belongs in code, tests or docs.

## Roadmap

Done: Garmin and Strava ingest with dedup, readiness, training load, the coach, the Today and Coach screens, and every number in the app computed by the backend.

Next:

- **Proactive coaching**: a morning briefing after each sync, a weekly report, and notifications.
- **Later**: self-experiments (an intervention compared against a baseline, with effect sizes), backtested forecasts, and phone builds or a PWA.

## License

Personal project, not for distribution.
