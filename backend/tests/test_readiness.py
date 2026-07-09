"""Tests for the readiness engine.

Assertions are mostly behavioral/relative (band ordering, flags, cold-start
tiering, guards) rather than pinned to exact scores, so they stay valid if the
constants are retuned — while still locking the important guarantees.
"""

from datetime import date, timedelta

from fastapi.testclient import TestClient

import api_server
import readiness_engine as re

END = date(2026, 7, 7)


def _series(n=60, hrv_base=55.0, jitter=True, rhr=50, sleep=82, bb=72,
            status="BALANCED", deep=90, light=240, rem=90):
    """n synthetic days, newest first. Jitter gives a realistic ln-HRV SD."""
    out = []
    for i in range(n):
        dd = END - timedelta(days=i)
        h = hrv_base + (((i % 7) - 3) * 2.0 if jitter else 0.0)
        out.append({
            "date": dd.isoformat(), "hrv": h, "hrv_status": status,
            "resting_hr": rhr, "sleep_score": sleep, "body_battery_start": bb,
            "deep_sleep_minutes": deep, "light_sleep_minutes": light,
            "rem_sleep_minutes": rem,
        })
    return out


def _set_recent(rows, k, **fields):
    for i in range(k):
        rows[i].update(fields)
    return rows


class TestScoring:
    def test_normal_full_baseline_is_green_high_confidence(self):
        r = re.readiness_today(_series(60))
        assert r["baseline_status"] == "full"
        assert r["band"] == "green"
        assert r["score"] >= 70
        assert r["confidence"] == "high"
        assert r["components"]["hrv"]["source"] == "baseline"

    def test_suppressed_hrv_scores_lower_than_normal(self):
        normal = re.readiness_today(_series(60))["score"]
        rows = _set_recent(_series(60), 5, hrv=38.0)  # recent week well below baseline
        supp = re.readiness_today(rows)
        assert supp["score"] < normal
        assert supp["band"] in ("amber", "red")
        assert supp["components"]["hrv"]["z"] < 0

    def test_illness_override_forces_red_with_flag(self):
        rows = _set_recent(_series(60), 3, hrv=34.0, resting_hr=60)
        r = re.readiness_today(rows)
        assert "illness_watch" in r["flags"]
        assert r["band"] == "red"
        assert r["score"] <= 35

    def test_cold_start_uses_status_fallback(self):
        r = re.readiness_today(_series(10))  # < HRV_TRUST_MIN valid nights
        assert r["baseline_status"] == "cold_start"
        assert r["components"]["hrv"]["source"] == "status"
        assert r["components"]["hrv"]["z"] is None
        assert r["confidence"] in ("low", "medium")  # never "high" without baseline
        assert r["score"] is not None
        assert r["days_to_full"] == 18

    def test_stale_hrv_when_recent_days_missing(self):
        rows = _series(60)
        _set_recent(rows, 5, hrv=None, hrv_status="BALANCED")  # only 2 of last 7 present
        r = re.readiness_today(rows)
        assert "stale_hrv" in r["flags"]
        assert r["components"]["hrv"]["source"] == "status"

    def test_short_sleep_guard_caps_sleep_axis(self):
        rows = _series(60, sleep=92)
        _set_recent(rows, 1, deep_sleep_minutes=40, light_sleep_minutes=120,
                    rem_sleep_minutes=60)  # TST=220 < 300
        r = re.readiness_today(rows)
        assert r["components"]["sleep_duration"]["guard_applied"] is True
        assert r["components"]["sleep_score"]["sub"] <= 0.5

    def test_missing_hrv_and_status_drops_component(self):
        rows = _series(60)
        _set_recent(rows, 8, hrv=None, hrv_status=None)
        r = re.readiness_today(rows)
        # HRV gone today, but body battery + resting HR + sleep still score it
        assert r["components"]["hrv"]["available"] is False
        assert r["score"] is not None
        assert r["axes"]["autonomic"]["present"] is True

    def test_insufficient_data_returns_unknown(self):
        rows = [{"date": "2026-07-07", "hrv": None, "hrv_status": None,
                 "resting_hr": None, "sleep_score": None,
                 "body_battery_start": None}]
        r = re.readiness_today(rows)
        assert r["score"] is None
        assert r["band"] == "unknown"
        assert r["confidence"] == "none"

    def test_briefing_names_the_score_and_is_deterministic(self):
        rows = _series(60)
        a = re.readiness_today(rows)["briefing"]
        b = re.readiness_today(rows)["briefing"]
        assert a == b  # deterministic
        assert "readiness" in a.lower()
        assert "/100" in a

    def test_history_is_point_in_time(self):
        rows = _series(60)
        hist = re.readiness_history(rows, days=5)
        assert len(hist["series"]) == 5
        # newest first; each entry has a score and band
        assert all("score" in s and "band" in s for s in hist["series"])


