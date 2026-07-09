# Automated Play uploads — one-time setup

`scripts/play_upload.py` pushes a signed AAB to Google Play via the Play
Developer API. It's for **release #2 onward** — the very first release of the app
must be created manually in the Play Console.

## 1. Create a service account (browser, ~10 min)
1. **Play Console → Setup → API access.**
2. Link a **Google Cloud project** (create one if prompted).
3. Under *Service accounts*, click **Create service account** → this opens Google
   Cloud Console. Create it (any name, e.g. `play-publisher`), no roles needed in
   Cloud, **Done**.
4. On that service account → **Keys → Add key → Create new key → JSON** → download.
5. Back in **Play Console → API access**, find the service account → **Grant
   access** → give it **Admin (or Release manager)** for this app → **Invite**.

## 2. Install the key + deps
- Save the downloaded JSON as: **`android/play-service-account.json`**
  (already gitignored — never commit it; back it up somewhere safe).
- Install the client libraries once:
  ```
  pip install google-api-python-client google-auth
  ```

## 3. Publish an update
```
# bump the version first (pubspec.yaml: version: 1.0.0+N  ->  1.0.0+N+1)
flutter build appbundle --release
python scripts/play_upload.py --track internal --notes "What changed"
```
- `--track` : internal | alpha | beta | production
- Each upload needs a **higher versionCode** than the last (bump `+N` in `pubspec.yaml`).

## Notes
- The service account can upload/manage releases but **cannot** create the first
  listing or edit store text unless granted broader access — keep first-release
  and listing edits in the console.
- After enrolling in **Play App Signing**, add Play's app-signing SHA-1/256 to the
  Firebase app (`com.pakbazar24.app`) or phone-OTP login breaks. See
  `store_assets/play_listing.md`.
