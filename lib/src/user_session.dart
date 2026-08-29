part of '../main.dart';

// The signed-in user's own state, held once instead of watched continuously.
//
// WHY THIS EXISTS. The Firestore SDK multiplexes every listener a client has
// over ONE connection, and Firestore allows one million concurrent connections
// per database. So the number that decides whether a million people can use
// this app at once is not how many listeners each of them has — it is whether
// they have ANY. One listener and twenty cost the same connection; zero costs
// none.
//
// The home screen held four, permanently, for the whole time the app was open:
//
//   * the user's own document, to decide whether to show a "verify your ID"
//     banner — a fact that changes at most once in a person's lifetime;
//   * their recently-viewed ads, which only ever change because THEY looked at
//     something, in this app, a moment ago;
//   * the sellers they follow, likewise;
//   * their unread notification count, for a badge.
//
// None of that needs a live socket. Every one of those changes either because
// the user themselves did something — in which case the app already knows — or
// because something happened server-side, in which case a push notification is
// already being sent. So this reads them once and refreshes on a SIGNAL:
// launch, app resume, a push arriving, or the user's own action.
//
// WHAT THIS IS NOT. It is not a cache in front of the database for everything.
// Chat messages in an open conversation stay on a live listener, because
// waiting for a signal to see a reply is exactly the thing a chat may not do.
// This is for state that is read far more often than it changes.

/// The signed-in user's session state.
///
/// A [ChangeNotifier] rather than a stream, so widgets rebuild the same way
/// they did under StreamBuilder — the ergonomics are unchanged, the connection
/// is gone.
class UserSession extends ChangeNotifier {
  UserSession._();

  static final UserSession instance = UserSession._();

  /// The user's own document. Null until the first load finishes.
  Map<String, dynamic>? profile;

  /// Ads this user looked at recently.
  List<Listing> recentlyViewed = const [];

  /// The newest ads from sellers this user follows.
  List<Listing> followingAds = const [];

  /// Unread notifications, for the badge. Counted, not downloaded.
  int unread = 0;

  /// True once a load has completed, so a widget can tell "nothing yet" from
  /// "nothing to show".
  bool loaded = false;

  bool _loading = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Drops everything on sign-out, so the next person to use this device does
  /// not briefly see the last person's ads.
  void clear() {
    // A shared phone must not show one person's browsing to the next.
    unawaited(clearCachedRecentlyViewed());
    profile = null;
    _social = null;
    recentlyViewed = const [];
    followingAds = const [];
    unread = 0;
    loaded = false;
    notifyListeners();
  }

