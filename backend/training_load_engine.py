"""Training load engine — per-session load and daily fitness/fatigue/form.
Pure stdlib, NULL-aware, deterministic.

Session load is one number per canonical activity (an activities.py dedup
group), taken from the best signal anywhere in the group, in this order:

  1. garmin_load        Garmin (Firstbeat, EPOC-based) activity training load
  2. trimp              Banister TRIMP from average HR: minutes x HR-reserve
                        fraction, weighted exponentially toward high intensity
  3. relative_effort    Strava Relative Effort (HR-zone based)
  4. duration_estimate  minutes x a per-sport rate, when there is no HR at all

All four sit on roughly the same scale (~100 for a hard hour) — close enough
to sum, not identical — so every session records its method, and each day
reports how much of the recent load was measured rather than estimated.

Daily state (Banister impulse-response model, Coggan Performance Manager):

  ctl ("fitness")   42-day exponentially weighted load
  atl ("fatigue")    7-day exponentially weighted load
  tsb ("form")      ctl - atl
  form_pct          tsb as % of ctl — scale-free, so robust to the
                    approximate load units above; drives form_band
  acwr              7:28-day EWMA acute:chronic ratio (Williams et al. 2017).
                    Its injury "sweet spot" is contested (Impellizzeri et al.
                    2020), so it only drives a neutral "load_spike" flag.

Every daily metric describes the state ENTERING the day — load through the
previous day — which is what a morning "how hard today?" decision needs and
matches the Performance Manager's form convention. `load` on a row is that
day's own load, which shows up in the next day's state.

A day with no activity is a rest day (load 0); the series starts at the first
recorded activity. Everything is point-in-time except two athlete parameters:
max HR (setting, else the highest plausible value observed in all history)
and, for sessions that predate all wellness data, resting HR taken from the
earliest readings.

References: Banister et al. 1975; Morton, Fitz-Clarke & Banister 1990;
Banister 1991 (TRIMP); Allen & Coggan 2010 (CTL/ATL/TSB); Williams et al.
2017 (EWMA ACWR); Impellizzeri et al. 2020 (ACWR critique).
"""

import bisect
import math
import os
import statistics
from collections import defaultdict
from datetime import date, timedelta

import activities
import db

# ---- Fitness / fatigue (exponential decay, alpha = 1 - e^(-1/tau)) ----
CTL_TIME_CONSTANT = 42          # days
ATL_TIME_CONSTANT = 7           # days

# ---- Acute:chronic ratio (EWMA, alpha = 2 / (N + 1), Williams 2017) ----
ACWR_ACUTE_DAYS = 7
ACWR_CHRONIC_DAYS = 28
ACWR_MIN_HISTORY = 28           # days of history before the ratio is reported
ACWR_SPIKE = 1.5                # neutral "load jumped" flag, not an injury cut-off

# ---- Maturity gates ----
HISTORY_MIN_DAYS = 14           # below this, no form band at all
HISTORY_FULL_DAYS = 42          # one CTL time constant; below this, low confidence
MIN_CTL_FOR_FORM = 5.0          # form % (and ACWR) are noise when fitness is ~0

# ---- Form % bands (tsb / ctl x 100): coaching convention, not validated ----
FORM_BANDS = [                  # (exclusive lower bound, band); else "overreaching"
    (25.0, "transition"),
    (5.0, "fresh"),
    (-10.0, "neutral"),
    (-30.0, "building"),
]

# ---- Confidence: share of the last 42 days' load that was measured ----
MEASURED_METHODS = ("garmin_load", "trimp", "relative_effort")
CONFIDENCE_WINDOW = CTL_TIME_CONSTANT
MEASURED_SHARE_HIGH = 0.8
MEASURED_SHARE_MEDIUM = 0.5

# ---- TRIMP (Banister 1991): load/min = HRr * a * e^(b * HRr) ----
TRIMP_COEFFICIENTS = {"male": (0.64, 1.92), "female": (0.86, 1.67)}
DEFAULT_TRIMP_SEX = "male"      # Banister's original curve; set TRIMP_SEX to change
RESTING_HR_READINGS = 7         # median of this many nearest resting-HR readings
MIN_HR_RESERVE = 20             # bpm; a smaller max - rest means bad HR inputs
MIN_PLAUSIBLE_MAX_HR = 100
MAX_PLAUSIBLE_HR = 220

# Rough TRIMP-equivalent load per minute at a typical effort, for sessions
# with no HR, load or effort score at all. Deliberately coarse: any session
# that needs it counts as estimated, which lowers that period's confidence.
LOAD_PER_MINUTE = {
    "run": 1.2, "ride": 0.9, "swim": 1.0, "row": 1.0, "ski": 1.0,
    "hike": 0.7, "strength": 0.6, "walk": 0.35, "yoga": 0.3,
}
DEFAULT_LOAD_PER_MINUTE = 0.7

