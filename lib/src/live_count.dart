part of '../main.dart';

// Counting things without downloading them.
//
// The app had seven places that rendered a number like this:
//
//     StreamBuilder(
//       stream: userRef.collection('followers').snapshots(),
//       builder: (c, s) => Text('${s.data?.docs.length ?? 0}'),
//     )
//
// which fetches every follower document, live, in order to display how many
// there are. A seller with fifty thousand followers downloads fifty thousand
// documents to draw the word "50,000" — and downloads them again every time
// anybody follows or unfollows. The admin dashboard did the same thing over
// the whole users, listings and offers collections at once.
//
// Firestore has an aggregation for this. `count()` is answered from the index
// and billed at one read per thousand entries matched, so a million users cost
// a thousand reads instead of a million, and the answer arrives in one round
// trip instead of a million documents' worth of them.
//
// WHAT IT GIVES UP, deliberately: an aggregation cannot be watched, so the
// number does not tick up on its own. That is the right trade for a count —
// nobody needs their follower total to animate, and the alternative costs a
// user their mobile data. Pass a new [refreshKey] to re-read it.

/// A count read from Firestore's aggregation index rather than from the
/// documents themselves.
///
/// [builder] receives null while the count is in flight, so a caller can show
/// a placeholder rather than a misleading zero.
class CountBuilder extends StatefulWidget {
  const CountBuilder({
    super.key,
    required this.query,
    required this.builder,
    this.refreshKey,
  });

  final Query<Object?> query;
  final Widget Function(BuildContext context, int? count) builder;

  /// Change this to re-read. Counts do not update themselves.
  final Object? refreshKey;

  @override
  State<CountBuilder> createState() => _CountBuilderState();
}

class _CountBuilderState extends State<CountBuilder> {
  int? _count;
  Object? _key;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CountBuilder old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey) _load();
  }

  Future<void> _load() async {
    final key = Object();
    _key = key;
    try {
      final snap = await widget.query.count().get();
      // A slow answer for a query the user has already navigated away from
      // must not overwrite a newer one.
      if (mounted && identical(_key, key)) {
        setState(() => _count = snap.count ?? 0);
      }
    } catch (_) {
      // A count is decoration. Failing to read one must never take a screen
      // down with it — the placeholder simply stays.
      if (mounted && identical(_key, key)) setState(() => _count = null);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _count);
}

/// How many rows a personal list ("my ads", "my orders") loads at once.
///
/// These lists used to be unbounded live queries: every ad you have ever
/// posted, every order you have ever had, re-sent whenever any one of them
/// changed. That is invisible at fifty and ruinous at fifty thousand — and the
/// person it is ruinous for is your most successful seller, on their phone.
///
/// Two hundred is far past what anybody scrolls, and the screens say so when
/// they hit it.
const int kMyListCap = 200;

/// How many rows an admin list loads at once.
///
/// Higher than a personal list because the operator is working through a
/// queue, and still a cap: the admin panel is what you use to run the business
/// when something is wrong, so it is the last screen that may become unusable
/// as the business grows.
const int kAdminListCap = 300;
