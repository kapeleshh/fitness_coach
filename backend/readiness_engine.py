"""Daily readiness engine — wellness-only, pure stdlib, NULL-aware.

Produces a deterministic, explainable 0-100 readiness score from Garmin
wellness data (no training-load yet — that is a later phase). The score is a
TWO-axis composite:

  - AUTONOMIC axis (weight 0.65): HRV (0.50) + morning body battery (0.30) +
    resting-HR (0.20). HRV is the rigorous bit — a 7-day rolling mean of
    ln(HRV) compared to a 60-day personal baseline with a smallest-worthwhile-
    change (SWC = 0.5 SD) deadband and a coefficient-of-variation instability
    penalty (Plews/Buchheit HRV-guided-training literature).
  - SLEEP axis (weight 0.35): Garmin sleep_score, capped when total sleep
    time is short.

Body battery is folded INTO the autonomic axis (not a standalone axis) because
it is itself a Garmin composite of overnight HRV+stress+sleep — a separate
axis would double-count. Missing components are dropped and the remaining
weights renormalize; nothing is ever zero-filled. Before a personal HRV
baseline matures (~4 weeks) the HRV term falls back to Garmin's own hrv_status,
fading in linearly so there is no cliff.

Everything is deterministic and reads db.get_all_days(legacy_zero_fill=False),
newest-first. Baselines are point-in-time (only data up to the scored date),
so the history endpoint has no lookahead. A later LLM only rephrases the
templated briefing; it never recomputes the number.

Reference: Plews et al. 2013; Buchheit 2014; Hopkins 2000 (SWC); Flatt & Esco
2016; Kiviniemi 2007. See the design spec for full citations.
"""

import math
from datetime import datetime, timedelta

import db

# ---- Windows & maturity gates ----
HRV_ROLLING_WINDOW = 7          # days, acute ln-HRV mean (Plews/Buchheit)
HRV_RECENT7_MIN_PRESENT = 4     # need >=4 of last 7 days to trust HRV_7
BASELINE_WINDOW = 60            # days, chronic reference
HRV_TRUST_MIN = 14              # valid HRV nights: below -> hrv_status fallback
HRV_TRUST_FULL = 28             # valid HRV nights: at/above -> personal baseline
RHR_RECENT_WINDOW = 3           # days, smooths one bad resting-HR reading
RHR_TRUST_MIN = 14              # valid RHR days before the RHR term is used

# ---- Statistical floors & SWC ----
SD_LN_FLOOR = 0.05              # ln units, floor on baseline ln-HRV SD
SD_RHR_FLOOR = 2.0             # bpm, floor on baseline resting-HR SD
NEUTRAL_ANCHOR = 0.85          # sub-score of an at-baseline day

# ---- CV "variation in variability" penalty ----
HRV_CV_RATIO_LOW = 1.25
HRV_CV_RATIO_HIGH = 2.0
HRV_CV_ABS_FLOOR = 8.0          # %, below this no penalty regardless of ratio
HRV_CV_PENALTY_MAX = 0.15

# ---- Weights ----
W_AUTONOMIC = 0.65
W_SLEEP = 0.35
AUTO_W_HRV = 0.50
AUTO_W_BODY_BATTERY = 0.30
AUTO_W_RHR = 0.20

# Full data-completeness shares (axis weight x sub-weight)
SHARE_HRV = W_AUTONOMIC * AUTO_W_HRV            # 0.325
SHARE_BODY_BATTERY = W_AUTONOMIC * AUTO_W_BODY_BATTERY  # 0.195
SHARE_RHR = W_AUTONOMIC * AUTO_W_RHR            # 0.13
SHARE_SLEEP = W_SLEEP                           # 0.35

SHORT_SLEEP_TST = 300          # min; sleep axis capped at 0.50 below 5h
SHORT_SLEEP_CAP = 0.50

HRV_STATUS_MAP = {"BALANCED": 0.85, "UNBALANCED": 0.50, "LOW": 0.30}

