#!/usr/bin/env python3
"""Upload a signed AAB to Google Play for com.pakbazar24.app.

Decoupled from the Gradle build (works regardless of AGP version). Talks to the
Google Play Developer API directly with a service-account key.

One-time setup — see scripts/PLAY_UPLOAD_SETUP.md. In short:
  1. Play Console -> Setup -> API access: link a Google Cloud project, create a
     service account, grant it release permission, download its JSON key.
  2. Save the key as:  android/play-service-account.json   (gitignored)
  3. pip install google-api-python-client google-auth

Usage (after `flutter build appbundle --release`):
  python scripts/play_upload.py --track internal --notes "What's new..."

NOTE: the FIRST release of a new app must be created manually in the Play
Console. This script handles every update after that.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGE = "com.pakbazar24.app"
DEFAULT_KEY = os.path.join(ROOT, "android", "play-service-account.json")
DEFAULT_AAB = os.path.join(
    ROOT, "build", "app", "outputs", "bundle", "release", "app-release.aab"
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload an AAB to Google Play.")
    ap.add_argument(
        "--track",
        default="internal",
        choices=["internal", "alpha", "beta", "production"],
        help="Play track to release to (default: internal).",
    )
    ap.add_argument("--notes", default="Bug fixes and improvements.",
                    help="Release notes (en-US).")
    ap.add_argument("--aab", default=DEFAULT_AAB, help="Path to the .aab.")
    ap.add_argument("--key", default=DEFAULT_KEY,
                    help="Path to the service-account JSON key.")
    args = ap.parse_args()

    if not os.path.exists(args.key):
        sys.exit(f"Service-account key not found: {args.key}\n"
                 f"See scripts/PLAY_UPLOAD_SETUP.md for how to create it.")
    if not os.path.exists(args.aab):
        sys.exit(f"AAB not found: {args.aab}\nRun: flutter build appbundle --release")

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        sys.exit("Missing deps. Run:\n"
                 "  pip install google-api-python-client google-auth")

    creds = service_account.Credentials.from_service_account_file(
        args.key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    print(f"Opening edit for {PACKAGE} ...")
    edit_id = svc.edits().insert(packageName=PACKAGE, body={}).execute()["id"]

    print(f"Uploading {os.path.basename(args.aab)} ...")
    bundle = svc.edits().bundles().upload(
        packageName=PACKAGE,
        editId=edit_id,
        media_body=args.aab,
        media_mime_type="application/octet-stream",
    ).execute()
    version_code = bundle["versionCode"]
    print(f"Uploaded versionCode {version_code}.")

    svc.edits().tracks().update(
        packageName=PACKAGE,
        editId=edit_id,
        track=args.track,
        body={"releases": [{
            "versionCodes": [str(version_code)],
            "status": "completed",
            "releaseNotes": [{"language": "en-US", "text": args.notes}],
        }]},
    ).execute()

    svc.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
    print(f"Done — versionCode {version_code} rolled out to '{args.track}'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
