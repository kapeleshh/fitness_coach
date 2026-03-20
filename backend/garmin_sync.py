"""
Garmin Connect Live Data Sync
Fetches health data directly from Garmin Connect API using python-garminconnect.
Replaces the need for manual Garmin data exports.

Usage:
    # Sync last 7 days
    python3 backend/garmin_sync.py

    # Sync specific date range
    python3 backend/garmin_sync.py --start 2026-01-01 --end 2026-03-20

    # Sync all historical data
    python3 backend/garmin_sync.py --full

Setup:
    pip install garminconnect
    cp backend/.env.example backend/.env
    # Edit backend/.env with your Garmin credentials
"""

import json
import os
import sys
import time
import argparse
import logging
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional

# Load .env file if present
def load_env():
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, value = line.partition("=")
                    os.environ.setdefault(key.strip(), value.strip())

load_env()

try:
    from garminconnect import (
        Garmin,
        GarminConnectAuthenticationError,
        GarminConnectConnectionError,
        GarminConnectTooManyRequestsError,
    )
except ImportError as _import_err:
    # Only exit when run directly as a script, not when imported by api_server.py
    if __name__ == "__main__":
        print("❌ garminconnect not installed. Run: cd backend && uv sync")
        sys.exit(1)
    else:
        raise

# Paths
BACKEND_DIR = Path(__file__).parent
DATA_FILE = BACKEND_DIR / "parsed_health_data.json"
TOKEN_STORE = Path(os.getenv("GARMIN_TOKEN_STORE", "~/.garminconnect")).expanduser()

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)


# ============= AUTH =============

def get_garmin_client() -> Garmin:
    """Initialize and authenticate Garmin client with token caching."""
    email = os.getenv("GARMIN_EMAIL")
    password = os.getenv("GARMIN_PASSWORD")

    # Try token-based login first (no password needed after first login)
    if TOKEN_STORE.exists() and list(TOKEN_STORE.glob("*.json")):
        try:
            client = Garmin()
            client.login(str(TOKEN_STORE))
            print("✅ Logged in using saved tokens")
            return client
        except Exception:
            print("⚠️  Saved tokens expired, logging in with credentials...")

    # Fall back to email/password
    if not email or not password:
        print("❌ No credentials found.")
        print("   Set GARMIN_EMAIL and GARMIN_PASSWORD in backend/.env")
        print("   Or copy backend/.env.example to backend/.env and fill in your details")
        sys.exit(1)

    try:
        client = Garmin(email=email, password=password)
        client.login()
        # Save tokens for future use
        TOKEN_STORE.mkdir(parents=True, exist_ok=True)
        client.garth.dump(str(TOKEN_STORE))
        print(f"✅ Logged in as {email}, tokens saved to {TOKEN_STORE}")
        return client
    except GarminConnectAuthenticationError:
        print("❌ Authentication failed. Check your email/password in backend/.env")
        sys.exit(1)
    except GarminConnectTooManyRequestsError:
        print("❌ Too many requests. Please wait before trying again.")
        sys.exit(1)
    except GarminConnectConnectionError as e:
        print(f"❌ Connection error: {e}")
        sys.exit(1)


# ============= DATA FETCHING =============

def safe_get(func, *args, default=None, **kwargs):
    """Call a Garmin API method safely, returning default on any error."""
    try:
        result = func(*args, **kwargs)
        return result if result is not None else default
    except GarminConnectTooManyRequestsError:
        print("  ⚠️  Rate limited — waiting 60 seconds...")
        time.sleep(60)
        try:
            return func(*args, **kwargs)
        except Exception:
            return default
    except Exception as e:
        logger.debug("API call failed: %s", e)
        return default


