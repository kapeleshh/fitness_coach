"""Deterministic synthetic health data for tests and golden capture.

Never put real health data in tests or goldens — this generator produces
plausible fake values with a fixed seed so goldens are reproducible.

All numeric fields are intentionally non-zero so that the legacy JSON path
and the SQLite path (which maps impossible zeros to NULL) produce identical
API responses for this dataset.
"""

import random
from datetime import date, timedelta

FIXTURE_END_DATE = date(2026, 7, 7)
FIXTURE_DAYS = 90

_INSIGHTS = [
    "NEGATIVE_LONG_AWAKE_TIME",
    "POSITIVE_DEEP_SLEEP",
    "NEGATIVE_LATE_BEDTIME",
    "POSITIVE_CONSISTENT_SCHEDULE",
]
_FEEDBACK = [
    "GOOD_CONTINUITY",
    "FAIR_QUALITY",
    "GOOD_QUALITY",
    "POOR_CONTINUITY",
]
_HRV_STATUS = ["BALANCED", "BALANCED", "BALANCED", "LOW", "UNBALANCED"]


def generate_days(n: int = FIXTURE_DAYS, end: date = FIXTURE_END_DATE) -> list[dict]:
    """Return n synthetic daily records, newest first (matching the real file)."""
    rng = random.Random(42)
    records = []
    for i in range(n):
        day = end - timedelta(days=i)
        date_str = day.strftime("%Y-%m-%d")
        bb_start = rng.randint(40, 95)
        bb_end = rng.randint(5, 39)
        records.append({
            "date": date_str,
            "sleep_score": rng.randint(55, 92),
            "deep_sleep_minutes": rng.randint(40, 110),
            "light_sleep_minutes": rng.randint(180, 280),
            "rem_sleep_minutes": rng.randint(60, 130),
            "awake_minutes": rng.randint(10, 60),
            "sleep_start_time": f"{(day - timedelta(days=1)).strftime('%Y-%m-%d')}T22:{rng.randint(10, 59):02d}:00.0",
            "sleep_end_time": f"{date_str}T06:{rng.randint(10, 59):02d}:00.0",
            "avg_sleep_stress": round(rng.uniform(14.0, 34.0), 1),
            "sleep_insight": rng.choice(_INSIGHTS),
            "sleep_feedback": rng.choice(_FEEDBACK),
            "resting_hr": rng.randint(46, 60),
            "min_hr": rng.randint(40, 45),
            "max_hr": rng.randint(120, 172),
            "hrv": round(rng.uniform(42.0, 78.0), 1),
            "hrv_status": rng.choice(_HRV_STATUS),
            "body_battery_start": bb_start,
            "body_battery_end": bb_end,
            "body_battery_high": min(100, bb_start + rng.randint(0, 5)),
            "body_battery_low": max(1, bb_end - rng.randint(0, 4)),
            "body_battery_charged": rng.randint(30, 80),
            "body_battery_drained": rng.randint(40, 90),
            "avg_stress": rng.randint(20, 52),
            "max_stress": rng.randint(70, 99),
            "stress_rest_minutes": rng.randint(300, 700),
            "stress_low_minutes": rng.randint(150, 400),
            "stress_medium_minutes": rng.randint(30, 150),
            "stress_high_minutes": rng.randint(5, 60),
            "steps": rng.randint(3000, 16500),
            "distance_meters": round(rng.uniform(2200.0, 13000.0), 2),
            "active_calories": rng.randint(200, 950),
            "total_calories": rng.randint(1900, 3100),
            "floors_climbed": rng.randint(4, 26),
            "active_minutes": rng.randint(20, 130),
            "avg_respiration": round(rng.uniform(13.0, 17.0), 1),
            "lowest_respiration": round(rng.uniform(10.0, 13.0), 1),
            "highest_respiration": round(rng.uniform(17.0, 22.0), 1),
        })
    return records