# Illness / non-functional-overreaching override (trusted baseline only)
ILLNESS_HRV_Z = -1.0
ILLNESS_RHR_ZR = 2.0
ILLNESS_CAP = 0.35
# A large isolated HRV suppression must force red regardless of sleep/battery.
SEVERE_HRV_Z = -2.0
SEVERE_HRV_CAP = 0.45
# Cold-start informational flag (no score change) for an extreme same-week drop.
COLD_START_DROP_MIN_NIGHTS = 7
COLD_START_DROP_Z = -2.5

BAND_GREEN_MIN = 70
BAND_AMBER_MIN = 50

_CONFIDENCE_TIERS = ["none", "low", "medium", "high"]


def _clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def _mean(xs):
    return sum(xs) / len(xs)


def _sample_sd(xs):
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def _shared_curve(x):
    """Map a goodness-z (positive = better) to a 0..1 sub-score.

    Flat NEUTRAL_ANCHOR inside the +/-0.5 SD SWC deadband; asymmetric —
    gentle above baseline, steep below, because suppression is the actionable
    direction. Used for both HRV (x=z) and resting-HR (x=-zr).
    """
    if x >= 1.5:
        return 1.0
    if x >= 0.5:
        return 0.85 + 0.15 * (x - 0.5)
    if x >= -0.5:
        return 0.85
    if x >= -1.5:
        return 0.85 + 0.45 * (x + 0.5)
    if x >= -3.0:
        return 0.40 + (0.40 / 1.5) * (x + 1.5)
    return 0.0


def _parse(d):
    return datetime.strptime(d, "%Y-%m-%d").date()


def _safe_parse(d):
    try:
        return _parse(d)
    except (ValueError, TypeError):
        return None


def _window_values(rows_by_date, target, days, field, transform=None, start=0):
    """Present (non-NULL) values of `field` over the trailing calendar days
    ending at `target` (inclusive), from offset `start` to `days`. Gaps just
    lower the count. `start` lets callers exclude the most-recent week."""
    out = []
    for i in range(start, days):
        row = rows_by_date.get(target - timedelta(days=i))
        if row is None:
            continue
        v = row.get(field)
        if v is None:
            continue
        if field == "hrv" and (not isinstance(v, (int, float)) or v <= 0):
            continue  # defensive: ln needs a positive value
        out.append(transform(v) if transform else v)
    return out


def _body_battery_sub(bb):
    if bb >= 75:
        return 1.0
    if bb >= 25:
        return 0.40 + 0.012 * (bb - 25)
    if bb >= 5:
        return 0.05 + 0.0175 * (bb - 5)
    return 0.05


def _band(score):
    if score is None:
        return "unknown"
    if score >= BAND_GREEN_MIN:
        return "green"
    if score >= BAND_AMBER_MIN:
        return "amber"
    return "red"


_BAND_LABEL = {
    "green": "Train as planned",
    "amber": "Train easy",
    "red": "Rest / recover",
    "unknown": "Not enough data yet",
}
_BAND_GUIDANCE = {
    "green": "Recovery looks good — train as planned; quality/hard work is fine.",
    "amber": "Recovery is slightly down — keep it easy-to-moderate and skip the hard session.",
    "red": "Recovery is low — rest or light active recovery, and check sleep/illness/life stress.",
    "unknown": "Sync your watch and check back.",
}


def _demote(conf, steps=1):
    i = max(0, _CONFIDENCE_TIERS.index(conf) - steps)
    return _CONFIDENCE_TIERS[i]


