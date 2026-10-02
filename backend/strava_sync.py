"""Incremental Strava activity sync via the Strava API v3.

Historic backfill should come from the bulk export (strava_import.py); this
keeps activities current afterwards. With no activities in the DB it pages
through the whole history, which is fine for most athletes but can hit the
daily rate limit for very long histories — use the export for those.

Setup (one time):
    1. Create an API application at https://www.strava.com/settings/api with
       "Authorization Callback Domain" = localhost.
    2. Put STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET in backend/.env.
    3. python strava_sync.py --auth
       Open the printed URL, approve, then paste the URL your browser was
       redirected to (the localhost page will fail to load — that's expected;
       the code is in the address bar). Tokens are stored in the SQLite
       user_settings table (fitness.db is gitignored).

Usage:
    python strava_sync.py            # fetch activities newer than the latest stored
    python strava_sync.py --status
"""

import argparse
import json
import os
import time
from datetime import datetime
from urllib.parse import parse_qs, urlencode, urlparse
from zoneinfo import ZoneInfo

import httpx

import activities
import db
from env import load_env

load_env()

AUTH_URL = "https://www.strava.com/oauth/authorize"
TOKEN_URL = "https://www.strava.com/oauth/token"
API_URL = "https://www.strava.com/api/v3"
SCOPE = "read,activity:read_all"
PAGE_SIZE = 200
TOKENS_SETTING = "strava_tokens"
# Refresh slightly before expiry so a request never races the deadline.
_EXPIRY_MARGIN_S = 300


class StravaNotConfigured(RuntimeError):
    pass


class StravaRateLimited(RuntimeError):
    pass


def _credentials() -> tuple[str, str]:
    client_id = os.getenv("STRAVA_CLIENT_ID")
    client_secret = os.getenv("STRAVA_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise StravaNotConfigured(
            "Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET in backend/.env"
        )
    return client_id, client_secret


def is_configured() -> bool:
    """True when credentials exist and the one-time --auth step was done."""
    try:
        _credentials()
    except StravaNotConfigured:
        return False
    db.init_db()
    return db.get_setting(TOKENS_SETTING) is not None


def authorize_url() -> str:
    client_id, _ = _credentials()
    return f"{AUTH_URL}?" + urlencode({
        "client_id": client_id,
        "redirect_uri": "http://localhost",
        "response_type": "code",
        "approval_prompt": "auto",
        "scope": SCOPE,
    })


def _store_tokens(payload: dict) -> None:
    db.set_setting(TOKENS_SETTING, {
        "access_token": payload["access_token"],
        "refresh_token": payload["refresh_token"],
        "expires_at": payload["expires_at"],
    })


def exchange_code(code: str, http: httpx.Client) -> None:
    client_id, client_secret = _credentials()
    res = http.post(TOKEN_URL, data={
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "grant_type": "authorization_code",
    })
    res.raise_for_status()
    _store_tokens(res.json())


def access_token(http: httpx.Client) -> str:
    """Return a valid access token, refreshing (and persisting) if needed."""
    tokens = db.get_setting(TOKENS_SETTING)
    if tokens is None:
        raise StravaNotConfigured("Strava not authorized. Run: python strava_sync.py --auth")
    if tokens["expires_at"] - _EXPIRY_MARGIN_S > time.time():
        return tokens["access_token"]
    client_id, client_secret = _credentials()
    res = http.post(TOKEN_URL, data={
        "client_id": client_id,
        "client_secret": client_secret,
        "grant_type": "refresh_token",
        "refresh_token": tokens["refresh_token"],
    })
    res.raise_for_status()
    payload = res.json()
    _store_tokens(payload)
    return payload["access_token"]


def _parse_api_time(value: str) -> datetime:
    return datetime.fromisoformat(value)


def from_api(item: dict) -> dict:
    """Map a Strava SummaryActivity to a raw activity dict."""
    start = _parse_api_time(item["start_date"])
    if item.get("start_date_local"):
        # start_date_local is local wall-clock time mislabelled with 'Z'.
        local_date = item["start_date_local"][:10]
    elif item.get("timezone"):
        zone = item["timezone"].split(" ")[-1]  # "(GMT+09:00) Asia/Tokyo"
        local_date = start.astimezone(ZoneInfo(zone)).strftime("%Y-%m-%d")
    else:
        local_date = start.strftime("%Y-%m-%d")
    return {
        "source": "strava",
        "source_id": item["id"],
        "start_time_utc": activities.to_utc_iso(start),
        "local_date": local_date,
        "sport_type": item.get("sport_type") or item.get("type"),
        "name": item.get("name"),
        "duration_s": item.get("elapsed_time"),
        "moving_time_s": item.get("moving_time"),
        "distance_m": item.get("distance"),
        "elevation_gain_m": item.get("total_elevation_gain"),
        "avg_hr": item.get("average_heartrate"),
        "max_hr": item.get("max_heartrate"),
        "avg_power": item.get("average_watts"),
        "calories": item.get("calories"),
        "suffer_score": item.get("suffer_score"),
    }


def sync(http: httpx.Client | None = None) -> dict:
    """Fetch activities newer than the latest stored Strava activity.

    Each page is ingested as it arrives, so a rate-limited or interrupted
    sync keeps its progress and the next run resumes from there.
    """
    db.init_db()
    own_client = http is None
    http = http or httpx.Client(timeout=30.0)
    try:
        token = access_token(http)
        latest = db.latest_activity_start("strava")
        # `after` is exclusive; re-fetching the boundary activity is harmless
        # because upserts are idempotent.
        after = int(activities.parse_utc_iso(latest).timestamp()) - 1 if latest else 0

        fetched = duplicates = 0
        page = 1
        while True:
            res = http.get(
                f"{API_URL}/athlete/activities",
                params={"after": after, "page": page, "per_page": PAGE_SIZE},
                headers={"Authorization": f"Bearer {token}"},
            )
            if res.status_code == 429:
                raise StravaRateLimited(
                    f"Strava rate limit hit after {fetched} activities "
                    f"(usage {res.headers.get('X-RateLimit-Usage', '?')}, "
                    f"limit {res.headers.get('X-RateLimit-Limit', '?')}); "
                    "progress saved, re-run later"
                )
            res.raise_for_status()
            items = res.json()
            if not items:
                break
            result = activities.ingest([from_api(i) for i in items])
            fetched += result["written"]
            duplicates = result["duplicates"]
            if len(items) < PAGE_SIZE:
                break
            page += 1
        return {"fetched": fetched, "duplicates": duplicates, "after": after}
    finally:
        if own_client:
            http.close()


def _code_from_input(value: str) -> str:
    value = value.strip()
    if value.startswith("http"):
        codes = parse_qs(urlparse(value).query).get("code")
        if not codes:
            raise ValueError("No 'code' parameter in that URL")
        return codes[0]
    return value


def main():
    parser = argparse.ArgumentParser(description="Sync Strava activities into SQLite")
    parser.add_argument("--auth", action="store_true", help="one-time OAuth authorization")
    parser.add_argument("--status", action="store_true", help="show activity counts")
    args = parser.parse_args()

    db.init_db()
    if args.status:
        print(json.dumps({"configured": is_configured(), **db.activity_summary()}, indent=2))
        return
    if args.auth:
        print("Open this URL, approve access, then paste the redirected URL here:\n")
        print(authorize_url(), "\n")
        code = _code_from_input(input("Redirected URL (or code): "))
        with httpx.Client(timeout=30.0) as http:
            exchange_code(code, http)
        print("✅ Strava authorized; tokens saved")
        return
    print(json.dumps(sync(), indent=2))


if __name__ == "__main__":
    main()
