"""SQLite storage layer for the fitness coach backend.

Replaces the single parsed_health_data.json file. Two tables for now
(Phase 1): daily_wellness and user_settings. Activity and plan tables are
added in later phases, designed against real payloads.

Data-integrity policy (the reason this module exists):
- Every metric column is NULLABLE. NULL means "not measured that day".
- The legacy pipeline stored missing metrics as 0, conflating "no HRV
  reading" with "HRV of 0 ms". normalize_record() maps physiologically
  impossible zeros to NULL on every write (sync and JSON import), so the
  Phase 2+ readiness/load engines compute baselines on real values only.
- For backward compatibility, get_all_days(legacy_zero_fill=True) restores
  the old 0-filled shape for the existing API endpoints and analytics code.
"""

import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import date, datetime
from pathlib import Path

BACKEND_DIR = Path(__file__).parent
DEFAULT_DB_PATH = BACKEND_DIR / "fitness.db"

# Ordered to match the legacy parsed_health_data.json record layout.
DAILY_FIELDS: dict[str, str] = {
    "date": "TEXT PRIMARY KEY",
    # Sleep
    "sleep_score": "INTEGER",
    "deep_sleep_minutes": "INTEGER",
    "light_sleep_minutes": "INTEGER",
    "rem_sleep_minutes": "INTEGER",
    "awake_minutes": "INTEGER",
    # NUMERIC affinity (not TEXT): Garmin sync stores epoch-millisecond
    # integers here and manual exports store ISO strings. TEXT affinity would
    # coerce the integers to strings; NUMERIC keeps an integer an integer and
    # leaves a non-numeric ISO string as text — preserving each source's type.
    "sleep_start_time": "NUMERIC",
    "sleep_end_time": "NUMERIC",
    "avg_sleep_stress": "REAL",
    "sleep_insight": "TEXT",
    "sleep_feedback": "TEXT",
    # Heart rate & HRV
    "resting_hr": "INTEGER",
    "min_hr": "INTEGER",
    "max_hr": "INTEGER",
    "hrv": "REAL",
    "hrv_status": "TEXT",
    # Body battery
    "body_battery_start": "INTEGER",
    "body_battery_end": "INTEGER",
    "body_battery_high": "INTEGER",
    "body_battery_low": "INTEGER",
    "body_battery_charged": "INTEGER",
    "body_battery_drained": "INTEGER",
    # Stress
    "avg_stress": "INTEGER",
    "max_stress": "INTEGER",
    "stress_rest_minutes": "INTEGER",
    "stress_low_minutes": "INTEGER",
    "stress_medium_minutes": "INTEGER",
    "stress_high_minutes": "INTEGER",
    # Activity
    "steps": "INTEGER",
    "distance_meters": "REAL",
    "active_calories": "INTEGER",
    "total_calories": "INTEGER",
    "floors_climbed": "INTEGER",
    "active_minutes": "INTEGER",
    # Respiration
    "avg_respiration": "REAL",
    "lowest_respiration": "REAL",
    "highest_respiration": "REAL",
}

# A value of exactly 0 in these fields cannot be a real measurement —
# it means the metric was missing. Mapped to NULL on write.
IMPOSSIBLE_ZERO_FIELDS = {
    "sleep_score",
    "avg_sleep_stress",
    "resting_hr",
    "min_hr",
    "max_hr",
    "hrv",
    "body_battery_start",
    "body_battery_end",
    "body_battery_high",
    "body_battery_low",
    "avg_stress",
    "max_stress",
    "total_calories",
    "avg_respiration",
    "lowest_respiration",
    "highest_respiration",
}

# Sleep-stage minutes CAN legitimately be 0 within a tracked night, but are
# meaningless when the whole sleep record is missing (sleep_score is NULL).
SLEEP_STAGE_FIELDS = {
    "deep_sleep_minutes",
    "light_sleep_minutes",
    "rem_sleep_minutes",
    "awake_minutes",
}

_NUMERIC_FIELDS = {
    name for name, sql_type in DAILY_FIELDS.items() if sql_type in ("INTEGER", "REAL")
}
_TEXT_FIELDS = {
    name for name, sql_type in DAILY_FIELDS.items()
    if sql_type == "TEXT" and name != "date"
}