class TestVerificationFixes:
    """Locks the behaviors changed after the adversarial review."""

    def test_warming_with_unknown_status_fades_from_anchor(self):
        # 14 valid nights, Garmin status still UNKNOWN (its own warmup): the
        # personal baseline must NOT snap to full trust — w=0 => anchored.
        r = re.readiness_today(_series(14, status="UNKNOWN"))
        assert r["baseline_status"] == "warming"
        assert r["components"]["hrv"]["source"] == "blend"
        assert abs(r["components"]["hrv"]["sub"] - re.NEUTRAL_ANCHOR) < 0.06

    def test_illness_override_does_not_fire_while_warming(self):
        rows = _set_recent(_series(20, status="UNKNOWN"), 3, hrv=34.0, resting_hr=62)
        r = re.readiness_today(rows)
        assert r["baseline_status"] == "warming"
        assert "illness_watch" not in r["flags"]   # needs a full baseline
        assert "hrv_suppressed" not in r["flags"]

    def test_body_battery_capped_under_dual_autonomic_suppression(self):
        rows = _series(60, bb=72)
        # moderate HRV drop + elevated RHR (below illness threshold) + high BB
        _set_recent(rows, 7, hrv=50.0, resting_hr=53)  # whole 7-day HRV window
        _set_recent(rows, 1, hrv=50.0, resting_hr=53, body_battery_start=95)
        r = re.readiness_today(rows)
        assert "body_battery_capped" in r["flags"]
        # specificity: a normal-autonomic day with the same high BB is NOT capped
        normal = re.readiness_today(
            _set_recent(_series(60, bb=72), 1, body_battery_start=95)
        )
        assert "body_battery_capped" not in normal["flags"]

    def test_severe_isolated_hrv_suppression_forces_red(self):
        rows = _series(60, bb=72)
        # big HRV crash across the whole week, normal resting HR, excellent BB + sleep
        _set_recent(rows, 7, hrv=35.0)
        _set_recent(rows, 1, hrv=35.0, body_battery_start=95, sleep_score=96)
        r = re.readiness_today(rows)
        assert "hrv_suppressed" in r["flags"]
        assert r["band"] == "red"

    def test_malformed_date_row_does_not_crash(self):
        rows = _series(30)
        rows.append({"date": "not-a-date", "hrv": 50, "hrv_status": "BALANCED",
                     "resting_hr": 50, "sleep_score": 80, "body_battery_start": 70})
        r = re.readiness_today(rows)  # must skip the bad row, not raise
        assert r["score"] is not None

    def test_cold_start_clears_baseline_metadata(self):
        r = re.readiness_today(_series(10))
        c = r["components"]["hrv"]
        assert c["z"] is None
        assert c["pct_dev"] is None
        assert c["cv_7"] is None


class TestSharedCurve:
    def test_deadband_and_anchors(self):
        assert re._shared_curve(0.0) == 0.85     # at baseline
        assert re._shared_curve(0.4) == 0.85     # inside SWC deadband
        assert re._shared_curve(2.0) == 1.0      # well above
        assert re._shared_curve(-3.5) == 0.0     # collapsed
        # monotonic non-decreasing in x
        xs = [-4, -2, -1, -0.5, 0, 0.5, 1, 2]
        ys = [re._shared_curve(x) for x in xs]
        assert ys == sorted(ys)


class TestEndpoints:
    def test_readiness_today(self, populated_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/readiness")
        assert res.status_code == 200
        body = res.json()
        assert set(["date", "score", "band", "confidence", "briefing"]).issubset(body)
        assert body["band"] in ("green", "amber", "red", "unknown")

    def test_readiness_history(self, populated_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/readiness/history?days=10")
        assert res.status_code == 200
        assert len(res.json()["series"]) <= 10

    def test_readiness_for_date(self, populated_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/readiness/2026-07-07")
        assert res.status_code == 200
        assert res.json()["date"] == "2026-07-07"

    def test_readiness_bad_date(self, temp_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/readiness/not-a-date")
        assert res.status_code == 400

    def test_readiness_empty_db_is_unknown(self, temp_db):
        with TestClient(api_server.app) as client:
            res = client.get("/api/readiness")
        assert res.status_code == 200
        assert res.json()["band"] == "unknown"

    def test_readiness_in_endpoint_list(self, temp_db):
        with TestClient(api_server.app) as client:
            eps = client.get("/api/nope").json()["endpoints"]
        assert "GET  /api/readiness" in eps
