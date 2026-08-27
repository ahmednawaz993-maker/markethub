# Changelog

User-visible changes to PakBazar, newest first. Versions match the `version:`
field in `pubspec.yaml` (the versionName users see); the Play versionCode is
auto-incremented by CI on every build, so it is not tracked here.

This file starts at 1.0.46 — earlier history lives in the git log.

Deploy topology matters when reading these entries: a push to `main` ships the
app and `firestore.rules`/`firestore.indexes.json`. Storage rules, Cloud
Functions and the website are deployed by hand, so backend items are marked
with where they landed.

## [1.0.64] — 2026-08-27

### Added

- **Three ways to play Ludo.** Pick one when you start a game:
  - **Classic** — four tokens each, bring all four home. The full game.
  - **Quick** — two tokens each. A genuinely shorter game, not a timer that
    cuts play off and awards it on points.
  - **Master** — four tokens, but you must send an opponent home before any of
    your tokens can enter your home column. It stops anyone racing round
    untouched.
- **Sound.** The dice rattles, tokens tick as they walk, a capture thuds, and
  there is a short fanfare when someone wins. Sound is **off until you turn it
  on** with the speaker button — the app never starts making noise on its own.

## [1.0.63] — 2026-08-27

### Fixed

- **The Ludo dice now works on the website.** Rolling failed with an
  "Int64 accessor not supported" error: the way the app asked the server to
  roll cannot be used from a browser. It now asks in a way that works
  identically on the website, Android and iOS.

## [1.0.62] — 2026-08-27

### Fixed

- **Older app versions could not roll the Ludo dice at all.** The dice moved to
  the server so nobody can fake a six, but apps installed before that update
  still tried to roll on the phone — and the server refused, silently. The
  board then played the turn by itself after 45 seconds, which looked like the
  dice was dead and the game was moving on its own. Those versions now say so
  and ask you to update, instead of leaving you with a board that plays itself.
- **You can now see how long is left on a turn.** A turn is played
  automatically if nobody acts, and that used to happen with no warning. The
  countdown appears on your own turn once it is close, and on someone else's
  turn while you wait.

## [1.0.61] — 2026-08-27

### Fixed

- **The Ludo dice could stop working entirely.** If you left the game screen,
  switched apps, or the screen simply redrew after rolling, the board stopped
  offering tokens to move — and rolling again was refused because a roll was
  already waiting. The game was stuck for everyone at the table with no way
  out. The roll now lives with the game itself, so it survives leaving and
  coming back.
- **Everyone at the table now sees the dice.** Previously only the player who
  rolled could see what they got.

### Changed

- **A forced move plays itself.** When your roll leaves only one possible move,
  the app plays it instead of making you tap — there is no decision to make,
  and waiting for the tap only slows the table down.

## [1.0.60] — 2026-08-27

### Changed

- **Ludo pieces now move across the board instead of jumping.** A token walks
  square by square, so a six visibly takes longer than a one, and it lifts
  slightly as it travels the way a piece does when you pick it up. A captured
  token flies back to its yard. Every move animates the same way — your own,
  your opponent's, and the computer's.
- **The dice tumbles before it settles.** It rolls for exactly as long as the
  game is waiting on the result, so on a slow connection it keeps turning
  rather than sitting frozen. The face is drawn with real pips rather than a
  number. Tap the dice to roll.

## [1.0.59] — 2026-08-27

### Fixed

- **A Ludo game no longer freezes when somebody leaves.** If a player closed
  the app mid-turn, the board stopped for everyone else permanently — nothing
  on the remaining players' phones could move it on. Their turn is now played
  automatically after 45 seconds, so a game always finishes.

### Added

- **Play Ludo against the computer.** Add one to three computer players to any
  game, so you can play on your own or fill an empty seat. They take a capture
  when one is there, bring tokens home, and open the yard on a six.

## [1.0.58] — 2026-08-27

### Security

- **The Ludo dice is now rolled by the server, not the phone.** Previously the
  app generated its own number, so a modified copy of the app could simply
  claim a six every turn. The roll now happens on PakBazar's servers with a
  cryptographic random number, and the rules refuse any dice value written by a
  player's device. Rolling again before playing your last roll is refused too,
  so nobody can keep rolling until a six turns up.

