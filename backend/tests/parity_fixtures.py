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
import math
import os
import random
import statistics
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


def numerics() -> dict[str, list]:
    """Cases for the Dart helpers that reproduce Python's numeric behaviour:
    round() (ties to even, on the exact binary value), fixed-point formatting
    in f-strings, sum() (compensated for floats since 3.12), repr() of
    floats, statistics.median, and the libm functions the engines call."""
    rng = random.Random(11)
    ties = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 0.125, 0.375, -0.125, 2.675, 1.005,
            0.285, 1.45, 2.345, 123456.785, 1e-7, -0.4, 0.0, -0.0, 100.0, 7.0]
    values = ties + [rng.uniform(-300, 300) for _ in range(60)]
    values += [round(rng.uniform(-100, 100), 3) for _ in range(60)]
    values += [k / 16 for k in range(-40, 41, 3)]
    rounds = [[x, None, round(x)] for x in values]
    rounds += [[x, n, round(x, n)] for x in values for n in (0, 1, 2, 3)]
    formats = [[x, spec, format(x, spec)]
               for x in values for spec in (".0f", "+.0f", ".1f", "+.1f", ".2f")]
    sums = [[0.1] * 10, [1, 2, 3], [1, 2.5, 3], [1e16, 1.0, -1e16], [3, 0.1, 0.2, 4]]
    sums += [[rng.uniform(-1, 1) * 10 ** rng.randint(-3, 3) for _ in range(rng.randint(1, 40))]
             for _ in range(40)]
    sums += [[rng.choice([rng.randint(0, 9), rng.uniform(0, 9)]) for _ in range(12)]
             for _ in range(20)]
    reprs = [[x, repr(x)] for x in values + [1e16, 1.5e16, 1e-5, 2.5e-5, 1e21, 123.456e-9]]
    medians = [[xs, statistics.median(xs)] for xs in
               ([1, 3], [1, 2, 3], [2.0, 1.0], [5], [rng.uniform(0, 50) for _ in range(9)],
                [rng.randint(40, 80) for _ in range(8)])]
    logs = [[x, math.log(x)] for x in (rng.uniform(5, 150) for _ in range(30))]
    exps = [[x, math.exp(x)] for x in (rng.uniform(-6, 6) for _ in range(30))]
    return {"round": rounds, "format": formats,
            "sum": [[xs, sum(xs)] for xs in sums], "repr": reprs,
            "median": medians, "log": logs, "exp": exps}


def readiness_scenarios() -> list[dict]:
    """The scenarios of tests/test_readiness.py (illness, cold start, stale
    HRV, short sleep, ...) with readiness_today's full answer for each, so
    the Dart port is checked on branches the 90-day dataset never reaches."""
    import readiness_engine
    from tests.test_readiness import _series, _set_recent

    insufficient = [{"date": "2026-07-07", "hrv": None, "hrv_status": None,
                     "resting_hr": None, "sleep_score": None, "body_battery_start": None}]
    malformed = _series(30) + [{"date": "not-a-date", "hrv": 50, "hrv_status": "BALANCED",
                                "resting_hr": 50, "sleep_score": 80, "body_battery_start": 70}]
    bb_capped = _set_recent(_set_recent(_series(60, bb=72), 7, hrv=50.0, resting_hr=53),
                            1, hrv=50.0, resting_hr=53, body_battery_start=95)
    severe = _set_recent(_set_recent(_series(60, bb=72), 7, hrv=35.0),
                         1, hrv=35.0, body_battery_start=95, sleep_score=96)
    scenarios = {
        "normal_full": _series(60),
        "suppressed": _set_recent(_series(60), 5, hrv=38.0),
        "illness": _set_recent(_series(60), 3, hrv=34.0, resting_hr=60),
        "cold_start": _series(10),
        "stale_hrv": _set_recent(_series(60), 5, hrv=None, hrv_status="BALANCED"),
        "short_sleep": _set_recent(_series(60, sleep=92), 1, deep_sleep_minutes=40,
                                   light_sleep_minutes=120, rem_sleep_minutes=60),
        "missing_hrv": _set_recent(_series(60), 8, hrv=None, hrv_status=None),
        "insufficient": insufficient,
        "warming_unknown": _series(14, status="UNKNOWN"),
        "warming_illness": _set_recent(_series(20, status="UNKNOWN"), 3, hrv=34.0,
                                       resting_hr=62),
        "body_battery_capped": bb_capped,
        "body_battery_normal": _set_recent(_series(60, bb=72), 1, body_battery_start=95),
        "severe_hrv": severe,
        "malformed_date": malformed,
        "no_jitter": _series(40, jitter=False),
    }
    return [{"name": name, "records": rows, "expected": readiness_engine.readiness_today(rows)}
            for name, rows in scenarios.items()]


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
        "readiness_scenarios": readiness_scenarios(),
        "training_load": training_load_engine.compute(),
        # Expected API bodies, keyed by request path
        "api": api,
        # Python numeric behaviour the Dart helpers must reproduce
        "numerics": numerics(),
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