def fetch_day(client: Garmin, date_str: str) -> dict:
    """
    Fetch all health metrics for a single day from Garmin Connect.
    Returns a dict compatible with DailyHealthData / parsed_health_data.json format.
    """
    day = {
        "date": date_str,
        # Sleep
        "sleep_score": 0,
        "deep_sleep_minutes": 0,
        "light_sleep_minutes": 0,
        "rem_sleep_minutes": 0,
        "awake_minutes": 0,
        "sleep_start_time": None,
        "sleep_end_time": None,
        "avg_sleep_stress": 0.0,
        "sleep_insight": "",
        "sleep_feedback": "",
        # Heart Rate & HRV
        "resting_hr": 0,
        "min_hr": 0,
        "max_hr": 0,
        "hrv": 0.0,
        "hrv_status": "UNKNOWN",
        # Body Battery
        "body_battery_start": 0,
        "body_battery_end": 0,
        "body_battery_high": 0,
        "body_battery_low": 0,
        "body_battery_charged": 0,
        "body_battery_drained": 0,
        # Stress
        "avg_stress": 0,
        "max_stress": 0,
        "stress_rest_minutes": 0,
        "stress_low_minutes": 0,
        "stress_medium_minutes": 0,
        "stress_high_minutes": 0,
        # Activity
        "steps": 0,
        "distance_meters": 0.0,
        "active_calories": 0,
        "total_calories": 0,
        "floors_climbed": 0,
        "active_minutes": 0,
        # Respiration
        "avg_respiration": 0.0,
        "lowest_respiration": 0.0,
        "highest_respiration": 0.0,
    }

    # --- Sleep ---
    sleep_data = safe_get(client.get_sleep_data, date_str, default={})
    if sleep_data:
        scores = sleep_data.get("dailySleepDTO", {}).get("sleepScores", {})
        dto = sleep_data.get("dailySleepDTO", {})
        day["sleep_score"] = scores.get("overallScore", 0) or dto.get("sleepScores", {}).get("overallScore", 0)
        day["deep_sleep_minutes"] = (dto.get("deepSleepSeconds", 0) or 0) // 60
        day["light_sleep_minutes"] = (dto.get("lightSleepSeconds", 0) or 0) // 60
        day["rem_sleep_minutes"] = (dto.get("remSleepSeconds", 0) or 0) // 60
        day["awake_minutes"] = (dto.get("awakeSleepSeconds", 0) or 0) // 60
        day["sleep_start_time"] = dto.get("sleepStartTimestampGMT")
        day["sleep_end_time"] = dto.get("sleepEndTimestampGMT")
        day["avg_sleep_stress"] = dto.get("avgSleepStress", 0.0) or 0.0
        day["sleep_insight"] = scores.get("insight", "")
        day["sleep_feedback"] = scores.get("feedback", "")

    # --- HRV ---
    hrv_data = safe_get(client.get_hrv_data, date_str, default={})
    if hrv_data:
        hrv_summary = hrv_data.get("hrvSummary", {})
        day["hrv"] = float(hrv_summary.get("lastNight", 0) or 0)
        day["hrv_status"] = hrv_summary.get("status", "UNKNOWN") or "UNKNOWN"

    # --- Heart Rate ---
    hr_data = safe_get(client.get_heart_rates, date_str, default={})
    if hr_data:
        day["resting_hr"] = hr_data.get("restingHeartRate", 0) or 0
        day["min_hr"] = hr_data.get("minHeartRate", 0) or 0
        day["max_hr"] = hr_data.get("maxHeartRate", 0) or 0

    # --- Body Battery ---
    bb_data = safe_get(client.get_body_battery, date_str, default=[])
    if bb_data and isinstance(bb_data, list) and len(bb_data) > 0:
        bb = bb_data[0] if isinstance(bb_data[0], dict) else {}
        day["body_battery_charged"] = bb.get("charged", 0) or 0
        day["body_battery_drained"] = bb.get("drained", 0) or 0
        # Get start/end/high/low from body battery values list
        bb_values = bb.get("bodyBatteryValuesArray", [])
        if bb_values:
            values_only = [v[1] for v in bb_values if v and len(v) > 1 and v[1] is not None]
            if values_only:
                day["body_battery_start"] = values_only[0]
                day["body_battery_end"] = values_only[-1]
                day["body_battery_high"] = max(values_only)
                day["body_battery_low"] = min(values_only)

    # --- Stress ---
    stress_data = safe_get(client.get_all_day_stress, date_str, default={})
    if stress_data:
        agg_list = stress_data.get("aggregatorList", [])
        for agg in agg_list:
            if agg.get("type") == "TOTAL":
                day["avg_stress"] = agg.get("averageStressLevel", 0) or 0
                day["max_stress"] = agg.get("maxStressLevel", 0) or 0
                day["stress_rest_minutes"] = (agg.get("restDuration", 0) or 0) // 60
                day["stress_low_minutes"] = (agg.get("lowDuration", 0) or 0) // 60
                day["stress_medium_minutes"] = (agg.get("mediumDuration", 0) or 0) // 60
                day["stress_high_minutes"] = (agg.get("highDuration", 0) or 0) // 60
                break

    # --- Daily Summary (steps, calories, distance, floors) ---
    summary = safe_get(client.get_user_summary, date_str, default={})
    if summary:
        day["steps"] = summary.get("totalSteps", 0) or 0
        day["distance_meters"] = float(summary.get("totalDistanceMeters", 0) or 0)
        day["active_calories"] = int(summary.get("activeKilocalories", 0) or 0)
        day["total_calories"] = int(summary.get("totalKilocalories", 0) or 0)
        day["floors_climbed"] = int(summary.get("floorsAscended", 0) or 0)
        moderate = summary.get("moderateIntensityMinutes", 0) or 0
        vigorous = summary.get("vigorousIntensityMinutes", 0) or 0
        day["active_minutes"] = moderate + (vigorous * 2)
        # Resting HR from summary if not already set
        if not day["resting_hr"]:
            day["resting_hr"] = summary.get("restingHeartRate", 0) or 0
        if not day["min_hr"]:
            day["min_hr"] = summary.get("minHeartRate", 0) or 0
        if not day["max_hr"]:
            day["max_hr"] = summary.get("maxHeartRate", 0) or 0

    # --- Respiration ---
    resp_data = safe_get(client.get_respiration_data, date_str, default={})
    if resp_data:
        day["avg_respiration"] = float(resp_data.get("avgWakingRespirationValue", 0) or 0)
        day["lowest_respiration"] = float(resp_data.get("lowestRespirationValue", 0) or 0)
        day["highest_respiration"] = float(resp_data.get("highestRespirationValue", 0) or 0)

    return day


