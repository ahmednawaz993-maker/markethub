part of '../main.dart';

// ---------------------------------------------------------------------------
// Deep links.
//
// The app previously declared only MAIN/LAUNCHER and used `home:` with no
// routes, so every pakbazar24.com URL resolved to the same place: the app had
// no addressable content at all. A seller sharing an ad sent the recipient to
// a homepage, and Google had a single URL to index for the whole marketplace —
// which, for a classifieds site, is the primary acquisition channel missing.
//
// Supported:
//   https://pakbazar24.com/ad/{listingId}      (Android App Link + web)
//   https://www.pakbazar24.com/ad/{listingId}
//   pakbazar://ad/{listingId}                  (fallback scheme)
//
// Android hands the path to Flutter because of the flutter_deeplinking_enabled
// meta-data in AndroidManifest.xml; on web the path IS the initial route. Both
// arrive here through MaterialApp.onGenerateRoute.
// ---------------------------------------------------------------------------

/// Extracts a listing id from an incoming route, or null if the route is not
/// a listing link.
///
/// Kept separate from route construction so the parsing — which is where the
/// edge cases live (full URLs vs bare paths, the custom scheme, trailing
/// slashes, query strings, junk) — is testable without a widget tree.
String? listingIdFromRoute(String raw) {
  if (raw.isEmpty || raw == '/') return null;

  // Tolerate a full URL as well as a bare path.
  Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return null;
  }

  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // pakbazar://ad/{id} parses with 'ad' as the HOST, not a path segment.
  if (uri.scheme == 'pakbazar' && uri.host.isNotEmpty) {
    segments = [uri.host, ...segments];
  }

  if (segments.length < 2) return null;
  if (segments.first != 'ad') return null;
  final id = segments[1].trim();
  return id.isEmpty ? null : id;
}

/// The Ludo room id in an invite link, or null.
///
/// Shares the parser above rather than repeating it: the awkward cases — a full
/// URL vs a bare path, the pakbazar:// scheme putting the first segment in the
/// HOST, trailing slashes, query strings — are identical and were already
/// solved once.
///
///   https://pakbazar24.com/ludo/{roomId}
///   pakbazar://ludo/{roomId}
String? ludoRoomIdFromRoute(String raw) => _segmentAfter(raw, 'ludo');

String? _segmentAfter(String raw, String prefix) {
  if (raw.isEmpty || raw == '/') return null;
  Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return null;
  }
  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'pakbazar' && uri.host.isNotEmpty) {
    segments = [uri.host, ...segments];
  }
  if (segments.length < 2 || segments.first != prefix) return null;
  final id = segments[1].trim();
  return id.isEmpty ? null : id;
}

/// A shareable invite to one game. Sent through whatever the player already
/// uses — WhatsApp, Facebook, SMS — rather than requiring anyone to be on a
/// particular social network.
String ludoInviteUrl(String roomId) => 'https://pakbazar24.com/ludo/$roomId';

/// Resolves an incoming route to a screen.
///
/// Returns null for anything unrecognised so MaterialApp falls back to `home`,
/// which is the right behaviour for a stale or malformed link: the user lands
/// in the app rather than on an error.
Route<dynamic>? generateAppRoute(RouteSettings settings) {
  final raw = settings.name ?? '/';

  final roomId = ludoRoomIdFromRoute(raw);
  if (roomId != null) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => LudoInviteScreen(roomId: roomId),
    );
  }

  final id = listingIdFromRoute(raw);
  if (id == null) return null;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => ListingDeepLinkScreen(listingId: id),
  );
}

/// Loads a listing by id, then shows it.
///
/// Deep links carry an id, but AdDetailsScreen needs a full Listing, so this
/// bridges the two. It also has to handle the cases a link inevitably hits:
/// the ad was deleted, was never approved, or the device is offline.
class ListingDeepLinkScreen extends StatefulWidget {
  final String listingId;

  const ListingDeepLinkScreen({super.key, required this.listingId});

  @override
  State<ListingDeepLinkScreen> createState() => _ListingDeepLinkScreenState();
}

class _ListingDeepLinkScreenState extends State<ListingDeepLinkScreen> {
  late Future<Listing?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// True when the ad could not be read because nobody is signed in.
  ///
  /// Listings are readable only by signed-in users, so a shared link opened by
  /// someone without an account fails with permission-denied — NOT a network
  /// error. Telling them to "check your connection" sends them to fix something
  /// that is not broken, which is the worst possible answer for the one visitor
  /// a shared link exists to bring in.
  bool _needsSignIn = false;

  Future<Listing?> _load() async {
    _needsSignIn = false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .get();
      if (!snap.exists) return null;
      return Listing.fromDoc(snap);
    } on FirebaseException catch (e) {
      final signedOut = FirebaseAuth.instance.currentUser == null;
      if (e.code == 'permission-denied' && signedOut) {
        _needsSignIn = true;
        // Remember the ad BEFORE sending them to sign in. This is the front
        // door for anybody arriving from a shared link or from Google, and
        // telling a first-time visitor to go and fetch the link again is the
        // worst possible greeting.
        await rememberPendingAd(widget.listingId);
        return null;
      }
      rethrow;
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SecurityGate(child: AuthGate())),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Listing?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('PakBazar')),
            body: ErrorStateWidget(
              message: 'We could not open this ad. Check your connection and '
                  'try again.',
              onRetry: () => setState(() => _future = _load()),
            ),
          );
        }

        // Signed out. The link is fine and the ad may well be fine — they just
        // cannot be shown it yet. Sending them to the login screen keeps the
        // link's promise instead of blaming their connection.
        if (_needsSignIn) {
          return Scaffold(
            appBar: AppBar(title: const Text('PakBazar')),
            body: EmptyStateWidget(
              icon: Icons.lock_outline,
              title: 'Sign in to view this ad',
              subtitle:
                  'PakBazar shows ads to signed-in users. Sign in or create a '
                  'free account — we will bring you straight back to this ad.',
              actionLabel: 'Sign in',
              onAction: _goHome,
            ),
          );
        }

        final listing = snap.data;
        // Gone, or never publicly visible. A shared link outliving its ad is
        // the normal case on a marketplace, so this is a real destination
        // rather than an error.
        if (listing == null || !listing.isApproved) {
          return Scaffold(
            appBar: AppBar(title: const Text('PakBazar')),
            body: EmptyStateWidget(
              icon: Icons.link_off,
              title: tr('ad.unavailable', 'This ad is no longer available'),
              subtitle: 'It may have been sold or removed by the seller.',
              actionLabel: 'Browse PakBazar',
              onAction: _goHome,
            ),
          );
        }

        return AdDetailsScreen(listing: listing);
      },
    );
  }
}
