"""Insights engine — the numbers behind the app's Insights, Patterns and
Predictions tabs. Pure stdlib, NULL-aware, deterministic.

These used to be computed on the device from 0-filled data, where a missing
reading counted as 0: a night with no sleep data read as "Poor Sleep
Quality", and predictions carried a hard-coded confidence. Here a missing
metric is None — rules that need it are skipped, averages ignore it — and
every reported number is measured:

  weekly_summary()         averages for this week and last (calendar weeks
                           ending at the latest day), the change and a trend
  insights()               rule-based callouts for the latest day
  correlation()            Pearson r for any metric pair, optionally lagged
  discover_correlations()  the curated pairs the Patterns tab lists
  outlook()                tomorrow's morning body battery from a simple
                           heuristic, plus that heuristic's error measured by
                           replaying it over past days (a backtest)

Correlation pairing and strength labels come from analytics_engine, so the
backend has one implementation of each.
"""

from datetime import date, timedelta

import analytics_engine
import db

WEEK_DAYS = 7
MIN_DAYS_PER_WEEK = 3           # values needed in each week to compare them

# Display key -> record field. Trends for these compare this week with last.
WEEK_METRICS = {
    "sleep": "sleep_score",
    "hrv": "hrv",
    "stress": "avg_stress",
    "steps": "steps",
    "body_battery": "body_battery_start",
    "resting_hr": "resting_hr",
}
LOWER_IS_BETTER = {"stress", "resting_hr"}
# A week-over-week change smaller than this is "stable" (in the metric's units).
TREND_THRESHOLDS = {
    "sleep": 3, "hrv": 3, "stress": 3, "steps": 500, "body_battery": 5, "resting_hr": 2,
}

# ---- Insight rules (latest day) ----
SLEEP_POOR = 50
SLEEP_EXCELLENT = 80
HRV_DROP_MS = 10                # below the week's average by more than this
BODY_BATTERY_LOW = 30
BODY_BATTERY_HIGH = 80
STRESS_ELEVATED = 50
STEP_GOAL = 10000
SLEEP_TREND_UP = 5              # week-over-week sleep gain worth calling out

# ---- Correlations ----
CORRELATION_METRICS = frozenset(
    name for name, sql_type in db.DAILY_FIELDS.items() if sql_type in ("INTEGER", "REAL")
)
MIN_PAIRS = 5
MAX_LAG_DAYS = 7
SAME_DAY_PAIRS = [
    ("sleep_score", "body_battery_start", "Sleep → Body Battery"),
    ("avg_stress", "hrv", "Stress ↔ HRV"),
    ("steps", "total_calories", "Steps → Calories"),
    ("deep_sleep_minutes", "hrv", "Deep Sleep → HRV"),
]
NEXT_DAY_PAIRS = [
    ("sleep_score", "body_battery_start", "Last Night's Sleep → Today's Energy"),
    ("avg_stress", "sleep_score", "Yesterday's Stress → Tonight's Sleep"),
]

# ---- Outlook: tomorrow's morning body battery ----
OUTLOOK_WEEK_WEIGHT = 0.6       # weight of this week's average morning battery
OUTLOOK_EVENING_WEIGHT = 0.4    # weight of today's end-of-day battery
OUTLOOK_HIGH_STRESS = 50        # avg stress above this...
OUTLOOK_STRESS_FACTOR = 0.9     # ...scales the prediction down
INTENSITY_HIGH = 70
INTENSITY_MODERATE = 50
BACKTEST_DAYS = 60
BACKTEST_MIN_PAIRS = 10


def _mean(values):
    return sum(values) / len(values) if values else None


def _round(x, digits=1):
    return round(x, digits) if x is not None else None


def _dated(records):
    """{date: record} for records with a parseable date, and the latest date."""
    by_date = {}
    for r in records:
        try:
            by_date[date.fromisoformat(r["date"])] = r
        except (KeyError, TypeError, ValueError):
            continue
    return by_date, (max(by_date) if by_date else None)


def _values(by_date, end, days, field):
    """Present values of `field` over the `days` calendar days ending at `end`."""
    out = []
    for i in range(days):
        row = by_date.get(end - timedelta(days=i))
        if row is not None and row.get(field) is not None:
            out.append(row[field])
    return out


def _baseline(by_date, end, field):
    """This week's average of `field`, if there are enough readings to compare
    a single day against it (MIN_DAYS_PER_WEEK); otherwise None."""
    values = _values(by_date, end, WEEK_DAYS, field)
    return _mean(values) if len(values) >= MIN_DAYS_PER_WEEK else None


# ============= WEEKLY SUMMARY =============