# Legacy zero-fill defaults, matching the DailyHealthData dataclass defaults.
_LEGACY_DEFAULTS = {
    **{f: 0 for f in _NUMERIC_FIELDS},
    "avg_sleep_stress": 0.0,
    "hrv": 0.0,
    "distance_meters": 0.0,
    "avg_respiration": 0.0,
    "lowest_respiration": 0.0,
    "highest_respiration": 0.0,
    "sleep_insight": "",
    "sleep_feedback": "",
    "hrv_status": "UNKNOWN",
    "sleep_start_time": None,
    "sleep_end_time": None,
}


def db_path() -> Path:
    """Resolve the database path (env override for tests)."""
    return Path(os.getenv("FITNESS_COACH_DB", str(DEFAULT_DB_PATH)))


@contextmanager
def connect(path: Path | None = None):
    """Open a connection for one unit of work: commits on success,
    rolls back on exception, and always closes (Windows file locks)."""
    conn = sqlite3.connect(path or db_path())
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        with conn:
            yield conn
    finally:
        conn.close()


def init_db(path: Path | None = None) -> None:
    """Create tables if they don't exist."""
    columns = ",\n            ".join(
        f"{name} {sql_type}" for name, sql_type in DAILY_FIELDS.items()
    )
    with connect(path) as conn:
        conn.execute(f"""
        CREATE TABLE IF NOT EXISTS daily_wellness (
            {columns},
            synced_at TEXT
        )""")
        conn.execute("""
        CREATE TABLE IF NOT EXISTS user_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )""")


# ============= NORMALIZATION =============

def normalize_record(raw: dict) -> dict:
    """Apply the missing-data policy to one daily record.

    - Unknown keys are dropped; missing keys become NULL.
    - Impossible zeros -> NULL.
    - Sleep-stage minutes -> NULL when the sleep record itself is missing.
    - Empty strings -> NULL for text fields.
    """
    record: dict = {}
    for field in DAILY_FIELDS:
        value = raw.get(field)
        if field in _TEXT_FIELDS:
            record[field] = value if value not in ("", None) else None
        else:
            record[field] = value

    for field in IMPOSSIBLE_ZERO_FIELDS:
        if record.get(field) == 0:
            record[field] = None

    if record.get("sleep_score") is None:
        for field in SLEEP_STAGE_FIELDS:
            if record.get(field) == 0:
                record[field] = None
        # An hrv_status of UNKNOWN alongside a missing HRV reading carries
        # no information; treat as missing.
        if record.get("hrv") is None and record.get("hrv_status") == "UNKNOWN":
            record["hrv_status"] = None

    if not record.get("date"):
        raise ValueError("daily record requires a 'date'")
    return record


def _legacy_fill(record: dict) -> dict:
    """Restore the legacy 0-filled record shape expected by the current
    API contract and analytics code (NULL -> 0 / "" / "UNKNOWN")."""
    return {
        field: (record[field] if record[field] is not None else _LEGACY_DEFAULTS[field])
        if field != "date" else record[field]
        for field in DAILY_FIELDS
    }


# ============= DAILY WELLNESS =============

def upsert_days(records: list[dict], path: Path | None = None) -> int:
    """Insert or replace daily records in a single transaction.

    Records are normalized (missing-data policy) before writing.
    """
    if not records:
        return 0
    normalized = [normalize_record(r) for r in records]
    fields = list(DAILY_FIELDS)
    placeholders = ", ".join("?" for _ in fields) + ", ?"
    sql = (
        f"INSERT OR REPLACE INTO daily_wellness ({', '.join(fields)}, synced_at) "
        f"VALUES ({placeholders})"
    )
    now = datetime.now().isoformat(timespec="seconds")
    rows = [tuple(r[f] for f in fields) + (now,) for r in normalized]
    with connect(path) as conn:
        conn.executemany(sql, rows)
    return len(rows)


def get_all_days(legacy_zero_fill: bool = False, path: Path | None = None) -> list[dict]:
    """All daily records, newest first (data[0] == most recent, as the
    API contract and analytics code assume)."""
    fields = ", ".join(DAILY_FIELDS)
    with connect(path) as conn:
        rows = conn.execute(
            f"SELECT {fields} FROM daily_wellness ORDER BY date DESC"
        ).fetchall()
    records = [dict(row) for row in rows]
    if legacy_zero_fill:
        records = [_legacy_fill(r) for r in records]
    return records


