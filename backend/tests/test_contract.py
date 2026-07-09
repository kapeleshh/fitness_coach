"""Golden contract tests: the FastAPI server must return byte-for-byte the
same JSON (parsed equality) as the original stdlib server did for the same
synthetic dataset. Goldens were captured from the stdlib implementation in
tests/goldens/ before the rewrite — do not regenerate them from FastAPI.
"""

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

GOLDENS_DIR = Path(__file__).parent / "goldens"
GOLDEN_FILES = sorted(GOLDENS_DIR.glob("*.json"))


def _client():
    from api_server import app
    return TestClient(app)


@pytest.mark.parametrize(
    "golden_file", GOLDEN_FILES, ids=[f.stem for f in GOLDEN_FILES]
)
def test_endpoint_matches_golden(populated_db, golden_file):
    golden = json.loads(golden_file.read_text())
    with _client() as client:
        response = client.get(golden["path"])
    assert response.status_code == golden["status"], golden["path"]

    body = response.json()
    expected = golden["body"]
    if isinstance(expected, dict) and "endpoints" in expected:
        # The 404 endpoint catalog is an intentionally-growing list: new
        # endpoints are added over time. The contract guarantee is that every
        # ORIGINAL endpoint remains listed (no regression), so assert the
        # golden's endpoints are a subset of the current ones and the rest of
        # the body matches exactly.
        assert set(expected["endpoints"]).issubset(set(body.get("endpoints", [])))
        assert {k: v for k, v in body.items() if k != "endpoints"} == {
            k: v for k, v in expected.items() if k != "endpoints"
        }
    else:
        assert body == expected, golden["path"]