# ============= SYNC LOGIC =============

def load_existing_data() -> dict:
    """Load existing parsed_health_data.json as a date-keyed dict."""
    if DATA_FILE.exists():
        with open(DATA_FILE, "r") as f:
            data_list = json.load(f)
        return {d["date"]: d for d in data_list}
    return {}


def save_data(data_by_date: dict):
    """Save data dict back to parsed_health_data.json sorted by date descending."""
    sorted_dates = sorted(data_by_date.keys(), reverse=True)
    data_list = [data_by_date[d] for d in sorted_dates]
    with open(DATA_FILE, "w") as f:
        json.dump(data_list, f, indent=2)
    print(f"💾 Saved {len(data_list)} days to {DATA_FILE}")


def sync_date_range(
    client: Garmin,
    start: date,
    end: date,
    overwrite: bool = False,
    delay: float = 1.0,
) -> dict:
    """
    Fetch data for each day in [start, end] and merge into existing data.
    Returns summary of what was synced.
    """
    existing = load_existing_data()
    total_days = (end - start).days + 1
    synced = 0
    skipped = 0

    print(f"\n📡 Syncing {total_days} days ({start} → {end})")
    print(f"   Overwrite existing: {overwrite}")
    print()

    current = start
    while current <= end:
        date_str = current.strftime("%Y-%m-%d")

        if date_str in existing and not overwrite:
            print(f"  ⏭️  {date_str} — already exists, skipping")
            skipped += 1
        else:
            print(f"  📥 {date_str} — fetching...", end=" ", flush=True)
            try:
                day_data = fetch_day(client, date_str)
                existing[date_str] = day_data
                synced += 1
                print("✅")
            except Exception as e:
                print(f"❌ Error: {e}")

            # Rate limit protection: 1 second between requests
            time.sleep(delay)

        current += timedelta(days=1)

    save_data(existing)

    return {
        "synced": synced,
        "skipped": skipped,
        "total": len(existing),
        "date_range": {"start": str(start), "end": str(end)},
    }


