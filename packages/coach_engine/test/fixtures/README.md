# Parity fixtures

Written by `backend/tests/parity_fixtures.py` from the synthetic dataset in
`backend/tests/synthetic.py`. Don't edit them by hand. Regenerate them from
`backend/` whenever a Python engine changes:

```bash
uv run python -m tests.parity_fixtures
```

`backend/tests/test_parity_fixtures.py` fails while these files are stale.

| File | What it holds |
|---|---|
| `wellness.json` | Input: daily wellness records as stored, newest first, missing values as `null` |
| `activities_raw.json` | Input: raw Garmin and Strava activities before normalizing |
| `activities.json` | Expected: normalized activities with `duplicate_of` links |
| `readiness.json` | Expected: the readiness result for every wellness date, keyed by date |
| `training_load.json` | Expected: sessions, the daily series and athlete parameters |
| `api.json` | Expected: the response body for each request the app makes, keyed by request path |