def _trend(key, change):
    if change is None:
        return "unknown"
    threshold = TREND_THRESHOLDS[key]
    if abs(change) < threshold:
        return "stable"
    better = change < 0 if key in LOWER_IS_BETTER else change > 0
    return "improving" if better else "declining"


def weekly_summary(records):
    """This week's and last week's averages, the change and a trend per metric.
    A change needs MIN_DAYS_PER_WEEK values in both weeks; otherwise None."""
    by_date, latest = _dated(records)
    this_week, last_week, change, trends = {}, {}, {}, {}
    for key, field in WEEK_METRICS.items():
        now = _values(by_date, latest, WEEK_DAYS, field) if latest else []
        before = (_values(by_date, latest - timedelta(days=WEEK_DAYS), WEEK_DAYS, field)
                  if latest else [])
        this_week[key] = _round(_mean(now))
        last_week[key] = _round(_mean(before))
        comparable = len(now) >= MIN_DAYS_PER_WEEK and len(before) >= MIN_DAYS_PER_WEEK
        change[key] = _round(_mean(now) - _mean(before)) if comparable else None
        trends[key] = _trend(key, change[key])
    return {
        "date": latest.isoformat() if latest else None,
        "this_week": this_week,
        "last_week": last_week,
        "change": change,
        "trends": trends,
    }


# ============= INSIGHTS =============

def _insight(kind, category, title, description, icon, metric, value, benchmark):
    return {
        "type": kind, "category": category, "title": title,
        "description": description, "icon": icon, "metric": metric,
        "value": value, "benchmark": benchmark,
    }


def insights(records, week=None):
    """Rule-based callouts for the latest day. A rule whose metric is missing
    is skipped. `benchmark` is always this week's average (the app labels it
    "Avg"), or None when the week has no data for it."""
    by_date, latest = _dated(records)
    if latest is None:
        return []
    t = by_date[latest]
    week = week or weekly_summary(records)
    avg = week["this_week"]
    out = []

    def bench(key):
        return round(avg[key]) if avg[key] is not None else None

    sleep = t.get("sleep_score")
    if sleep is not None and sleep < SLEEP_POOR:
        out.append(_insight(
            "warning", "Sleep", "Poor Sleep Quality",
            f"Your sleep score of {sleep} is below average. Consider going to bed earlier.",
            "😴", "sleep_score", sleep, bench("sleep")))
    elif sleep is not None and sleep > SLEEP_EXCELLENT:
        out.append(_insight(
            "positive", "Sleep", "Excellent Sleep!",
            f"Great sleep score of {sleep}. Your body is well-rested.",
            "🌟", "sleep_score", sleep, bench("sleep")))

    hrv = t.get("hrv")
    hrv_baseline = _baseline(by_date, latest, "hrv")
    if hrv is not None and hrv_baseline is not None and hrv < hrv_baseline - HRV_DROP_MS:
        out.append(_insight(
            "warning", "Recovery", "Lower HRV Today",
            f"HRV of {round(hrv)}ms is below your average. Consider lighter activity.",
            "❤️", "hrv", hrv, bench("hrv")))

    battery = t.get("body_battery_start")
    if battery is not None and battery < BODY_BATTERY_LOW:
        out.append(_insight(
            "warning", "Energy", "Low Energy Reserves",
            f"Starting the day with Body Battery at {battery}%. Prioritize rest.",
            "🔋", "body_battery_start", battery, bench("body_battery")))
    elif battery is not None and battery > BODY_BATTERY_HIGH:
        out.append(_insight(
            "positive", "Energy", "Fully Charged!",
            f"Body Battery at {battery}%. Great day for high-intensity activity!",
            "⚡", "body_battery_start", battery, bench("body_battery")))

    stress = t.get("avg_stress")
    if stress is not None and stress > STRESS_ELEVATED:
        out.append(_insight(
            "warning", "Stress", "Elevated Stress",
            f"Average stress of {stress} is higher than ideal. Try breathing exercises.",
            "😰", "avg_stress", stress, bench("stress")))

    steps = t.get("steps")
    if steps is not None and steps > STEP_GOAL:
        out.append(_insight(
            "positive", "Activity", "Step Goal Achieved!",
            f"You've walked {steps} steps today. Keep it up!",
            "🚶", "steps", steps, bench("steps")))

    sleep_change = week["change"]["sleep"]
    if sleep_change is not None and sleep_change > SLEEP_TREND_UP:
        out.append(_insight(
            "positive", "Trend", "Sleep Improving",
            f"Your sleep score is up {round(sleep_change)} points from last week!",
            "📈", "sleep_trend", sleep_change, None))
    return out


# ============= CORRELATIONS =============