def get_day(date_str: str, legacy_zero_fill: bool = False,
            path: Path | None = None) -> dict | None:
    fields = ", ".join(DAILY_FIELDS)
    with connect(path) as conn:
        row = conn.execute(
            f"SELECT {fields} FROM daily_wellness WHERE date = ?", (date_str,)
        ).fetchone()
    if row is None:
        return None
    record = dict(row)
    return _legacy_fill(record) if legacy_zero_fill else record


def get_existing_dates(path: Path | None = None) -> set[str]:
    with connect(path) as conn:
        rows = conn.execute("SELECT date FROM daily_wellness").fetchall()
    return {row["date"] for row in rows}


def count_days(path: Path | None = None) -> int:
    with connect(path) as conn:
        return conn.execute("SELECT COUNT(*) AS n FROM daily_wellness").fetchone()["n"]


def get_status(path: Path | None = None) -> dict:
    """Data-freshness summary (mirrors the old JSON-file status shape)."""
    with connect(path) as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS n, MIN(date) AS earliest, MAX(date) AS latest "
            "FROM daily_wellness"
        ).fetchone()
    if not row["n"]:
        return {"status": "no_data", "message": "No data in database. Run sync first."}

    latest = datetime.strptime(row["latest"], "%Y-%m-%d").date()
    days_stale = (date.today() - latest).days
    resolved = path or db_path()
    return {
        "status": "ok",
        "total_days": row["n"],
        "earliest_date": row["earliest"],
        "latest_date": row["latest"],
        "days_stale": days_stale,
        "needs_sync": days_stale > 1,
        "db_size_kb": round(resolved.stat().st_size / 1024, 1) if resolved.exists() else 0,
    }


# ============= JSON IMPORT (legacy migration) =============

def import_json(json_path: Path, path: Path | None = None) -> int:
    """One-time import of a legacy parsed_health_data.json into SQLite.

    Impossible zeros in the legacy file become NULL (see normalize_record).
    """
    with open(json_path, encoding="utf-8") as f:
        records = json.load(f)
    return upsert_days(records, path=path)


def coverage_report(path: Path | None = None) -> dict:
    """Field-coverage audit: % of days with each key readiness metric present."""
    records = get_all_days(path=path)
    total = len(records)
    if not total:
        return {"total_days": 0, "coverage": {}}
    key_fields = ["hrv", "sleep_score", "resting_hr", "body_battery_start", "avg_stress"]
    coverage = {
        f: round(100 * sum(1 for r in records if r[f] is not None) / total, 1)
        for f in key_fields
    }
    return {
        "total_days": total,
        "earliest": records[-1]["date"],
        "latest": records[0]["date"],
        "coverage_pct": coverage,
    }


# ============= USER SETTINGS =============

def get_setting(key: str, default=None, path: Path | None = None):
    with connect(path) as conn:
        row = conn.execute(
            "SELECT value FROM user_settings WHERE key = ?", (key,)
        ).fetchone()
    return json.loads(row["value"]) if row else default


def set_setting(key: str, value, path: Path | None = None) -> None:
    with connect(path) as conn:
        conn.execute(
            "INSERT OR REPLACE INTO user_settings (key, value) VALUES (?, ?)",
            (key, json.dumps(value)),
        )


def get_all_settings(path: Path | None = None) -> dict:
    with connect(path) as conn:
        rows = conn.execute("SELECT key, value FROM user_settings").fetchall()
    return {row["key"]: json.loads(row["value"]) for row in rows}


# ============= CLI =============

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Fitness coach database utilities")
    parser.add_argument("--import-json", metavar="PATH",
                        help="Import a legacy parsed_health_data.json into SQLite")
    parser.add_argument("--coverage", action="store_true",
                        help="Print a field-coverage audit of the wellness data")
    args = parser.parse_args()

    init_db()
    if args.import_json:
        n = import_json(Path(args.import_json))
        print(f"Imported {n} days into {db_path()}")
    if args.coverage or not args.import_json:
        print(json.dumps(coverage_report(), indent=2))