def sync_latest(client: Garmin, days: int = 7) -> dict:
    """Sync the last N days (always overwrites to get fresh data)."""
    end = date.today()
    start = end - timedelta(days=days - 1)
    return sync_date_range(client, start, end, overwrite=True)


def sync_full(client: Garmin, start_date: Optional[str] = None) -> dict:
    """Sync all data from start_date to today. Skips already-downloaded days."""
    if start_date:
        start = datetime.strptime(start_date, "%Y-%m-%d").date()
    else:
        # Default: start from earliest date in existing data, or 90 days ago
        existing = load_existing_data()
        if existing:
            earliest = min(existing.keys())
            start = datetime.strptime(earliest, "%Y-%m-%d").date()
            print(f"📅 Earliest existing data: {earliest}")
        else:
            start = date.today() - timedelta(days=90)
            print(f"📅 No existing data, starting from 90 days ago: {start}")

    end = date.today()
    return sync_date_range(client, start, end, overwrite=False)


# ============= STATUS =============

def get_sync_status() -> dict:
    """Return info about the current state of parsed_health_data.json."""
    if not DATA_FILE.exists():
        return {"status": "no_data", "message": "No data file found. Run sync first."}

    with open(DATA_FILE, "r") as f:
        data = json.load(f)

    if not data:
        return {"status": "empty", "message": "Data file is empty."}

    dates = [d["date"] for d in data]
    dates.sort()

    # Check how stale the data is
    latest_date = datetime.strptime(dates[-1], "%Y-%m-%d").date()
    days_stale = (date.today() - latest_date).days

    return {
        "status": "ok",
        "total_days": len(data),
        "earliest_date": dates[0],
        "latest_date": dates[-1],
        "days_stale": days_stale,
        "needs_sync": days_stale > 1,
        "file_size_kb": round(DATA_FILE.stat().st_size / 1024, 1),
    }


# ============= CLI =============

def main():
    parser = argparse.ArgumentParser(
        description="Sync Garmin Connect health data to parsed_health_data.json"
    )
    parser.add_argument(
        "--latest",
        type=int,
        metavar="DAYS",
        default=7,
        help="Sync last N days (default: 7, always overwrites)",
    )
    parser.add_argument(
        "--start",
        type=str,
        metavar="YYYY-MM-DD",
        help="Start date for range sync",
    )
    parser.add_argument(
        "--end",
        type=str,
        metavar="YYYY-MM-DD",
        default=date.today().strftime("%Y-%m-%d"),
        help="End date for range sync (default: today)",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Sync all data from earliest known date to today",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing data (use with --start/--end)",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Show current data status without syncing",
    )
    args = parser.parse_args()

    print("🏃‍♂️ Garmin Connect Data Sync")
    print("=" * 40)

    # Status only — no login needed
    if args.status:
        status = get_sync_status()
        print(f"\n📊 Data Status:")
        for k, v in status.items():
            print(f"   {k}: {v}")
        return

    # Login
    client = get_garmin_client()

    # Run appropriate sync mode
    if args.full:
        result = sync_full(client)
    elif args.start:
        start = datetime.strptime(args.start, "%Y-%m-%d").date()
        end = datetime.strptime(args.end, "%Y-%m-%d").date()
        result = sync_date_range(client, start, end, overwrite=args.overwrite)
    else:
        result = sync_latest(client, days=args.latest)

    print(f"\n✅ Sync complete!")
    print(f"   Fetched: {result['synced']} days")
    print(f"   Skipped: {result['skipped']} days (already existed)")
    print(f"   Total in DB: {result['total']} days")


if __name__ == "__main__":
    main()