def score_date(records, target_date):
    """Score readiness for a single date using only records up to that date.

    `records` is db.get_all_days(legacy_zero_fill=False) (newest-first).
    Returns the full readiness object (see module docstring / endpoint spec).
    """
    target = _parse(target_date) if isinstance(target_date, str) else target_date
    # Skip records with an unparseable date rather than letting one bad row
    # (e.g. a malformed legacy import) 500 every readiness call.
    rows_by_date = {}
    for r in records:
        d = _safe_parse(r.get("date"))
        if d is not None and d <= target:
            rows_by_date[d] = r
    today = rows_by_date.get(target)
    flags = []

    # ---------- HRV sub-score ----------
    ln_60 = _window_values(rows_by_date, target, BASELINE_WINDOW, "hrv", math.log)
    # CV baseline excludes the most recent 7 days, so an unstable acute week
    # can't inflate its own reference and self-mask the instability penalty.
    raw_cv_baseline = _window_values(
        rows_by_date, target, BASELINE_WINDOW, "hrv", start=HRV_ROLLING_WINDOW
    )
    n_hrv = len(ln_60)
    recent7_raw = _window_values(rows_by_date, target, HRV_ROLLING_WINDOW, "hrv")
    recent7_ln = [math.log(v) for v in recent7_raw]
    status = (today or {}).get("hrv_status")
    status_sub = HRV_STATUS_MAP.get(status)

    hrv = {
        "available": False, "sub": None, "source": None, "value_ms": None,
        "baseline_ms": None, "pct_dev": None, "z": None, "cv_7": None,
        "cv_ratio": None, "cv_penalty": 0.0, "n_days": n_hrv,
    }

    z = None
    can_form_recent = len(recent7_raw) >= HRV_RECENT7_MIN_PRESENT
    if can_form_recent and n_hrv >= 2:
        hrv_7 = _mean(recent7_ln)
        base_mean = _mean(ln_60)
        base_sd = max(_sample_sd(ln_60), SD_LN_FLOOR)
        z = (hrv_7 - base_mean) / base_sd
        sub_base = _shared_curve(z)
        hrv["value_ms"] = round(math.exp(hrv_7), 1)
        hrv["baseline_ms"] = round(math.exp(base_mean), 1)
        hrv["pct_dev"] = round((math.exp(hrv_7) / math.exp(base_mean) - 1) * 100, 1)
        hrv["z"] = round(z, 2)

        # CV "variation in variability" penalty (base excludes recent 7 days)
        penalty = 0.0
        if len(recent7_raw) >= 2 and len(raw_cv_baseline) >= 2 and _mean(raw_cv_baseline) > 0:
            cv_7 = _sample_sd(recent7_raw) / _mean(recent7_raw) * 100
            base_cv = _sample_sd(raw_cv_baseline) / _mean(raw_cv_baseline) * 100
            hrv["cv_7"] = round(cv_7, 1)
            if base_cv > 0:
                cv_ratio = cv_7 / base_cv
                hrv["cv_ratio"] = round(cv_ratio, 2)
                if cv_ratio > HRV_CV_RATIO_LOW and cv_7 >= HRV_CV_ABS_FLOOR:
                    span = HRV_CV_RATIO_HIGH - HRV_CV_RATIO_LOW
                    penalty = HRV_CV_PENALTY_MAX * _clamp(
                        (cv_ratio - HRV_CV_RATIO_LOW) / span
                    )

        if n_hrv >= HRV_TRUST_FULL:
            hrv.update(available=True, source="baseline",
                       sub=_clamp(sub_base - penalty), cv_penalty=round(penalty, 3))
        elif n_hrv >= HRV_TRUST_MIN:
            # Linear fade-in of the personal baseline. Garmin often still
            # reports hrv_status='UNKNOWN' through this window, so when no
            # status is available we blend toward the NEUTRAL_ANCHOR (0.85)
            # instead of snapping to a full-trust 14-day baseline — otherwise
            # w=0 would still let a thin baseline drive the score (no "cliff").
            w = (n_hrv - HRV_TRUST_MIN) / (HRV_TRUST_FULL - HRV_TRUST_MIN)
            proxy = status_sub if status_sub is not None else NEUTRAL_ANCHOR
            blended = w * sub_base + (1 - w) * proxy - 0.5 * penalty
            hrv.update(available=True, source="blend", sub=_clamp(blended),
                       cv_penalty=round(0.5 * penalty, 3))
        else:  # n_hrv < HRV_TRUST_MIN -> cold start: status only, no z/CV
            z = None  # untrusted; must not feed the illness/severe overrides
            for k in ("value_ms", "baseline_ms", "pct_dev", "z", "cv_7", "cv_ratio"):
                hrv[k] = None
            hrv["cv_penalty"] = 0.0
            if status_sub is not None:
                hrv.update(available=True, source="status", sub=status_sub)
    else:
        # Can't form a trusted acute mean today -> Garmin status fallback.
        if status_sub is not None:
            hrv.update(available=True, source="status", sub=status_sub)
            if n_hrv >= HRV_TRUST_MIN and not can_form_recent:
                flags.append("stale_hrv")

    # ---------- Resting-HR sub-score ----------
    rhr_60 = _window_values(rows_by_date, target, BASELINE_WINDOW, "resting_hr")
    rhr_recent = _window_values(rows_by_date, target, RHR_RECENT_WINDOW, "resting_hr")
    rhr = {"available": False, "sub": None, "value": None, "baseline": None,
           "delta_bpm": None, "zr": None, "n_days": len(rhr_60)}
    zr = None
    if len(rhr_60) >= RHR_TRUST_MIN and rhr_recent:
        r_recent = _mean(rhr_recent)
        r_base = _mean(rhr_60)
        r_sd = max(_sample_sd(rhr_60), SD_RHR_FLOOR)
        zr = (r_recent - r_base) / r_sd
        rhr.update(available=True, sub=_shared_curve(-zr), value=round(r_recent, 1),
                   baseline=round(r_base, 1), delta_bpm=round(r_recent - r_base, 1),
                   zr=round(zr, 2))

    # ---------- Body-battery sub-score ----------
    bb_val = (today or {}).get("body_battery_start")
    body_battery = {"available": False, "sub": None, "value": bb_val}
    if bb_val is not None:
        body_battery.update(available=True, sub=_body_battery_sub(bb_val))

    # ---------- Sleep axis ----------
    sleep_val = (today or {}).get("sleep_score")
    sleep = {"available": False, "sub": None, "value": sleep_val}
    sleep_dur = {"available": False, "tst_min": None, "guard_applied": False}
    if sleep_val is not None:
        sub = _clamp(sleep_val / 100.0)
        stages = [(today or {}).get(k) for k in
                  ("deep_sleep_minutes", "light_sleep_minutes", "rem_sleep_minutes")]
        if all(s is not None for s in stages):
            tst = sum(stages)
            sleep_dur.update(available=True, tst_min=tst)
            if tst < SHORT_SLEEP_TST:
                sub = min(sub, SHORT_SLEEP_CAP)
                sleep_dur["guard_applied"] = True
        sleep.update(available=True, sub=sub)

    # ---------- Autonomic axis (renormalized over present sub-components) ----------
    auto_parts = []
    if hrv["available"]:
        auto_parts.append((AUTO_W_HRV, hrv["sub"]))
    if body_battery["available"]:
        bb_axis = body_battery["sub"]
        # Morning body battery is dominated by overnight sleep charging, so it
        # can read high even when HRV is depressed. Don't let it mask a genuine
        # autonomic withdrawal: when BOTH HRV and resting HR are below their
        # neutral anchor, cap body battery at the stronger of those two direct
        # autonomic signals.
        if (hrv["available"] and rhr["available"]
                and hrv["sub"] < NEUTRAL_ANCHOR and rhr["sub"] < NEUTRAL_ANCHOR):
            capped = min(bb_axis, max(hrv["sub"], rhr["sub"]))
            if capped < bb_axis:
                bb_axis = capped
                flags.append("body_battery_capped")
        auto_parts.append((AUTO_W_BODY_BATTERY, bb_axis))
    if rhr["available"]:
        auto_parts.append((AUTO_W_RHR, rhr["sub"]))
    autonomic_score = (
        sum(w * s for w, s in auto_parts) / sum(w for w, _ in auto_parts)
        if auto_parts else None
    )

    # ---------- Final composite (renormalized over present axes) ----------
    axis_parts = []
    if autonomic_score is not None:
        axis_parts.append((W_AUTONOMIC, autonomic_score))
    if sleep["available"]:
        axis_parts.append((W_SLEEP, sleep["sub"]))

    if not axis_parts:
        return _insufficient(target_date)

    composite = sum(w * s for w, s in axis_parts) / sum(w for w, _ in axis_parts)

    baseline_full = n_hrv >= HRV_TRUST_FULL

    # Illness / overreaching override — only on a trusted (full) baseline, so a
    # thin 14-day baseline can't slam the score to red off two noisy weeks.
    if (baseline_full and z is not None and zr is not None
            and z <= ILLNESS_HRV_Z and zr >= ILLNESS_RHR_ZR):
        composite = min(composite, ILLNESS_CAP)
        flags.append("illness_watch")

    # A large isolated HRV suppression must force red even on great sleep/battery.
    if baseline_full and z is not None and z <= SEVERE_HRV_Z:
        composite = min(composite, SEVERE_HRV_CAP)
        if "hrv_suppressed" not in flags:
            flags.append("hrv_suppressed")

    # Cold start: no trusted baseline for a score cap, but still surface an
    # extreme same-week HRV drop as an informational flag (e.g. week-2 illness).
    if (not baseline_full and n_hrv >= COLD_START_DROP_MIN_NIGHTS
            and can_form_recent and len(ln_60) >= 2):
        cs_z = (_mean(recent7_ln) - _mean(ln_60)) / max(_sample_sd(ln_60), SD_LN_FLOOR)
        if cs_z <= COLD_START_DROP_Z:
            flags.append("hrv_drop_watch")

    score = round(100 * _clamp(composite))
    band = _band(score)

    # ---------- Data completeness & confidence ----------
    completeness = (
        (SHARE_HRV if hrv["available"] else 0)
        + (SHARE_BODY_BATTERY if body_battery["available"] else 0)
        + (SHARE_RHR if rhr["available"] else 0)
        + (SHARE_SLEEP if sleep["available"] else 0)
    )
    if n_hrv >= HRV_TRUST_FULL:
        baseline_status = "full"
    elif n_hrv >= HRV_TRUST_MIN:
        baseline_status = "warming"
    else:
        baseline_status = "cold_start"

    if completeness == 0:
        confidence = "none"
    elif completeness < 0.35:
        confidence = "low"
    elif completeness >= 0.70 and baseline_status == "full":
        confidence = "high"
    else:
        confidence = "medium"
    if "stale_hrv" in flags:
        confidence = _demote(confidence)

    # ---------- Drivers (limiter / support) ----------
    driver_parts = []
    if hrv["available"]:
        driver_parts.append(("hrv", SHARE_HRV, hrv["sub"]))
    if body_battery["available"]:
        driver_parts.append(("body_battery", SHARE_BODY_BATTERY, body_battery["sub"]))
    if rhr["available"]:
        driver_parts.append(("resting_hr", SHARE_RHR, rhr["sub"]))
    if sleep["available"]:
        driver_parts.append(("sleep_score", SHARE_SLEEP, sleep["sub"]))
    gaps = [(name, share * (sub - NEUTRAL_ANCHOR)) for name, share, sub in driver_parts]
    limiter = min(gaps, key=lambda g: g[1])[0]
    support = max(gaps, key=lambda g: g[1])[0]

    total_w = sum(w for w, _ in axis_parts)
    result = {
        "date": target_date if isinstance(target_date, str) else target_date.isoformat(),
        "score": score,
        "band": band,
        "label": _BAND_LABEL[band],
        "confidence": confidence,
        "baseline_status": baseline_status,
        "days_to_full": max(0, HRV_TRUST_FULL - n_hrv),
        "data_completeness": round(completeness, 3),
        "drivers": {"limiter": limiter, "support": support},
        "flags": flags,
        "axes": {
            "autonomic": {
                "score": round(autonomic_score, 3) if autonomic_score is not None else None,
                "weight": W_AUTONOMIC, "present": autonomic_score is not None,
            },
            "sleep": {
                "score": round(sleep["sub"], 3) if sleep["available"] else None,
                "weight": W_SLEEP, "present": sleep["available"],
            },
        },
        "components": {
            "hrv": hrv, "resting_hr": rhr, "body_battery": body_battery,
            "sleep_score": sleep, "sleep_duration": sleep_dur,
        },
        "weights_effective": {
            "autonomic": round(W_AUTONOMIC / total_w, 3) if autonomic_score is not None else 0,
            "sleep": round(W_SLEEP / total_w, 3) if sleep["available"] else 0,
        },
    }
    result["briefing"] = _render_briefing(result)
    return result


