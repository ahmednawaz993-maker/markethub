#!/usr/bin/env python3
"""Report what is actually live on Google Play for com.pakbazar24.app.

The read-only companion to play_upload.py: same service-account key, same API,
but it only LISTS. Answers "did the rollout finish, and at what percentage",
which the upload script cannot (it opens an edit, ships, and exits).

Usage:
  python scripts/play_status.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGE = "com.pakbazar24.app"
DEFAULT_KEY = os.path.join(ROOT, "android", "play-service-account.json")


def main() -> int:
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        print("pip install google-api-python-client google-auth", file=sys.stderr)
        return 2

    if not os.path.exists(DEFAULT_KEY):
        print(f"missing service-account key: {DEFAULT_KEY}", file=sys.stderr)
        return 2

    creds = service_account.Credentials.from_service_account_file(
        DEFAULT_KEY, scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    # An edit is how this API reads track state; it is discarded, never committed.
    edit_id = svc.edits().insert(body={}, packageName=PACKAGE).execute()["id"]
    try:
        tracks = svc.edits().tracks().list(
            packageName=PACKAGE, editId=edit_id
        ).execute().get("tracks", [])
        for t in tracks:
            releases = t.get("releases") or []
            if not releases:
                print(f"{t['track']}: (no releases)")
                continue
            for r in releases:
                codes = ",".join(str(c) for c in r.get("versionCodes", []) or [])
                pct = r.get("userFraction")
                pct = f"{float(pct) * 100:g}%" if pct is not None else "100%"
                name = r.get("name", "")
                notes = (r.get("releaseNotes") or [{}])[0].get("text", "")
                notes = notes.replace("\n", " ")[:70]
                print(
                    f"{t['track']}: vc {codes} | name {name} | "
                    f"status {r.get('status')} | rollout {pct}"
                    + (f" | {notes}" if notes else "")
                )
    finally:
        svc.edits().delete(packageName=PACKAGE, editId=edit_id).execute()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
