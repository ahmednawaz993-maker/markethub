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
    profile = null;
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

  Future<void> _loadRecentlyViewed(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('recentlyViewed')
          .orderBy('viewedAt', descending: true)
          .limit(10)
          .get();
      recentlyViewed = snap.docs.map(Listing.fromDoc).toList();
    } catch (_) {}
  }

  Future<void> _loadFollowing(String uid) async {
    try {
      final follows = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      final ids = follows.docs.map((d) => d.id).toList();
      if (ids.isEmpty) {
        followingAds = const [];
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          // whereIn takes at most 30 values, which is why the follow list above
          // is capped at 30 rather than being a coincidence.
          .where('userId', whereIn: ids)
          .where('approvalStatus', isEqualTo: 'approved')
          .limit(40)
          .get();
      followingAds = snap.docs.map(Listing.fromDoc).toList();
    } catch (_) {}
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

  /// Refreshes just the followed-sellers rail, after the user follows or
  /// unfollows somebody — the one moment it can change.
  Future<void> refreshFollowing() async {
    final uid = _uid;
    if (uid == null) return;
    await _loadFollowing(uid);
    notifyListeners();
  }
}

/// Shorthand, because this is referenced from several screens.
UserSession get userSession => UserSession.instance;