def _insufficient(target_date):
    d = target_date if isinstance(target_date, str) else target_date.isoformat()
    return {
        "date": d, "score": None, "band": "unknown",
        "label": _BAND_LABEL["unknown"], "confidence": "none",
        "baseline_status": "cold_start", "data_completeness": 0.0,
        "drivers": {"limiter": None, "support": None}, "flags": [],
        "axes": {"autonomic": {"score": None, "weight": W_AUTONOMIC, "present": False},
                 "sleep": {"score": None, "weight": W_SLEEP, "present": False}},
        "components": {},
        "briefing": (
            f"UNKNOWN — no readiness score. No HRV, body battery or sleep "
            f"recorded for {d}. Sync your watch and check back."
        ),
    }


_COMPONENT_PHRASE = {
    "hrv": lambda c: (
        f"HRV {c['value_ms']:.0f}ms, {c['pct_dev']:+.0f}% vs your 60-day baseline "
        f"(z {c['z']:+.1f})" if c.get("z") is not None and c.get("value_ms")
        else "Garmin HRV status"
    ),
    "resting_hr": lambda c: (
        f"resting HR {c['delta_bpm']:+.0f} bpm vs baseline ({c['value']:.0f} bpm)"
    ),
    "body_battery": lambda c: f"morning body battery {c['value']}",
    "sleep_score": lambda c: f"sleep score {c['value']}",
}