RECENT_SESSIONS_MAX = 10
HISTORY_MAX_DAYS = 730

_CONFIDENCE_TIERS = ["none", "low", "medium", "high"]


def _alpha_time_constant(tau):
    return 1.0 - math.exp(-1.0 / tau)


def _alpha_span(n):
    return 2.0 / (n + 1)


def _round(x, digits):
    return round(x, digits) if x is not None else None


def _minutes(row):
    """Active minutes: moving time when known (average HR is over moving
    time), else elapsed time."""
    seconds = row.get("moving_time_s") or row.get("duration_s")
    return seconds / 60.0 if seconds and seconds > 0 else None


def trimp(minutes, avg_hr, resting_hr, max_hr, sex=DEFAULT_TRIMP_SEX):
    """Banister TRIMP for one session, or None when the inputs can't support it."""
    if None in (minutes, avg_hr, resting_hr, max_hr) or minutes <= 0:
        return None
    reserve = max_hr - resting_hr
    if reserve < MIN_HR_RESERVE:
        return None
    hrr = (avg_hr - resting_hr) / reserve
    if hrr <= 0:
        return None
    hrr = min(hrr, 1.0)
    a, b = TRIMP_COEFFICIENTS[sex]
    return minutes * hrr * a * math.exp(b * hrr)


def resting_hr_lookup(wellness):
    """Return f(local_date) -> resting HR: the median of the last
    RESTING_HR_READINGS readings on or before that date (point-in-time), or of
    the earliest readings for sessions that predate all wellness data."""
    readings = sorted(
        (r["date"], r["resting_hr"]) for r in wellness
        if r.get("resting_hr") is not None and isinstance(r.get("date"), str)
    )
    dates = [d for d, _ in readings]
    values = [v for _, v in readings]

    def at(local_date):
        if not values:
            return None
        i = bisect.bisect_right(dates, local_date)
        window = values[max(0, i - RESTING_HR_READINGS):i] if i else values[:RESTING_HR_READINGS]
        return statistics.median(window)

    return at


def _number(value):
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def athlete_params(activity_rows, wellness, settings):
    """Max HR and TRIMP curve. Each resolves env var > DB setting > default,
    like coach.llm_config(); max HR otherwise falls back to the highest
    plausible value observed in the given rows."""
    sex = str(os.getenv("TRIMP_SEX") or settings.get("trimp_sex") or DEFAULT_TRIMP_SEX).lower()
    if sex not in TRIMP_COEFFICIENTS:
        sex = DEFAULT_TRIMP_SEX
    override = _number(os.getenv("ATHLETE_MAX_HR") or settings.get("athlete_max_hr"))
    if override:
        return {"max_hr": override, "max_hr_source": "setting", "trimp_sex": sex}
    observed = [
        v for v in [r.get("max_hr") for r in activity_rows] + [r.get("max_hr") for r in wellness]
        if v is not None and MIN_PLAUSIBLE_MAX_HR <= v <= MAX_PLAUSIBLE_HR
    ]
    return {
        "max_hr": max(observed) if observed else None,
        "max_hr_source": "observed" if observed else None,
        "trimp_sex": sex,
    }


def _resolve(members, rest_at, params):
    """Load for one dedup group; members are ordered best source first."""
    lead = members[0]
    minutes = next((m for m in map(_minutes, members) if m), None)
    load = method = None

    with_load = next((m for m in members if m.get("training_load") is not None), None)
    if with_load is not None:
        load, method = with_load["training_load"], "garmin_load"

    if load is None:
        resting = rest_at(lead["local_date"])
        for m in members:
            t = trimp(_minutes(m), m.get("avg_hr"), resting,
                      params["max_hr"], params["trimp_sex"])
            if t is not None:
                load, method = t, "trimp"
                break

    if load is None:
        with_effort = next((m for m in members if m.get("suffer_score") is not None), None)
        if with_effort is not None:
            load, method = with_effort["suffer_score"], "relative_effort"

    if load is None and minutes:
        rate = LOAD_PER_MINUTE.get(lead["sport_family"], DEFAULT_LOAD_PER_MINUTE)
        load, method = minutes * rate, "duration_estimate"

    if load is None:
        load, method = 0.0, "none"

    return {
        "id": lead["id"],
        "local_date": lead["local_date"],
        "start_time_utc": lead["start_time_utc"],
        "sport_family": lead["sport_family"],
        "sport_type": lead["sport_type"],
        "name": lead["name"],
        "minutes": _round(minutes, 1),
        "load": round(load, 1),
        "method": method,
        "sources": sorted({m["source"] for m in members}),
    }


