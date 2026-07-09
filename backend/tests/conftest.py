import pytest

import db
from tests.synthetic import generate_days


@pytest.fixture()
def temp_db(tmp_path, monkeypatch):
    """Point the whole backend at an isolated, empty SQLite file."""
    db_file = tmp_path / "test.db"
    monkeypatch.setenv("FITNESS_COACH_DB", str(db_file))
    # Never let tests start the background sync scheduler.
    monkeypatch.setenv("GARMIN_AUTO_SYNC", "0")
    # Never let the server's empty-DB migration ingest the developer's real
    # parsed_health_data.json into a test database.
    monkeypatch.setenv("FITNESS_COACH_IMPORT_LEGACY", "0")
    db.init_db()
    return db_file


@pytest.fixture()
def populated_db(temp_db):
    """temp_db pre-loaded with the deterministic 90-day synthetic dataset."""
    db.upsert_days(generate_days())
    return temp_db