def _confidence_phrase(r):
    conf, base, dtf = r["confidence"], r["baseline_status"], r.get("days_to_full", 0)
    if conf == "high":
        return "high confidence"
    if conf == "medium" and base == "full":
        return "medium confidence"
    if conf == "medium" and base == "warming":
        return f"medium confidence, baseline still building ({dtf}d to go)"
    if base == "cold_start" and conf != "low":
        return f"provisional — using Garmin signals while your baseline builds ({dtf}d to go)"
    if conf == "low":
        return "low confidence, limited data today"
    return "no data"


def _render_briefing(r):
    band = r["band"]
    comps = r["components"]
    limiter, support = r["drivers"]["limiter"], r["drivers"]["support"]

    def phrase(name):
        c = comps.get(name, {})
        try:
            return _COMPONENT_PHRASE[name](c)
        except (KeyError, TypeError):
            return name

    driver = ""
    if limiter:
        driver = f"Main limiter: {phrase(limiter)}"
        if support and support != limiter:
            driver += f"; support {phrase(support)}"
        driver += ". "

    text = (
        f"{band.upper()} — readiness {r['score']}/100 "
        f"({_confidence_phrase(r)}). {driver}{_BAND_GUIDANCE[band]}"
    )
    if "illness_watch" in r["flags"]:
        text = ("Heads-up — HRV down and resting HR up (possible illness/"
                "overreaching): ") + text
    return text


def readiness_today(records=None):
    records = db.get_all_days() if records is None else records
    if not records:
        return _insufficient(datetime.today().strftime("%Y-%m-%d"))
    return score_date(records, records[0]["date"])


def readiness_history(records=None, days=30):
    """Point-in-time readiness for the most recent `days` scored dates."""
    records = db.get_all_days() if records is None else records
    days = max(1, min(int(days), 180))
    series = []
    for r in records[:days]:
        s = score_date(records, r["date"])
        series.append({
            "date": s["date"], "score": s["score"], "band": s["band"],
            "confidence": s["confidence"],
            "autonomic": s["axes"]["autonomic"]["score"],
            "sleep": s["axes"]["sleep"]["score"],
        })
    return {"days": days, "series": series}
