"""Insights engine and the NULL-aware analytics engine: weekly summaries,
rule-based insights, correlations, the body-battery outlook with its
backtest, and the endpoints. Synthetic data only."""

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

import analytics_engine
import api_server
import db
import insights_engine as ie

END = date(2026, 7, 7)


def _day(offset, **fields):
    """A record `offset` days before END (newest = 0). Unset metrics are None,
    as db.get_all_days() returns them."""
    return {"date": (END - timedelta(days=offset)).isoformat(), **fields}


def _days(n, **fields):
    return [_day(i, **fields) for i in range(n)]


class TestAnalyticsEngineNullAware:
    def test_lagged_pairs_use_calendar_days_and_keep_real_zeros(self):
        records = [
            _day(0, active_minutes=0, deep_sleep_minutes=95),
            _day(1, active_minutes=40, deep_sleep_minutes=80),
            # no record for 07-05
            _day(3, active_minutes=10, deep_sleep_minutes=70),
            _day(4, active_minutes=25, deep_sleep_minutes=60),
        ]
        xs, ys = analytics_engine.lagged_pairs(records, "active_minutes", "deep_sleep_minutes", 1)
        # 07-06 -> 07-07 and 07-03 -> 07-04. 07-04's next day has no record;
        # pairing by row position would have matched it with 07-06 instead.
        assert (xs, ys) == ([40.0, 25.0], [95.0, 70.0])
        same_day, _ = analytics_engine.lagged_pairs(records, "active_minutes", "deep_sleep_minutes", 0)
        assert 0.0 in same_day                     # a rest day is a real zero

    def test_too_little_data_is_none_not_zero(self):
        assert analytics_engine.pearson_correlation([1, 2], [1, 2]) is None
        assert analytics_engine.pearson_correlation([5, 5, 5, 5], [1, 2, 3, 4]) is None
        records = _days(10, sleep_score=80, hrv=None)
        matrix = analytics_engine.calculate_correlation_matrix(records)["matrix"]
        assert matrix["sleep_score"]["hrv"] is None

    def test_missing_values_are_never_anomalies(self):
        records = [_day(i, hrv=50.0 + (i % 5)) for i in range(20)]
        records[3]["hrv"] = None
        found = analytics_engine.detect_anomalies(records)["all_anomalies"]
        assert all(a["date"] != records[3]["date"] for a in found)

    def test_trends_use_calendar_windows(self):
        # 14 records spread over 28 days: only 4 fall in the last 7 calendar days.
        records = [_day(i * 2, sleep_score=90 if i < 4 else 60) for i in range(14)]
        trend = analytics_engine.analyze_trends(records)["trends"]["sleep_score"]
        assert trend["recent_avg"] == 90.0 and trend["previous_avg"] == 60.0

    def test_summary_averages_ignore_missing_and_report_null(self, temp_db):
        db.upsert_days([
            {"date": "2026-07-07", "sleep_score": 80, "steps": 0},
            {"date": "2026-07-06", "sleep_score": 0, "steps": 9000},  # sleep missing
        ])
        with TestClient(api_server.app) as client:
            averages = client.get("/api/summary").json()["averages"]
        assert averages["sleep_score"] == 80.0       # the missing night isn't a 0
        assert averages["steps"] == 4500.0           # a real 0-step day counts
        assert averages["hrv"] is None               # never measured


class TestWeeklySummary:
    def test_averages_change_and_trends(self):
        records = ([_day(i, sleep_score=82, avg_stress=30, steps=9000) for i in range(7)]
                   + [_day(i, sleep_score=75, avg_stress=36, steps=8800) for i in range(7, 14)])
        week = ie.weekly_summary(records)
        assert week["date"] == "2026-07-07"
        assert week["this_week"]["sleep"] == 82.0 and week["last_week"]["sleep"] == 75.0
        assert week["change"]["sleep"] == 7.0 and week["trends"]["sleep"] == "improving"
        assert week["trends"]["stress"] == "improving"   # lower is better
        assert week["trends"]["steps"] == "stable"       # +200 steps is under 500
        assert week["trends"]["hrv"] == "unknown"        # never measured

    def test_change_needs_enough_days_in_both_weeks(self):
        records = _days(7, sleep_score=80) + [_day(8, sleep_score=60), _day(9, sleep_score=60)]
        week = ie.weekly_summary(records)
        assert week["last_week"]["sleep"] == 60.0
        assert week["change"]["sleep"] is None and week["trends"]["sleep"] == "unknown"

    def test_empty(self):
        week = ie.weekly_summary([])
        assert week["date"] is None and week["this_week"]["sleep"] is None