def session_loads(activity_rows, wellness, params):
    """One load per dedup group, newest first. `activity_rows` must include
    duplicates (db.get_activities(include_duplicates=True)) so a canonical
    session can borrow a signal its duplicate has — e.g. a Strava Relative
    Effort for a Garmin session recorded without HR."""
    rest_at = resting_hr_lookup(wellness)
    groups = defaultdict(list)
    for r in activity_rows:
        groups[r.get("duplicate_of") or r["id"]].append(r)
    sessions = []
    for members in groups.values():
        members.sort(key=lambda r: (activities.SOURCE_PRIORITY.get(r["source"], 99), r["id"]))
        sessions.append(_resolve(members, rest_at, params))
    sessions.sort(key=lambda s: s["start_time_utc"], reverse=True)
    return sessions


def _form_band(form_pct):
    for floor, band in FORM_BANDS:
        if form_pct > floor:
            return band
    return "overreaching"


def _confidence(history_days, measured_share):
    if measured_share is None:
        return "low" if history_days else "none"
    if measured_share >= MEASURED_SHARE_HIGH:
        tier = "high"
    elif measured_share >= MEASURED_SHARE_MEDIUM:
        tier = "medium"
    else:
        tier = "low"
    if history_days < HISTORY_FULL_DAYS:
        tier = _CONFIDENCE_TIERS[min(_CONFIDENCE_TIERS.index(tier), 1)]
    return tier


def daily_series(sessions, end=None):
    """Daily state, oldest first, from the first session's day through `end`
    (or the last session's day, if later). See the module docstring for the
    entering-the-day convention."""
    if not sessions:
        return []
    by_day = defaultdict(float)
    measured = defaultdict(float)
    for s in sessions:
        d = date.fromisoformat(s["local_date"])
        by_day[d] += s["load"]
        if s["method"] in MEASURED_METHODS:
            measured[d] += s["load"]

    first = min(by_day)
    last = max(max(by_day), end or first)
    a_ctl = _alpha_time_constant(CTL_TIME_CONSTANT)
    a_atl = _alpha_time_constant(ATL_TIME_CONSTANT)
    a_acute = _alpha_span(ACWR_ACUTE_DAYS)
    a_chronic = _alpha_span(ACWR_CHRONIC_DAYS)

    ctl = atl = acute = chronic = 0.0
    window_total = window_measured = 0.0   # load over the CONFIDENCE_WINDOW days before d
    rows = []
    d = first
    while d <= last:
        prev = d - timedelta(days=1)
        dropped = prev - timedelta(days=CONFIDENCE_WINDOW)
        window_total += by_day.get(prev, 0.0) - by_day.get(dropped, 0.0)
        window_measured += measured.get(prev, 0.0) - measured.get(dropped, 0.0)

        history = (d - first).days
        ctl_r, atl_r = round(ctl, 1), round(atl, 1)
        form_pct = (ctl - atl) / ctl * 100 if ctl >= MIN_CTL_FOR_FORM else None
        acwr = (acute / chronic
                if history >= ACWR_MIN_HISTORY and chronic >= MIN_CTL_FOR_FORM else None)
        share = window_measured / window_total if window_total > 1e-9 else None
        flags = []
        if acwr is not None and acwr > ACWR_SPIKE:
            flags.append("load_spike")
        if history < HISTORY_FULL_DAYS:
            flags.append("warming_up")
        rows.append({
            "date": d.isoformat(),
            "load": round(by_day.get(d, 0.0), 1),
            "ctl": ctl_r,
            "atl": atl_r,
            "tsb": round(ctl_r - atl_r, 1),
            "form_pct": _round(form_pct, 1),
            "form_band": (_form_band(form_pct)
                          if form_pct is not None and history >= HISTORY_MIN_DAYS else None),
            "acwr": _round(acwr, 2),
            "history_days": history,
            "measured_share": _round(share, 2),
            "confidence": _confidence(history, share),
            "flags": flags,
        })

        load = by_day.get(d, 0.0)
        ctl += (load - ctl) * a_ctl
        atl += (load - atl) * a_atl
        acute += (load - acute) * a_acute
        chronic += (load - chronic) * a_chronic
        d += timedelta(days=1)
    return rows


_FORM_PHRASE = {
    "transition": "very fresh — recent load is well below your fitness",
    "fresh": "fresh",
    "neutral": "balanced",
    "building": "carrying productive training fatigue",
    "overreaching": "carrying high training fatigue",
}


