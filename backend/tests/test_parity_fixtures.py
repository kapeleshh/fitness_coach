"""The committed Dart parity fixtures must match what the Python engines
produce now. Regenerate them with: uv run python -m tests.parity_fixtures"""

import json

from tests import parity_fixtures


def test_fixtures_are_current(temp_db, monkeypatch):
    for name in parity_fixtures.ENGINE_ENV:
        monkeypatch.delenv(name, raising=False)
    built = parity_fixtures.build_fixtures(parity_fixtures.load_dataset())

    committed = sorted(p.stem for p in parity_fixtures.FIXTURE_DIR.glob("*.json"))
    assert committed == sorted(built)
    for name, value in built.items():
        path = parity_fixtures.FIXTURE_DIR / f"{name}.json"
        expected = json.loads(path.read_text(encoding="utf-8"))
        assert json.loads(parity_fixtures.dumps(value)) == expected, (
            f"{path.name} is stale: run `uv run python -m tests.parity_fixtures`"
        )
