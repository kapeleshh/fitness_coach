"""Import historic activities from a Strava bulk export.

Get the export from Strava → Settings → My Account → "Download or Delete
Your Account" → Request your archive. Put the zip under data/ (gitignored).
This reads its activities.csv: fully offline, no API rate limits, all history
in one pass. Ongoing activities come from strava_sync.py afterwards.

Usage:
    python strava_import.py data/export_12345.zip
    python strava_import.py data/export_12345/            # extracted folder
    python strava_import.py data/activities.csv --tz Asia/Tokyo

activities.csv quirks handled here:
- Several headers appear twice (Elapsed Time, Distance, Max Heart Rate,
  Relative Effort). The first copy is in display units (Distance in km or mi
  depending on account settings); the later copy is raw SI (meters,
  seconds). The LAST occurrence of each header is used. If a file has only
  one Distance column its unit is ambiguous, so distance is left NULL rather
  than guessed.
- "Activity Date" is UTC with no zone marker, e.g. "Mar 15, 2023, 7:12:34 AM".
  local_date is derived by converting to --tz (default: this machine's zone).
"""

import argparse
import csv
import io
import json
import zipfile
from datetime import UTC, datetime, tzinfo
from pathlib import Path
from zoneinfo import ZoneInfo

import activities
import db

_DATE_FORMATS = (
    "%b %d, %Y, %I:%M:%S %p",
    "%b %d, %Y, %H:%M:%S",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%SZ",
)

# Header → our field, for columns whose last occurrence is in SI units.
_NUMERIC_COLUMNS = {
    "Elapsed Time": "duration_s",
    "Moving Time": "moving_time_s",
    "Elevation Gain": "elevation_gain_m",
    "Average Heart Rate": "avg_hr",
    "Max Heart Rate": "max_hr",
    "Average Watts": "avg_power",
    "Calories": "calories",
    "Relative Effort": "suffer_score",
}


def parse_activity_date(value: str) -> datetime:
    # Newer exports put a narrow no-break space before AM/PM.
    cleaned = " ".join(value.replace(" ", " ").replace("\xa0", " ").split())
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(cleaned, fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    raise ValueError(f"Unrecognized Activity Date: {value!r}")


def _number(value: str | None) -> float | None:
    """Strict float parse. Anything else (blank, "10,5", "1,234") is NULL:
    a comma's meaning depends on locale, and a guessed number is worse than
    a missing one."""
    if value is None or value.strip() == "":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_activities_csv(text: str, tz: tzinfo) -> tuple[list[dict], int]:
    """Parse activities.csv content into raw activity dicts (pre-normalization).
    Returns (records, skipped) — rows with an unreadable date are skipped."""
    reader = csv.reader(io.StringIO(text))
    header = next(reader, None)
    if not header:
        return [], 0
    # Last occurrence wins for duplicated headers (the SI-unit copy).
    index = {name.strip(): i for i, name in enumerate(header)}
    distance_is_si = sum(1 for name in header if name.strip() == "Distance") > 1

    def cell(row: list[str], name: str) -> str | None:
        i = index.get(name)
        return row[i] if i is not None and i < len(row) else None

    records, skipped = [], 0
    for row in reader:
        if not row or not cell(row, "Activity ID"):
            continue
        try:
            start = parse_activity_date(cell(row, "Activity Date") or "")
        except ValueError:
            skipped += 1
            continue
        record = {
            "source": "strava",
            "source_id": cell(row, "Activity ID").strip(),
            "start_time_utc": activities.to_utc_iso(start),
            "local_date": start.astimezone(tz).strftime("%Y-%m-%d"),
            "sport_type": (cell(row, "Activity Type") or "").strip() or None,
            "name": (cell(row, "Activity Name") or "").strip() or None,
            "distance_m": _number(cell(row, "Distance")) if distance_is_si else None,
        }
        for column, field in _NUMERIC_COLUMNS.items():
            record[field] = _number(cell(row, column))
        records.append(record)
    return records, skipped


def read_export(path: Path) -> str:
    """Return activities.csv text from a zip, an extracted folder, or the CSV."""
    if path.is_dir():
        return (path / "activities.csv").read_text(encoding="utf-8-sig")
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as zf:
            name = next(
                (n for n in zf.namelist() if Path(n).name == "activities.csv"), None
            )
            if name is None:
                raise FileNotFoundError(f"No activities.csv inside {path}")
            return zf.read(name).decode("utf-8-sig")
    return path.read_text(encoding="utf-8-sig")


def import_export(path: Path, tz: tzinfo | None = None) -> dict:
    tz = tz or datetime.now().astimezone().tzinfo
    records, skipped = parse_activities_csv(read_export(path), tz)
    db.init_db()
    result = activities.ingest(records)
    return {"parsed": len(records), "skipped_unreadable_date": skipped, **result}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Import a Strava bulk export")
    parser.add_argument("path", type=Path, help="export zip, extracted folder, or activities.csv")
    parser.add_argument("--tz", help="IANA timezone for local dates (default: system)")
    args = parser.parse_args()
    result = import_export(args.path, ZoneInfo(args.tz) if args.tz else None)
    print(json.dumps(result, indent=2))