## [1.0.57] — 2026-08-27

### Added

- **Ludo, with chat at the table.** Start a game, share it, and up to four
  people play on one board in real time — with a chat panel so the table can
  talk while they play. Two, three or four players; the seats decide who is in
  the game. Under **Menu → Games**.

  The rules are the ones people actually play in Pakistan: a six to leave the
  yard, another turn for a six, a capture or getting a token home, three sixes
  in a row forfeits the turn, eight safe squares, and an exact roll needed to
  come home.

  A game lives in a single record that every player watches, so moves appear
  immediately for everyone. The security rules only accept a move from the
  player whose turn it actually is, so nobody can play out of turn or move
  somebody else's token.

## [1.0.56] — 2026-08-27

### Added

- **Prayer timings.** Namaz times for 40 Pakistani cities, with the next prayer
  and a countdown to it. Calculated on the phone from the sun's position using
  the University of Islamic Sciences, Karachi method (Fajr and Isha at 18°),
  which is the convention Pakistani mosques publish against. Asr can be set to
  Hanafi or Shafi'i — the two differ by up to an hour, so it is a choice rather
  than a buried default.

  It needs no internet at all, which is the point: a prayer schedule that
  requires a signal is useless exactly when people reach for it.

- **The Quran with Urdu translation.** All 114 surahs and 6,236 ayahs, bundled
  inside the app so it works offline. Arabic in Uthmani script with the Urdu
  translation of Maulana Muhammad Junagarhi — the plain rendering used in the
  Saudi-printed Urdu mushaf and the one most widely read in Pakistan. Search by
  surah name or number, copy any ayah, and the app remembers where you were.

  Both are under **Menu → Namaz & Quran**.

## [1.0.55] — 2026-08-26

### Changed

- **Text now follows one type scale.** The app was using 27 different font
  sizes, including pairs nobody can tell apart — 11 and 11.5, 17 and 18, 12 and
  12.5. Steps that look identical aren't a scale, they're noise, and noise is
  what makes typography feel unconsidered. It's now 13 sizes, and no piece of
  text moves by more than 2px.

  The caption style moved from 11.5 to 11, because 47 places had independently
  settled on 11 and only 7 on 11.5 — the scale followed what the app was
  actually doing rather than the other way round.

### Fixed

- **Two cards were reserving the wrong amount of height for their own text.**
  The listing card and the featured banner each computed their height from
  copied numbers that had drifted from the sizes they actually render. Both now
  read the real values, so the "this card can never overflow" guarantee can't
  quietly rot when the type scale moves.

  Doing that surfaced a genuine latent bug: both were summing ideal line
  heights, while the text painter rounds each line up to whole pixels
  independently — leaving them a fraction of a pixel short of what paints. They
  now round the same way the painter does.

## [1.0.54] — 2026-08-26

### Changed

- **Card and panel padding is now consistent app-wide.** Thirty containers sat
  one step off the spacing scale — 10px and 14px where the app uses 12 and 16 —
  which is the kind of 2px-at-a-time drift that makes screens feel slightly
  unaligned without anything looking obviously wrong. Order cards, chat, the
  admin panel, refunds, returns, cancellations, payouts and support all move
  onto the scale.

  Thirteen insets stay as they are, on purpose: nine size a glyph inside a
  circle or square (the verified badge, the favourite button, the fullscreen
  control) where the ruler is optical, not rhythmic, and four are whitespace
  around a lone spinner with nothing near them to align to.

## [1.0.53] — 2026-08-26

### Changed

- **Corner radii are now consistent across the whole app.** Every rounded
  corner ran through one of six hand-typed numbers; 23 of them were off the
  design scale entirely, which is the kind of inconsistency you feel without
  being able to point at it. All 67 now use a token, and a test fails the build
  if a raw number comes back.

  The radius scale gained a 4 step — three screens were already using a bare 4
  for colour swatches and small thumbnails, so the gap was in the scale rather
  than in them. Those keep their exact pixels. Twenty small badges and
  thumbnails move by 2px (6→8, 10→12); nothing else changes, because a corner
  radius affects only how a corner is painted, never how much room anything
  takes.

