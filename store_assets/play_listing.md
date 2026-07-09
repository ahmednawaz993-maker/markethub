# PakBazar — Google Play listing & submission pack

Package: **com.pakbazar24.app** · Bundle: `build/app/outputs/bundle/release/app-release.aab`
Reflects the current build — the wallet, escrow and paid promotions are HIDDEN
for Play Payments compliance, so this listing must NOT mention them.

## Assets (in this folder)
- App icon 512×512: `icon_512.png`
- Feature graphic 1024×500: `feature_1024x500.png`
- Phone screenshots: `screenshot_home.png`, `screenshot_detail.png`, `screenshot_chat.png`
- Privacy: https://pakbazar24.com/privacy.html · Terms: https://pakbazar24.com/terms.html

---

## App name (max 30)
`PakBazar – Buy & Sell in PK`

## Short description (max 80)
`Pakistan's free marketplace to buy & sell cars, phones, property & more.`

## Full description (max 4000)
PakBazar is Pakistan's own online marketplace — a simple, free place to buy and
sell in your city. List anything in minutes, chat with buyers and sellers, and
find great local deals near you.

Whether you're upgrading your phone, selling your car, renting out a flat, or
hunting for a bargain, PakBazar connects you with real people across Pakistan.

WHAT YOU CAN DO
• Post ads for free in just a couple of minutes
• Browse thousands of listings by category and city
• Chat directly with buyers and sellers, including voice messages
• Make and receive offers to agree on a fair price
• Save your favourite ads and searches for later
• Order with Cash on Delivery on supported listings
• Explore verified business stores and their products

POPULAR CATEGORIES
• Motors — cars, motorcycles, auto parts
• Property — homes, plots and flats for sale or rent
• Mobiles & Tablets — phones, tablets and accessories
• Electronics & home appliances
• Food & Grocery
• Commute & Rides
• Fashion, and much more

BUILT FOR PAKISTAN
• Full English and اردو (Urdu) support
• Prices in PKR, cities across the country
• Location-aware so you see what's nearby

SAFE & TRUSTED
• Optional identity verification for added trust
• Report and block tools to keep the marketplace clean
• You control your data — delete your account any time from the app

Download PakBazar and start buying and selling today. Pakistan ka apna online
bazaar. 🇵🇰

## Category & contact
- Category: **Shopping** · Email: **ahmednawaz993@gmail.com**
- Privacy policy: **https://pakbazar24.com/privacy.html**

---

# Data Safety form — answer sheet
Collects user data: **Yes** · Encrypted in transit: **Yes** · Users can request deletion: **Yes**
(in-app: Profile → Delete my account; web: https://pakbazar24.com/delete-account.html)
Data shared with third parties: **No** (Firebase/Google is a service provider; no ad SDKs).

| Category → Data type | Collected | Req/Opt | Purpose |
|---|---|---|---|
| Personal → Name | Yes | Optional | Account, listings |
| Personal → Email | Yes | Optional | Account / sign-in |
| Personal → Phone number | Yes | Optional | Account, OTP login, buyer/seller contact |
| Personal → Other (CNIC/ID + selfie) | Yes | Optional | Identity verification, fraud prevention |
| Location → Approximate & Precise | Yes | Optional (on permission) | Show nearby ads, tag listings |
| Photos → Photos | Yes | Optional | Listing & profile/store images |
| Messages → In-app messages | Yes | Required for chat | Buyer/seller chat |
| App activity → User content (listings, favourites, saved searches, reviews, orders) | Yes | Optional | Core app function |
| Device IDs → Device ID (FCM push token) | Yes | Optional | Push notifications |

Mark NOT collected: Health, Web history, Contacts, Calendar, SMS/Call logs, Audio recordings stored, Files, Installed apps, **Financial info** (no payments/wallet in this build).

---

# Submission steps (Play Console)

1. **Create the app** — name "PakBazar", English, App, Free, accept declarations.
2. **Store listing** — paste name/descriptions; upload icon (512), feature graphic (1024×500), 3 screenshots.
3. **App content:**
   - Privacy policy: `https://pakbazar24.com/privacy.html`
   - App access: *"Browse with 'Continue as Guest'. To test posting/chat/offers, sign up with any email + password, or phone sign-in with OTP."*
   - Ads: **No** · Content rating: fill questionnaire (has chat) · Target audience: **18+**
   - Data safety: use the sheet above · Financial features: **No** (wallet hidden)
4. **Release → Testing → Internal testing → Create release** — upload `app-release.aab`, enrol in **Play App Signing**, add testers, roll out. Promote to Production after testing.

## ⚠️ Phone-OTP login after Play App Signing
This app's upload-key SHA-1/256 are already in Firebase, so OTP works via the
upload key. **After you enrol in Play App Signing**, Google re-signs with its own
key — copy Play Console → Setup → **App signing** → SHA-1 & SHA-256 and add them
to the Firebase app (`com.pakbazar24.app`), or phone login breaks in the store build.

Upload-key fingerprints (already added to Firebase):
- SHA-1: `02:64:0C:9E:C0:D4:87:E7:22:BA:73:FA:60:A5:1B:26:1A:00:7F:5A`
- SHA-256: `2C:10:3B:4E:75:3D:71:59:47:C4:73:4E:31:22:B6:AC:8A:8B:D6:94:A9:11:C6:A8:F4:9F:DC:5B:24:04:98:47`

## Automated updates (release #2 onward)
See `scripts/play_upload.py` and `scripts/PLAY_UPLOAD_SETUP.md`.