def correlation(records, x, y, lag=0):
    """Pearson r between `x` on day d and `y` on day d + `lag` (calendar days)."""
    xs, ys = analytics_engine.lagged_pairs(records, x, y, lag)
    r = analytics_engine.pearson_correlation(xs, ys) if len(xs) >= MIN_PAIRS else None
    if r is None:
        # Too few pairs, or a metric that never varied: nothing to report.
        return {"correlation": None, "strength": "insufficient_data", "sample_size": len(xs)}
    return {
        "correlation": round(r, 3),
        "strength": analytics_engine.categorize_strength(r),
        "sample_size": len(xs),
        "metric1_avg": _round(_mean(xs)),
        "metric2_avg": _round(_mean(ys)),
    }


def discover_correlations(records):
    """The curated same-day and next-day pairs with at least a weak
    relationship, strongest first."""
    found = []
    for lag, pairs in ((0, SAME_DAY_PAIRS), (1, NEXT_DAY_PAIRS)):
        for x, y, label in pairs:
            result = correlation(records, x, y, lag)
            if result["strength"] in ("insufficient_data", "minimal"):
                continue
            found.append({"metric1": x, "metric2": y, "label": label,
                          "lagged": lag > 0, **result})
    found.sort(key=lambda c: abs(c["correlation"]), reverse=True)
    return found


# ============= OUTLOOK =============

def _predict(by_date, day):
    """Tomorrow's morning body battery from data up to `day`, or None when
    the inputs are missing."""
    week = _mean(_values(by_date, day, WEEK_DAYS, "body_battery_start"))
    row = by_date.get(day) or {}
    evening = row.get("body_battery_end")
    if week is None or evening is None:
        return None
    predicted = OUTLOOK_WEEK_WEIGHT * week + OUTLOOK_EVENING_WEIGHT * evening
    stress = row.get("avg_stress")
    if stress is not None and stress > OUTLOOK_HIGH_STRESS:
        predicted *= OUTLOOK_STRESS_FACTOR
    return predicted


def _backtest(by_date, latest):
    """Mean absolute error of _predict over the last BACKTEST_DAYS days:
    each day's prediction against the next morning's actual battery."""
    errors = []
    for i in range(1, BACKTEST_DAYS + 1):
        day = latest - timedelta(days=i)
        predicted = _predict(by_date, day)
        actual = (by_date.get(day + timedelta(days=1)) or {}).get("body_battery_start")
        if predicted is not None and actual is not None:
            errors.append(abs(predicted - actual))
    if len(errors) < BACKTEST_MIN_PAIRS:
        return None
    return {"mean_abs_error": round(_mean(errors), 1), "days": len(errors)}


def _impact(value, good):
    if value is None:
        return "unknown"
    return "positive" if good(value) else "negative"


def outlook(records, week=None):
    """Tomorrow's predicted morning body battery, a training intensity and the
    factors behind it. `available` is False when today's inputs are missing."""
    by_date, latest = _dated(records)
    week = week or weekly_summary(records)
    t = by_date.get(latest) or {}
    today = {k: t.get(k) for k in ("sleep_score", "body_battery_end", "avg_stress", "hrv")}
    base = {"date": week["date"], "today": today,
            "weekly": week["this_week"], "trends": week["trends"]}

    predicted = _predict(by_date, latest) if latest else None
    if predicted is None:
        return {**base, "available": False,
                "message": "Need a week of body battery data, including today's, for a prediction."}

    if predicted > INTENSITY_HIGH:
        intensity = "high"
        recommendation = "Great recovery predicted. Good day for intense workout!"
    elif predicted > INTENSITY_MODERATE:
        intensity = "moderate"
        recommendation = "Moderate energy expected. Balanced workout recommended."
    else:
        intensity = "low"
        recommendation = "Lower energy predicted. Consider light activity or rest."

    hrv_baseline = _baseline(by_date, latest, "hrv")
    hrv = t.get("hrv")
    return {
        **base,
        "available": True,
        "predicted_body_battery": round(predicted),
        "backtest": _backtest(by_date, latest),
        "recommended_intensity": intensity,
        "recommendation": recommendation,
        "factors": [
            {"name": "Recent Sleep", "value": t.get("sleep_score"),
             "impact": _impact(t.get("sleep_score"), lambda v: v > 70)},
            {"name": "Current Stress", "value": t.get("avg_stress"),
             "impact": _impact(t.get("avg_stress"), lambda v: v < 40)},
            {"name": "HRV Status", "value": hrv,
             "impact": ("unknown" if hrv is None or hrv_baseline is None
                        else "positive" if hrv > hrv_baseline else "neutral")},
        ],
    }