- **134 spacing and radius values now read from the design system** instead of
  repeating a number. Every one of those was verified to be numerically
  identical to the token replacing it, so not a single pixel moved — this buys
  no new polish today, it stops the polish drifting apart tomorrow.

## [1.0.52] — 2026-08-26

### Changed

- **Listing cards now lift off the page.** The hairline border is replaced by a
  soft shadow, so on a busy grid the cards read as separate objects you can tap
  rather than as one mesh of boxes. Geometry is untouched — same corner radius,
  same height — so nothing reflows and the card keeps its guarantee that it can
  never overflow.

  Dark mode deliberately keeps the hairline and spends nothing on a shadow: a
  shade cast on a near-black ground is invisible, and there the separation
  already comes from the card surface being lighter than the page. Exactly one
  of the two mechanisms is active in either theme, and a test pins that.

  The loading skeleton was updated to match, so a card no longer visibly
  changes shape when its data arrives.

## [1.0.51] — 2026-08-26

### Fixed

- **Admin "Delete ad" destroyed a seller's live listing on a single tap.** The
  Reports queue deleted the ad and the report outright with no confirmation and
  nothing to restore from. It now states the consequence first — including that
  the seller is never told why — and suggests opening the ad before acting.
  "Dismiss" confirms too.
- **Deleting an ad draft asked nothing.** The delete icon sits next to the row's
  own tap target, so a mis-tap threw away a half-written ad permanently.
- **The business activity card re-queried Firestore on every rebuild.** Its two
  aggregate count queries were issued inline in `build()`, so scrolling the
  Business tab re-ran them continuously — billable reads, and the row flickering
  back to "Loading activity…" each time. They now run once per card.

## [1.0.50] — 2026-08-20

### Changed

- **Feedback now requires a verified account.** Sending help requests and
  suggestions carries the same identity bar as posting or buying, and respects
  the same platform-wide "Require ID & face verification" switch — with that
  switch off, everyone can still write in. Suspended users are deliberately
  still allowed to send feedback, so nobody loses their route to support over a
  suspension they want to appeal.
- **Sending feedback no longer claims success when it failed.** The write error
  was swallowed and the app said "sent to our team" regardless, so a rejected
  message looked exactly like a delivered one and the user waited for a reply
  that could never come.

### Added

- **Admins can reply to feedback in-app.** The reply is recorded on the message
  — with who sent it and when — and delivered to the user's notifications, so
  both sides can see it was answered. Feedback now moves through
  open → replied → resolved, with filter chips and counts, and a resolved item
  can be re-opened.
- **Every message shows who wrote it.** Name, ID-verified / suspended /
  business standing, how long they have been a member, email, and phone with
  one-tap WhatsApp, call and email. Previously the queue showed an email
  address and nothing else.

### Fixed

- **Review-prompt feedback was near-invisible in the admin queue.** It wrote
  `userEmail` with no type or status, so those messages showed a blank sender
  and could not be filtered or resolved. They now use the same shape as the
  Help & Feedback sheet, and the admin panel reads either schema so the
  existing backlog displays correctly too.
- **The new feedback card overflowed on a phone** — up to 154px at 320px wide
  with large text, across the header, the action buttons and the contact row.
  Caught by new layout tests before release.

## [1.0.49] — 2026-08-20

### Changed

- **Updated the Firebase SDKs**, led by `firebase_messaging` 16.4.0 → 16.5.0.
  Play Vitals showed three separate ANR clusters inside the messaging plugin's
  own broadcast receiver (`c2dm.intent.RECEIVE`) on budget Android devices —
  there is no app code in that path, so the plugin update is the fix available
  to us.

  16.5.0 requires `firebase_core` 4.13.0, so the whole FlutterFire stack moved
  with it: `cloud_firestore` 6.5.0 → 6.8.0, `firebase_auth` 6.5.2 → 6.5.7,
  `firebase_storage` 13.4.2 → 13.4.6, `firebase_crashlytics` 5.2.4 → 5.2.7,
  `firebase_analytics` 12.4.3 → 12.4.6, and `firebase_core_platform_interface`
  7.1.0 → 8.1.0 (a major bump). No app code changed.

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
