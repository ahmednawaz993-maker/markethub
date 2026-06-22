# PakBazar — Google Play listing & submission pack

## Assets (already in this folder / repo)
- App icon 512×512: `store_assets/icon_512.png` (or `web/icons/Icon-512.png`)
- Feature graphic 1024×500: `store_assets/feature_1024x500.png`
- Phone screenshots: `screenshot_home.png`, `screenshot_detail.png`, `screenshot_chat.png` (add 1–2 more if you can; Play allows up to 8)
- Release bundle: `build/app/outputs/bundle/release/app-release.aab`
- Privacy policy URL: https://markethub-80276.web.app/privacy.html
- Terms URL: https://markethub-80276.web.app/terms.html

## App name (max 30)
PakBazar – Buy & Sell

## Short description (max 80)
Buy & sell cars, property, mobiles & more across Pakistan. Free classifieds.

## Full description (max 4000)
PakBazar is Pakistan's free marketplace to buy and sell almost anything — cars, property, mobile phones, electronics, furniture, fashion, jobs, services and more. Post your ad in minutes and reach buyers across the country.

WHY PAKBAZAR
• 100% free to post ads
• Buy & sell across 280+ cities in Pakistan
• All prices in Pakistani Rupees (Rs)
• Chat with buyers and sellers in real time
• Verified members — sign in with email or phone (OTP)
• Save your favourite ads and searches

EXPLORE EVERYTHING
Motors • Property • Mobiles & Tablets • Electronics • Home & Furniture • Men & Women Essentials • Kids • Jobs • Services • Pets • Sports & Hobbies • Business & Industrial — all in one app.

POST AN AD IN MINUTES
Add multiple photos, set your price, choose your city or attach your exact GPS location, and submit. Every ad is quickly reviewed before it goes live to keep PakBazar safe. Boost your ad to "Featured" to get more views and sell faster.

SAFE & TRUSTED
• Identity & address verification for members
• Secure in-app escrow — we hold payment until the buyer confirms receipt
• Cash on Delivery available on supported ads
• 5-star ratings & reviews for buyers and sellers
• Saved-search alerts when a matching new ad is posted
• Report or block bad actors; our team moderates the marketplace
• Built-in safety tips and scam warnings in chat

Whether you're upgrading your phone, selling your car, renting an apartment, or hunting for a great deal, PakBazar connects you with real buyers and sellers near you.

Download PakBazar and start buying and selling today — Pakistan ka apna bazaar, ab aapke phone par!

Privacy policy: https://markethub-80276.web.app/privacy.html

---

# Data Safety form — answer sheet

## Overview answers
- Does your app collect or share any required user data types? **Yes (collects)**
- Is all of the user data collected by your app encrypted in transit? **Yes** (HTTPS / Firebase)
- Do you provide a way for users to request that their data is deleted? **Yes** (in-app: edit profile, delete ads; plus account-deletion request via the contact email in the privacy policy)

## Data types — declare COLLECTED (nothing "shared"; Firebase/Google is a service provider, not third-party sharing)
For every row: Shared = **No**, Encrypted in transit = **Yes**.

| Category → Data type | Collected | Required/Optional | Purpose |
|---|---|---|---|
| Personal info → **Email address** | Yes | Optional (guests/phone users may not provide) | Account management |
| Personal info → **Phone number** | Yes | Optional | Account management + App functionality (login by OTP; shown on the seller's own ad) |
| Personal info → **Name** (display/business name) | Yes | Optional | App functionality, Account management |
| Personal info → **Address** | Yes | Optional | App functionality, Fraud prevention (address verification) |
| Personal info → **Other info** (CNIC / ID document + selfie) | Yes | Optional | Identity verification, Fraud prevention & compliance |
| Financial info → **Purchase history** (orders, wallet top-ups, escrow) | Yes | Optional | App functionality |
| Financial info → **Other financial info** (seller payout account for withdrawals) | Yes | Optional | App functionality |
| Location → **Approximate location** | Yes | Optional | App functionality (ad location) |
| Location → **Precise location** | Yes | Optional (only when the user grants permission) | App functionality |
| Photos and videos → **Photos** | Yes | Optional | App functionality (listing & verification images) |
| Messages → **Other in-app messages** | Yes | Required (to use chat) | App functionality |
| App activity → **Other user-generated content** (listings, favourites, saved searches, reviews) | Yes | Optional | App functionality |
| Device or other IDs → **Device or other IDs** (FCM push token) | Yes | Optional | App functionality (push notifications) |

Note: full card/bank numbers are NOT stored by the app — payments are manual or handled by a payment provider.

## Data types to mark NOT collected
Health & fitness, Web browsing history, Contacts, Calendar, SMS/Call logs, Audio, Files/Docs, Installed apps.

## App access (for reviewers) — IMPORTANT
Core features (posting, buying, offers, chat) require identity verification that an admin approves, so create a ready-to-use review account and enter it under Play Console → App content → App access:
- Provide a **pre-verified test account** (email + password) that is already `idVerified` in Firestore so reviewers can post/buy/chat, OR
- Note: "Tap **Continue as Guest** on the welcome screen to browse the full marketplace without an account."

## Content rating questionnaire
- Category: Social / Shopping (classifieds). No violence, sexual content, gambling, or drugs.
- Expected result: **Everyone** / PEGI 3.

## Target audience & ads
- Target age: **18+** (it's a marketplace with transactions).
- Does your app contain ads? **No.**

---

# Submission steps (Play Console)

1. **Firebase first (for Android phone-auth):** Firebase Console → Project Settings → your Android app (`com.pakbazaar.app`) → Add fingerprint:
   - SHA-1: `02:64:0C:9E:C0:D4:87:E7:22:BA:73:FA:60:A5:1B:26:1A:00:7F:5A`
   - SHA-256: `2C:10:3B:4E:75:3D:71:59:47:C4:73:4E:31:22:B6:AC:8A:8B:D6:94:A9:11:C6:A8:F4:9F:DC:5B:24:04:98:47`
2. **Create the app** in Play Console (app name, default language English, App not Game, Free).
3. **Store listing:** paste app name, short & full description; upload icon (512), feature graphic (1024×500), and the 3 phone screenshots.
4. **Upload the AAB:** Production (or Internal testing first) → Create release → upload `app-release.aab` → enrol in **Play App Signing** (recommended).
5. **After Play App Signing enrols:** copy Play's **app-signing SHA-1 & SHA-256** (Play Console → Setup → App signing) and add them to Firebase too — otherwise phone-auth breaks in the published build.
6. **App content:** Privacy policy URL, App access (test account above), Ads = No, Content rating questionnaire, Target audience (18+), Data safety (use the sheet above), Government apps = No, Financial features (declare in-app digital purchases / escrow if asked).
7. **Review & roll out.** Consider **Internal testing** first to verify the signed build + phone-auth on a real device before Production.

## Recommended: test with Internal testing before Production
Upload to Internal testing, add your own email as a tester, install from the Play link, and confirm: login (email + phone OTP), post an ad (admin approve → goes live), chat, and escrow flow all work on the signed build.