class TestInsights:
    def test_missing_metrics_trigger_nothing(self):
        # The old on-device rules read missing as 0: "Poor Sleep Quality" and
        # "Low Energy Reserves" for a day with no sleep or battery data.
        records = [_day(0, steps=4000)] + _days(13, sleep_score=75, body_battery_start=60)[1:]
        titles = [i["title"] for i in ie.insights(records)]
        assert "Poor Sleep Quality" not in titles and "Low Energy Reserves" not in titles

    def test_rules_and_benchmarks(self):
        records = ([_day(0, sleep_score=45, hrv=40.0, body_battery_start=90,
                         avg_stress=55, steps=12000)]
                   + [_day(i, sleep_score=80, hrv=60.0, body_battery_start=70,
                           avg_stress=30, steps=8000) for i in range(1, 7)])
        by_title = {i["title"]: i for i in ie.insights(records)}
        assert set(by_title) == {"Poor Sleep Quality", "Lower HRV Today", "Fully Charged!",
                                 "Elevated Stress", "Step Goal Achieved!"}
        # Benchmarks are this week's averages (the app labels them "Avg").
        assert by_title["Poor Sleep Quality"]["benchmark"] == round((45 + 6 * 80) / 7)
        assert by_title["Step Goal Achieved!"]["benchmark"] == round((12000 + 6 * 8000) / 7)

    def test_sleep_trend_callout_has_no_fake_average(self):
        records = _days(7, sleep_score=70) + [_day(i, sleep_score=60) for i in range(7, 14)]
        (trend,) = [i for i in ie.insights(records) if i["metric"] == "sleep_trend"]
        assert trend["value"] == 10.0 and trend["benchmark"] is None


class TestCorrelations:
    def test_perfect_and_lagged(self):
        records = [_day(i, sleep_score=60 + i, hrv=30.0 + 2 * i) for i in range(10)]
        same = ie.correlation(records, "sleep_score", "hrv")
        assert same["correlation"] == 1.0 and same["strength"] == "strong"
        assert same["sample_size"] == 10 and same["metric1_avg"] == 64.5
        lagged = ie.correlation(records, "sleep_score", "hrv", lag=1)
        assert lagged["sample_size"] == 9

    def test_insufficient_or_constant(self):
        assert ie.correlation(_days(4, sleep_score=1, hrv=2.0), "sleep_score", "hrv") == {
            "correlation": None, "strength": "insufficient_data", "sample_size": 4}
        flat = ie.correlation(_days(10, sleep_score=80, hrv=50.0), "sleep_score", "hrv")
        assert flat["correlation"] is None and flat["strength"] == "insufficient_data"

    def test_discover_filters_and_sorts(self):
        records = [_day(i, sleep_score=60 + i, body_battery_start=40 + 3 * i,
                        avg_stress=30 + (i * 7) % 5, hrv=50.0 + (i * 3) % 4) for i in range(20)]
        found = ie.discover_correlations(records)
        strengths = [abs(c["correlation"]) for c in found]
        assert strengths == sorted(strengths, reverse=True)
        assert all(c["strength"] not in ("minimal", "insufficient_data") for c in found)
        assert {c["label"] for c in found} >= {"Sleep → Body Battery"}
        assert any(c["lagged"] for c in found)


