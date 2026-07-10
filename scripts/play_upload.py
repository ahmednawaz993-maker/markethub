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
        from googleapiclient.http import MediaFileUpload
        from googleapiclient.errors import HttpError
    except ImportError:
        sys.exit("Missing deps. Run:\n"
                 "  pip install google-api-python-client google-auth")

    # Raise the socket timeout — a single-shot upload of a ~58MB AAB stalls and
    # times out on slower links. Combined with the resumable/chunked upload
    # below, this makes large uploads reliable.
    import socket
    socket.setdefaulttimeout(300)

    creds = service_account.Credentials.from_service_account_file(
        args.key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    # One full release attempt: open a fresh edit, upload the AAB, set the
    # track release, and commit. Play edits have a short TTL, so everything from
    # insert -> commit must happen inside one attempt; if the edit expires (or a
    # transient error hits), the caller retries with a brand-new edit. 10MB
    # chunks keep the transfer short enough to finish inside the edit's life.
    def attempt_release():
        edit_id = svc.edits().insert(packageName=PACKAGE, body={}).execute()["id"]
        media = MediaFileUpload(
            args.aab,
            mimetype="application/octet-stream",
            chunksize=10 * 1024 * 1024,
            resumable=True,
        )
        request = svc.edits().bundles().upload(
            packageName=PACKAGE, editId=edit_id, media_body=media)
        bundle = None
        while bundle is None:
            status, bundle = request.next_chunk(num_retries=3)
            if status:
                print(f"  {int(status.progress() * 100)}% uploaded")
        code = bundle["versionCode"]
        svc.edits().tracks().update(
            packageName=PACKAGE,
            editId=edit_id,
            track=args.track,
            body={"releases": [{
                "versionCodes": [str(code)],
                "status": "completed",
                "releaseNotes": [{"language": "en-US", "text": args.notes}],
            }]},
        ).execute()
        svc.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
        return code

    print(f"Uploading {os.path.basename(args.aab)} to '{args.track}' ...")
    last_err = None
    for attempt in range(1, 4):
        try:
            version_code = attempt_release()
            print(f"Done — versionCode {version_code} rolled out to '{args.track}'.")
            return 0
        except HttpError as e:
            last_err = e
            msg = str(e).lower()
            retryable = "expired" in msg or e.resp.status in (409, 429, 500, 502, 503)
            if attempt < 3 and retryable:
                print(f"Attempt {attempt} failed ({e.resp.status}: "
                      f"{'edit expired' if 'expired' in msg else 'transient'}); "
                      f"retrying with a fresh edit ...")
                continue
            raise
    sys.exit(f"Upload failed after retries: {last_err}")


if __name__ == "__main__":
    raise SystemExit(main())