def _summary(s):
    if s["form_band"] is not None:
        text = (f"Training load: {_FORM_PHRASE[s['form_band']]} (form {s['form_pct']:+.0f}% "
                f"— fitness {s['ctl']:.0f}, fatigue {s['atl']:.0f}).")
        if "warming_up" in s["flags"]:
            text += f" Baseline still building ({s['history_days']} of {HISTORY_FULL_DAYS} days)."
    elif s["history_days"] < HISTORY_MIN_DAYS:
        text = (f"Training load: still building a baseline ({s['history_days']} of "
                f"{HISTORY_FULL_DAYS} days) — fitness {s['ctl']:.0f}, fatigue {s['atl']:.0f}.")
    else:
        text = (f"Training load: too little recent training to rate form "
                f"(fitness {s['ctl']:.0f}, fatigue {s['atl']:.0f}).")
    if "load_spike" in s["flags"]:
        text += f" Load jumped well above your recent norm (acute:chronic {s['acwr']:.2f})."
    return text


def describe(row, sessions):
    """A daily row plus the last 7 days of sessions and a templated summary."""
    d = date.fromisoformat(row["date"])
    week_start = d - timedelta(days=6)
    week = [s for s in sessions
            if week_start <= date.fromisoformat(s["local_date"]) <= d]
    state = dict(row)
    state["last_7_days"] = {
        "sessions": len(week),
        "load": round(sum(s["load"] for s in week), 1),
        "minutes": round(sum(s["minutes"] or 0 for s in week)),
    }
    state["recent_sessions"] = week[:RECENT_SESSIONS_MAX]
    state["summary"] = _summary(state)
    return state


def state_on(date_str, data):
    """describe() for one date, or None if it falls outside the series."""
    row = next((r for r in data["series"] if r["date"] == date_str), None)
    return describe(row, data["sessions"]) if row else None


def readiness_note(readiness_band, state):
    """Fuse the two axes: the load summary plus what it means for today's
    readiness band. Readiness itself stays wellness-only."""
    band = state["form_band"]
    note = state["summary"]
    if readiness_band == "green":
        if band == "overreaching":
            note += " Recovery markers look fine, but fatigue is high — consider capping intensity today."
        elif band in ("fresh", "transition"):
            note += " You're fresh as well — a good day for a key session."
    elif readiness_band in ("amber", "red"):
        if band == "overreaching":
            note += " High training fatigue is the likely cause — prioritise recovery."
        elif band in ("fresh", "transition", "neutral"):
            note += " Training load isn't high, so look at sleep, stress or illness instead."
    return note


_READINESS_FIELDS = ("date", "ctl", "atl", "tsb", "form_pct", "form_band", "acwr",
                     "confidence", "flags")


def annotate_readiness(readiness, state):
    """Readiness response plus a `training_load` object, with the fused note
    appended to the briefing when both axes are available."""
    out = dict(readiness)
    out["training_load"] = {k: state[k] for k in _READINESS_FIELDS} if state else None
    if state and readiness.get("score") is not None:
        out["briefing"] = f"{readiness['briefing']} {readiness_note(readiness['band'], state)}"
    return out


# ============= DATABASE ENTRY POINTS =============

def _latest_date(wellness, sessions):
    dates = [s["local_date"] for s in sessions]
    dates += [r["date"] for r in wellness[:1] if isinstance(r.get("date"), str)]
    parsed = []
    for d in dates:
        try:
            parsed.append(date.fromisoformat(d))
        except ValueError:
            continue
    return max(parsed) if parsed else None


def compute(exclude_sources=()):
    """Sessions, daily series and athlete parameters from the database.
    `exclude_sources` drops every row from those sources — and so anything
    derived from them, such as borrowed effort scores or observed max HR."""
    wellness = db.get_all_days()
    rows = [r for r in db.get_activities(include_duplicates=True)
            if r["source"] not in exclude_sources]
    params = athlete_params(rows, wellness, db.get_all_settings())
    sessions = session_loads(rows, wellness, params)
    return {
        "sessions": sessions,
        "series": daily_series(sessions, _latest_date(wellness, sessions)),
        "params": params,
    }


def training_load_today(exclude_sources=()):
    data = compute(exclude_sources)
    if not data["series"]:
        return {
            "date": None, "load": None, "ctl": None, "atl": None, "tsb": None,
            "form_pct": None, "form_band": None, "acwr": None, "history_days": 0,
            "measured_share": None, "confidence": "none", "flags": [],
            "last_7_days": {"sessions": 0, "load": 0.0, "minutes": 0},
            "recent_sessions": [], "parameters": data["params"],
            "summary": "No activities recorded yet — import your Strava history or sync Garmin.",
        }
    state = describe(data["series"][-1], data["sessions"])
    state["parameters"] = data["params"]
    return state


def training_load_history(days=90, exclude_sources=()):
    """Daily state for the most recent `days` days, newest first."""
    days = max(1, min(int(days), HISTORY_MAX_DAYS))
    series = compute(exclude_sources)["series"]
    return {"days": days, "series": series[-days:][::-1]}
