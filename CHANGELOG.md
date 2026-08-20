# Changelog

User-visible changes to PakBazar, newest first. Versions match the `version:`
field in `pubspec.yaml` (the versionName users see); the Play versionCode is
auto-incremented by CI on every build, so it is not tracked here.

This file starts at 1.0.46 — earlier history lives in the git log.

Deploy topology matters when reading these entries: a push to `main` ships the
app and `firestore.rules`/`firestore.indexes.json`. Storage rules, Cloud
Functions and the website are deployed by hand, so backend items are marked
with where they landed.

## [1.0.48] — 2026-08-20

### Fixed

- **The admin order screen overflowed on a phone.** Its five-step progress
  strip laid the long-form status names ("Ready to dispatch", "Order accepted")
  across a single row, which ran 354 pixels past the edge of a 320px screen —
  508 at large text. The steps now use short names and wrap, so the strip fits
  at any width and text size. Shipped in 1.0.47; caught by new layout tests
  rather than in review.

## [1.0.47] — 2026-08-20

### Fixed

- **Admin panel reset itself while you were using it.** The panel restarted its
  permission load on every rebuild — opening the keyboard on a tab with a text
  field was enough — which dropped it to a spinner, rebuilt every tab and
  bounced you back to the first tab.
- **Staff Panel button came and went.** Staff permissions were cleared before
  each reload rather than after, so during every load a staff member briefly
  looked like they had none: the button disappeared from the Menu and the panel
  could show "No access". A failed read (offline) locked them out for the rest
  of the session. The button also had nothing to rebuild it when grants
  arrived, so on a cold start it stayed hidden until something unrelated
  redrew the Menu.
- **Removing staff no longer deletes on a single tap.** It asks first, and
  points at the "Active" toggle as the reversible option.
- **Re-adding an existing staff email no longer wipes their permissions.**
  "Add staff" merged over the existing record; duplicates are now refused with
  a pointer to "Edit permissions".
- **A typo in a staff email no longer discards the dialog.** The address is
  validated inline instead of after the dialog closes.
- **Verify ID staff can see the documents they are reviewing.** Read access to
  verification images was hard-coded to the owner's account, so anyone else
  granted the Verify ID permission opened the queue to broken image tiles.
  *(storage.rules — deployed 2026-08-16.)*

### Security

- **An approved ID verification can no longer be edited by its owner.**
  Previously the owner could rewrite the selfie, CNIC and address on an
  already-approved record — the rules only required the new status to be
  `pending`, and the `idVerified` badge on the account was never reset by that
  write. A verified account could end up vouching for documents no reviewer had
  seen. Approved records are now frozen for the owner in both the app and the
  rules, and verification images are written to a fresh object per capture so a
  retake cannot overwrite what was approved.
  *(firestore.rules deployed 2026-08-16; storage.rules deployed by hand the
  same day.)*

### Added

- **Admin order management.** Every order is now openable from Admin → Orders
  into a full management screen: buyer and seller with one-tap WhatsApp, call
  and in-app reminder; the delivery address, courier and tracking; the payment
  breakdown; the fulfillment timeline; and a trail of every admin action taken
  on it. Orders the seller has not accepted within 24 hours are flagged, sorted
  into a "Needs action" filter and highlighted in the list, and an admin can
  **accept on the seller's behalf** — the buyer gets the same notification they
  would have got from the seller, and the order is stamped as an admin
  acceptance. Admins can also advance, edit (delivery/tracking only), cancel
  and delete. Money is deliberately untouchable from this screen: amounts,
  commission and payouts stay with the payment backend, cancelling an order
  with a held payment is refused and routed to the refund flow, and deleting
  one requires typing the order number.
- **"Re-open for re-submission"** on approved records in the Verify ID tab, so
  support can start someone's verification over (renewed CNIC, moved house,
  approved by mistake). It clears the badge — spelled out in the confirmation —
  and notifies the user.

> The Fixed and Security items above were merged and deployed on 2026-08-16
> while `pubspec.yaml` still read 1.0.46, so they first reached production in a
> build reporting 1.0.46; 1.0.47 is the first release to carry them under their
> own version number. Rules changes are live independently of app version.

## [1.0.46] — 2026-08-14

### Added

- **Minimum-version gate and maintenance mode**, so a build below the supported
  floor can be told to update, and the app can be put into maintenance from
  `config/appGate` without a release.