  /// Reads the whole session.
  ///
  /// Everything in parallel: this runs on launch and on every resume, and four
  /// sequential round trips would be four times the wait on a slow connection
  /// for no reason.
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) {
      clear();
      return;
    }
    // A second refresh while one is in flight is a wasted read, and resume can
    // fire twice in quick succession.
    if (_loading) return;
    _loading = true;
    try {
      await Future.wait([
        _loadProfile(uid),
        _loadSocial(uid),
        _loadRecentlyViewed(uid),
        _loadFollowing(uid),
        _loadUnread(uid),
      ]);
      loaded = true;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      profile = doc.data();
    } catch (_) {
      // Leave whatever was there. A failed refresh must not blank a banner
      // decision and make a verified user look unverified.
    }
  }

  Future<void> _loadSocial(String uid) async {
    try {
      final doc = await privateSocialRef(uid).get();
      _social = doc.data();
    } catch (_) {}
  }

  /// Continue Browsing, from the device.
  ///
  /// This is a list of ads THIS user opened on THIS phone moments ago, so the
  /// phone already has all of them — asking a database what it just did cost
  /// ten document reads on every launch and every resume. The Firestore copy
  /// is still written and is still what carries the rail to another device;
  /// it is read only when the local list is empty, which is a fresh install.
  Future<void> _loadRecentlyViewed(String uid) async {
    final local = await loadCachedRecentlyViewed();
    if (local.isNotEmpty) {
      recentlyViewed = local;
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('recentlyViewed')
          .orderBy('viewedAt', descending: true)
          .limit(kRecentlyViewedCap)
          .get();
      recentlyViewed = snap.docs.map(Listing.fromDoc).toList();
      // Seeded, so this device never pays for it again.
      await seedCachedRecentlyViewed(recentlyViewed);
    } catch (_) {}
  }

  /// The follow list, mirrored as a list of ids so the rail does not have to
  /// read thirty subcollection documents on every launch and every resume.
  ///
  /// KEPT IN users/{uid}/private/social, NOT ON THE PROFILE DOCUMENT. The
  /// profile is readable by any signed-in user — seller pages need the name
  /// and rating — while `following` is deliberately owner-only, described in
  /// the rules as "their own private list". Mirroring the ids onto the profile
  /// would have published who everybody follows to every signed-in account,
  /// and it would have done it silently, because a denormalised copy inherits
  /// the permissions of where you PUT it, not of where it came from.
  ///
  /// The subcollection stays the source of truth — it carries the seller names
  /// and timestamps the Following screen shows — and this is a copy of just
  /// the ids, written in the same batch as the follow itself.
  static const String kFollowingIdsField = 'followingIds';

  /// The owner-only document the mirror lives in.
  static DocumentReference<Map<String, dynamic>> privateSocialRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('social');

  /// The private half of the session, read alongside the profile.
  Map<String, dynamic>? _social;

  /// Firestore's `whereIn` accepts at most thirty values, which is the real
  /// reason the rail looks at thirty sellers and not a hundred.
  static const int maxFollowsQueried = 30;

  /// How long the followed-sellers rail may go without re-checking.
  ///
  /// It changes when somebody you follow posts an ad, which is not something
  /// that needs noticing within seconds. Without this, every resume — every
  /// glance at the phone — paid for the rail again.
  static const Duration _followingTtl = Duration(minutes: 10);

  DateTime? _followingLoadedAt;

  Future<void> _loadFollowing(String uid, {bool force = false}) async {
    if (!force &&
        _followingLoadedAt != null &&
        DateTime.now().difference(_followingLoadedAt!) < _followingTtl) {
      return;
    }
    try {
      final ids = await _followedSellerIds(uid);
      if (ids.isEmpty) {
        followingAds = const [];
        _followingLoadedAt = DateTime.now();
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .where('userId', whereIn: ids)
          .where('approvalStatus', isEqualTo: 'approved')
          // Newest first IN THE QUERY, so twelve documents are twelve reads.
          // This used to fetch forty and sort them on the phone to show twelve.
          .orderBy('createdAt', descending: true)
          .limit(12)
          .get();
      followingAds = snap.docs.map(Listing.fromDoc).toList();
      _followingLoadedAt = DateTime.now();
    } catch (_) {}
  }

  /// The sellers this user follows: free when the profile carries them, and
  /// backfilled the one time it does not.
  Future<List<String>> _followedSellerIds(String uid) async {
    final cached = _social?[kFollowingIdsField];
    if (cached is List) return followedIdsFrom(cached);

    // Accounts that predate the field. Read the subcollection once, then write
    // the ids onto the profile so this user never pays for it again.
    final follows = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('following')
        .orderBy('createdAt', descending: true)
        .limit(maxFollowsQueried)
        .get();
    // Oldest first, to match the order arrayUnion will keep it in from here.
    final ids = follows.docs.map((d) => d.id).toList().reversed.toList();
    _social = {...?_social, kFollowingIdsField: ids};
    try {
      await privateSocialRef(
        uid,
      ).set({kFollowingIdsField: ids}, SetOptions(merge: true));
    } catch (_) {
      // Backfill is an optimisation. Failing it costs this user the thirty
      // reads again next time; it must never cost them the rail.
    }
    return ids;
  }

  Future<void> _loadUnread(String uid) async {
    try {
      // count(), so a user who has ignored the bell for a month costs one read
      // rather than three hundred.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .count()
          .get();
      unread = snap.count ?? 0;
    } catch (_) {}
  }

  /// Refreshes just the badge. Cheap enough to call whenever a push arrives or
  /// the notification screen is left.
  Future<void> refreshUnread() async {
    final uid = _uid;
    if (uid == null) return;
    await _loadUnread(uid);
    notifyListeners();
  }

  /// Refreshes just the Continue Browsing rail, after this user opens an ad —
  /// the one moment it can change.
  Future<void> refreshRecentlyViewed() async {
    final uid = _uid;
    if (uid == null) return;
    await _loadRecentlyViewed(uid);
    notifyListeners();
  }

  /// Records a follow or unfollow the user just made, and reloads the rail.
  ///
  /// The id list is mirrored on the profile document, and the copy held here
  /// was fetched before the change — so without this the rail would rebuild
  /// from a list that does not yet include the seller the user just followed,
  /// and following somebody would appear to do nothing.
  Future<void> noteFollowChange(String sellerId, {required bool following}) async {
    final current = (_social?[kFollowingIdsField] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    current.remove(sellerId);
    if (following) current.add(sellerId); // newest at the end, as arrayUnion
    _social = {...?_social, kFollowingIdsField: current};
    await refreshFollowing();
  }

  /// Refreshes just the followed-sellers rail, after the user follows or
  /// unfollows somebody — the one moment it can change.
  Future<void> refreshFollowing() async {
    final uid = _uid;
    if (uid == null) return;
    // Forced: the user just followed somebody and expects to see it.
    await _loadFollowing(uid, force: true);
    notifyListeners();
  }
}

/// The sellers to ask about, out of the raw `followingIds` array.
///
/// Pure, and tested, because the trimming is where this quietly goes wrong:
/// Firestore's `whereIn` takes at most thirty values and REJECTS a longer list
/// outright, so a user who follows thirty-one sellers would get no rail at all
/// rather than a shorter one. Taking from the wrong end is the other failure —
/// arrayUnion appends, so the recent follows are at the TAIL, and trimming the
/// front would show somebody the thirty sellers they cared about least.
List<String> followedIdsFrom(
  List<Object?> raw, {
  int max = UserSession.maxFollowsQueried,
}) {
  final ids = <String>[];
  for (final e in raw) {
    final id = e?.toString() ?? '';
    // Duplicates would waste slots in a list capped at thirty.
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return ids.length <= max ? ids : ids.sublist(ids.length - max);
}

/// Shorthand, because this is referenced from several screens.
UserSession get userSession => UserSession.instance;
