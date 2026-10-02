"""Per-session activity records from Strava and Garmin: normalization,
cross-source dedup, and ingest into SQLite (see db.py).

Garmin usually auto-uploads to Strava, so the same session typically exists
twice. Every activity row is kept (so re-syncs stay idempotent), and the
non-canonical copy of each duplicate group points at the canonical one via
`duplicate_of`. Garmin wins when both exist — it carries native training
load and comes from the same device as the wellness data; Strava supplies
pre-Garmin history and anything not recorded on the Garmin device.

Missing-data policy matches daily wellness: absent metrics are NULL, and
physiologically impossible zeros (HR 0, power 0, ...) are mapped to NULL.
"""

import re
from datetime import UTC, datetime, timedelta

import db

# Same session if same sport family, starts within this window, and
# durations differ by less than DEDUP_DURATION_TOLERANCE (relative).
DEDUP_START_WINDOW = timedelta(minutes=5)
DEDUP_DURATION_TOLERANCE = 0.10

# Lower rank wins when choosing the canonical row of a duplicate group.
SOURCE_PRIORITY = {"garmin": 0, "strava": 1}

ZERO_IS_MISSING = {
    "avg_hr", "max_hr", "avg_power", "calories",
    "suffer_score", "training_load", "duration_s", "moving_time_s",
}

# Ordered keyword → family rules; first match wins. Keys are matched against
# the type lowercased with non-letters stripped, so Strava "TrailRun" and
# Garmin "trail_running" both become "trailrun..." and map to "run".
_FAMILY_RULES = [
    ("run", "run"),
    ("swim", "swim"),
    ("ride", "ride"),
    ("cycl", "ride"),
    ("bik", "ride"),
    ("walk", "walk"),
    ("hik", "hike"),
    ("weight", "strength"),
    ("strength", "strength"),
    ("yoga", "yoga"),
    ("row", "row"),
    ("ski", "ski"),
]


def sport_family(sport_type: str | None) -> str:
    """Collapse source-specific sport names into a shared family."""
    key = re.sub(r"[^a-z]", "", (sport_type or "").lower())
    for needle, family in _FAMILY_RULES:
        if needle in key:
            return family
    return key or "other"


def to_utc_iso(dt: datetime) -> str:
    """Canonical start-time encoding: UTC, second precision, 'Z' suffix."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_utc_iso(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def normalize_activity(raw: dict) -> dict:
    """Apply the missing-data policy and derive id/family for one activity."""
    record = {field: raw.get(field) for field in db.ACTIVITY_FIELDS}
    if not record["source"] or record["source_id"] in (None, ""):
        raise ValueError("activity requires 'source' and 'source_id'")
    if not record["start_time_utc"] or not record["local_date"]:
        raise ValueError("activity requires 'start_time_utc' and 'local_date'")

    record["source_id"] = str(record["source_id"])
    record["id"] = f"{record['source']}:{record['source_id']}"
    record["sport_family"] = sport_family(record["sport_type"])
    for field in ZERO_IS_MISSING:
        if record.get(field) == 0:
            record[field] = None
    if record.get("name") == "":
        record["name"] = None
    # duplicate_of is owned by find_duplicates(), never by the source.
    record["duplicate_of"] = None
    return record


def _same_session(a: dict, b: dict) -> bool:
    """Sport and duration check for two activities already known to start
    within DEDUP_START_WINDOW of each other."""
    if a["source"] == b["source"] or a["sport_family"] != b["sport_family"]:
        return False
    da, db_ = a.get("duration_s"), b.get("duration_s")
    if da is None or db_ is None:
        # Without durations the start-time + sport match is the only signal.
        return True
    return abs(da - db_) / max(da, db_) < DEDUP_DURATION_TOLERANCE


def find_duplicates(records: list[dict]) -> dict[str, str]:
    """Map each non-canonical activity id to its group's canonical id.

    Candidate pairs are cross-source only — two sessions from the same source
    starting minutes apart (e.g. a warm-up recorded separately) are distinct.
    Pairs are merged closest-start first, and a group never takes a second
    activity from a source it already has, so one Strava upload can't bridge
    two separate Garmin sessions into one group.
    """
    ordered = sorted(records, key=lambda r: r["start_time_utc"])
    starts = [parse_utc_iso(r["start_time_utc"]) for r in ordered]

    candidates = []
    for i in range(len(ordered)):
        for j in range(i + 1, len(ordered)):
            gap = starts[j] - starts[i]
            if gap > DEDUP_START_WINDOW:
                break
            if _same_session(ordered[i], ordered[j]):
                candidates.append((gap, i, j))
    candidates.sort()

    group_of = list(range(len(ordered)))
    members = {g: [g] for g in group_of}
    sources = {g: {ordered[g]["source"]} for g in group_of}
    for _, i, j in candidates:
        gi, gj = group_of[i], group_of[j]
        if gi == gj or sources[gi] & sources[gj]:
            continue
        for k in members[gj]:
            group_of[k] = gi
        members[gi].extend(members.pop(gj))
        sources[gi] |= sources.pop(gj)

    links: dict[str, str] = {}
    for indices in members.values():
        if len(indices) < 2:
            continue
        group = [ordered[k] for k in indices]
        canonical = min(
            group, key=lambda r: (SOURCE_PRIORITY.get(r["source"], 99), r["id"])
        )
        for r in group:
            if r["id"] != canonical["id"]:
                links[r["id"]] = canonical["id"]
    return links


def ingest(records: list[dict]) -> dict:
    """Normalize, upsert, and recompute duplicate links across all sources."""
    normalized = [normalize_activity(r) for r in records]
    written = db.upsert_activities(normalized)
    links = find_duplicates(db.get_activities(include_duplicates=True))
    db.set_duplicate_links(links)
    return {"written": written, "duplicates": len(links)}
