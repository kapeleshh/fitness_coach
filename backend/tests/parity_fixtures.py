"""Expected outputs for the Dart engines in packages/coach_engine.

The Python engines are the reference for the Dart port. This module runs them
on the deterministic synthetic dataset (wellness from generate_days(), Garmin
and Strava activities from generate_activities()) and writes their inputs and
outputs as JSON fixtures that the Dart parity tests load.

These are not the stdlib-server goldens in tests/goldens/: those pin the API
contract and are never regenerated, while these follow the Python engines and
are regenerated whenever an engine changes:

    uv run python -m tests.parity_fixtures

tests/test_parity_fixtures.py fails while the committed files are stale.
"""

import json
import os
import tempfile
from pathlib import Path

from tests.synthetic import generate_activities, generate_days

FIXTURE_DIR = (
    Path(__file__).resolve().parents[2] / "packages" / "coach_engine" / "test" / "fixtures"
)

# Engine settings read from the environment. Cleared so a developer's
# backend/.env (loaded when api_server imports the sync modules) can't change
# the expected numbers.
ENGINE_ENV = ("ATHLETE_MAX_HR", "TRIMP_SEX")

# The requests the app makes, as the app makes them. The local data source
# that replaces HTTP in the public app must return these bodies.
API_REQUESTS = [
    "/api/readiness",
    "/api/readiness/history?days=14",
    "/api/training-load",
    "/api/insights",
    "/api/correlations",
    "/api/correlations/pair?x=sleep_score&y=hrv&lag=0",
    "/api/correlations/pair?x=avg_stress&y=sleep_score&lag=1",
    "/api/outlook",
    "/api/summary",
    "/api/health-data",
]


def load_dataset() -> list[dict]:
    """Write the synthetic wellness and activities into the current database
    and return the raw activity records that were ingested."""
    import activities
    import db

    raw = generate_activities()
    raw_records = raw["garmin"] + raw["strava"]
    db.upsert_days(generate_days())
    activities.ingest(raw_records)
    return raw_records


def build_fixtures(raw_activities: list[dict]) -> dict[str, object]:
    """Fixture name -> JSON value, read from a database holding only the
    synthetic dataset."""
    from fastapi.testclient import TestClient

    import api_server
    import db
    import readiness_engine
    import training_load_engine

    wellness = db.get_all_days()
    with TestClient(api_server.app) as client:
        api = {path: client.get(path).json() for path in API_REQUESTS}
    return {
        # Inputs
        "wellness": wellness,
        "activities_raw": raw_activities,
        # Expected engine outputs
        "activities": db.get_activities(include_duplicates=True),
        "readiness": {r["date"]: readiness_engine.score_date(wellness, r["date"])
                      for r in wellness},
        "training_load": training_load_engine.compute(),
        # Expected API bodies, keyed by request path
        "api": api,
    }


def dumps(value: object) -> str:
    return json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> None:
    for name, value in (("GARMIN_AUTO_SYNC", "0"), ("STRAVA_AUTO_SYNC", "0"),
                        ("FITNESS_COACH_IMPORT_LEGACY", "0")):
        os.environ[name] = value
    with tempfile.TemporaryDirectory() as tmp:
        db_file = Path(tmp) / "parity.db"
        os.environ["FITNESS_COACH_DB"] = str(db_file)

        import api_server  # noqa: F401 - imports the sync modules, which load backend/.env
        import db

        for name in ENGINE_ENV:
            os.environ.pop(name, None)
        # Never write the synthetic dataset into the real database.
        assert db.db_path() == db_file, db.db_path()
        db.init_db()
        fixtures = build_fixtures(load_dataset())

    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for name, value in fixtures.items():
        (FIXTURE_DIR / f"{name}.json").write_text(dumps(value), encoding="utf-8")
        print(f"wrote {name}.json")


if __name__ == "__main__":
    main()