class TestOutlook:
    def test_prediction_hand_computed(self):
        records = [_day(0, body_battery_start=60, body_battery_end=30, avg_stress=20,
                        sleep_score=75, hrv=55.0)] + _days(8, body_battery_start=60)[1:]
        out = ie.outlook(records)
        # 0.6 x 60 (this week's mornings) + 0.4 x 30 (this evening) = 48
        assert out["available"] and out["predicted_body_battery"] == 48
        assert out["recommended_intensity"] == "low"
        impacts = {f["name"]: f["impact"] for f in out["factors"]}
        assert impacts == {"Recent Sleep": "positive", "Current Stress": "positive",
                           "HRV Status": "unknown"}   # no week of HRV to compare with

    def test_high_stress_scales_down(self):
        records = [_day(0, body_battery_start=60, body_battery_end=30, avg_stress=60)]
        assert ie.outlook(records)["predicted_body_battery"] == round(48 * 0.9)

    def test_backtest_is_measured(self):
        # Every day predicts 0.6 x 60 + 0.4 x 30 = 48 for a next morning of 60.
        records = _days(20, body_battery_start=60, body_battery_end=30, avg_stress=20)
        assert ie.outlook(records)["backtest"] == {"mean_abs_error": 12.0, "days": 19}
        short = _days(5, body_battery_start=60, body_battery_end=30)
        assert ie.outlook(short)["backtest"] is None    # under BACKTEST_MIN_PAIRS

    def test_unavailable_without_tonights_battery(self):
        records = [_day(0, body_battery_start=60)] + _days(8, body_battery_start=60)[1:]
        out = ie.outlook(records)
        assert out["available"] is False and "message" in out
        assert "predicted_body_battery" not in out


class TestEndpoints:
    def _client(self):
        return TestClient(api_server.app)

    def test_insights(self, populated_db):
        with self._client() as client:
            body = client.get("/api/insights").json()
        assert body["date"] == "2026-07-07"
        assert body["readiness"]["score"] is not None
        assert set(body["today"]) == {"sleep_score", "hrv", "avg_stress"}
        assert set(body["weekly"]) == {"date", "this_week", "last_week", "change", "trends"}
        assert isinstance(body["insights"], list)

    def test_correlations_and_pair(self, populated_db):
        with self._client() as client:
            listed = client.get("/api/correlations").json()
            pair = client.get("/api/correlations/pair",
                              params={"x": "sleep_score", "y": "hrv", "lag": 1}).json()
        assert listed["days"] == 90
        assert (pair["metric1"], pair["metric2"], pair["lag_days"]) == ("sleep_score", "hrv", 1)
        assert pair["sample_size"] == 89

    @pytest.mark.parametrize("params", [
        {"x": "sleep_score"},                                # missing y
        {"x": "sleep_score", "y": "date"},                   # not a numeric metric
        {"x": "sleep_score", "y": "hrv", "lag": 8},          # lag out of range
    ])
    def test_pair_validation(self, temp_db, params):
        with self._client() as client:
            res = client.get("/api/correlations/pair", params=params)
        assert res.status_code == 400 and "error" in res.json()

    def test_outlook(self, populated_db):
        with self._client() as client:
            body = client.get("/api/outlook").json()
        assert body["available"] is True
        assert 0 <= body["predicted_body_battery"] <= 100
        assert body["backtest"]["days"] >= ie.BACKTEST_MIN_PAIRS

    def test_empty_database(self, temp_db):
        with self._client() as client:
            body = client.get("/api/insights").json()
            outlook = client.get("/api/outlook").json()
            listed = client.get("/api/correlations").json()
        assert body["date"] is None and body["insights"] == []
        assert body["readiness"]["band"] == "unknown"
        assert outlook["available"] is False
        assert listed == {"days": 0, "correlations": []}

    def test_endpoints_listed(self, temp_db):
        for prefix in ("GET  /api/insights", "GET  /api/correlations",
                       "GET  /api/correlations/pair", "GET  /api/outlook"):
            assert any(e.startswith(prefix) for e in api_server.ENDPOINT_LIST)
