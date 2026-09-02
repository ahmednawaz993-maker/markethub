part of '../main.dart';

// ---------------------------------------------------------------------------
// Paged listing loading.
//
// Every listing surface used to open a fixed window and never grow: the home
// feed stopped dead at 60 ads, Browse pulled 1000 documents on every open and
// filtered them in Dart. Both were hard ceilings — past them, ads were simply
// invisible, with nothing in the UI to say so — and the 1000-document read ran
// on every session, which is the single largest read cost in the app.
//
// This loads a query one page at a time and appends, so a list grows as the
// user scrolls and costs one page of reads instead of a thousand documents.
// ---------------------------------------------------------------------------

/// Documents fetched per page. Large enough that a phone screen fills in one
/// round trip, small enough that the first paint is cheap.
const int kListingPageSize = 30;

/// Loads a listings [Query] page by page, appending into [items].
///
/// A [clientFilter] may reject documents after they are fetched — that is how
/// text search and the local filters keep working without a search index. When
/// a filter is present a single `loadMore()` may fetch SEVERAL pages, because
/// one page of results can contain no matches at all; without that, a search
/// whose hits live deep in the catalogue would look empty until the user
/// scrolled far enough, which is worse than the wide window it replaces.
class PagedListings extends ChangeNotifier {
  PagedListings({
    required this.query,
    this.clientFilter,
    this.pageSize = kListingPageSize,
    this.maxPagesPerLoad = 10,
  });

  final Query<Map<String, dynamic>> query;
  final bool Function(Listing)? clientFilter;
  final int pageSize;

  /// Upper bound on pages pulled in one [loadMore] while hunting for matches,
  /// so a search that matches nothing cannot walk the whole collection.
  final int maxPagesPerLoad;

  /// Everything loaded so far, in query order, after [clientFilter].
  final List<Listing> items = <Listing>[];

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _exhausted = false;
  Object? _error;
  int _scanned = 0;

  bool get isLoading => _loading;

  /// False once the underlying query has been walked to its end.
  bool get hasMore => !_exhausted;

  /// Non-null if the last fetch failed. The already-loaded [items] stay valid.
  Object? get error => _error;

  /// Documents examined, including ones the client filter rejected. Lets the UI
  /// distinguish "no ads exist" from "none of the ads matched your search".
  int get scannedCount => _scanned;

  bool get isEmpty => items.isEmpty && !_loading;

  /// Fetches forward until at least one new item is accepted, the query is
  /// exhausted, or [maxPagesPerLoad] pages have been read.
  Future<void> loadMore() async {
    if (_loading || _exhausted) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      var pages = 0;
      var accepted = 0;
      while (!_exhausted && accepted == 0 && pages < maxPagesPerLoad) {
        Query<Map<String, dynamic>> q = query.limit(pageSize);
        if (_cursor != null) q = q.startAfterDocument(_cursor!);

        final snap = await q.get();
        pages++;

        if (snap.docs.isEmpty) {
          _exhausted = true;
          break;
        }
        _cursor = snap.docs.last;
        // A short page means we reached the end of the query.
        if (snap.docs.length < pageSize) _exhausted = true;

        for (final doc in snap.docs) {
          _scanned++;
          final listing = Listing.fromDoc(doc);
          if (clientFilter != null && !clientFilter!(listing)) continue;
          items.add(listing);
          accepted++;
        }
      }
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Discards everything and reloads from the first page. Used by
  /// pull-to-refresh and whenever the filters change.
  Future<void> refresh() async {
    items.clear();
    _cursor = null;
    _exhausted = false;
    _error = null;
    _scanned = 0;
    _loading = false;
    await loadMore();
  }

  @override
  void dispose() {
    items.clear();
    super.dispose();
  }
}

/// Fires [onLoadMore] when the user scrolls near the bottom of a list.
///
/// Wrap a scrollable in this rather than polling a ScrollController from
/// several places; the source itself guards against overlapping loads.
class InfiniteScrollTrigger extends StatelessWidget {
  final Widget child;
  final VoidCallback onLoadMore;

  /// How far from the bottom, in pixels, to start loading the next page.
  final double threshold;

  const InfiniteScrollTrigger({
    super.key,
    required this.child,
    required this.onLoadMore,
    this.threshold = 600,
  });

  @override
  Widget build(BuildContext context) {
    bool nearBottom(ScrollMetrics m) =>
        m.axis == Axis.vertical && m.maxScrollExtent - m.pixels <= threshold;

    // TWO listeners, and the second one is the interesting one.
    //
    // ScrollNotification only arrives when somebody SCROLLS. If a page of
    // results is shorter than the screen there is nothing to scroll, so the
    // next page is never asked for — the list sits at whatever it has, under a
    // count that says "2+ results", above a screenful of nothing. On a young
    // marketplace that is most searches, and it reads as the app being broken
    // rather than as the search being narrow.
    //
    // ScrollMetricsNotification fires when the metrics themselves change —
    // including on first layout and whenever the content grows — so a list
    // that cannot scroll still gets asked. It settles on its own: if a load
    // adds nothing, the metrics do not change and no further notification
    // arrives.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (nearBottom(n.metrics)) onLoadMore();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (nearBottom(n.metrics)) onLoadMore();
          return false;
        },
        child: child,
      ),
    );
  }
}

/// Footer sliver for a paged list: a spinner while loading, a retry on error,
/// and an end-of-results marker once everything has been seen.
class PagedListingFooter extends StatelessWidget {
  final PagedListings source;
  final VoidCallback onRetry;

  const PagedListingFooter({
    super.key,
    required this.source,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (source.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Column(
            children: [
              Text(
                tr('state.loadMoreFailed', 'Could not load more ads.'),
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(tr('action.retry', 'Try again')),
              ),
            ],
          ),
        ),
      );
    }
    if (source.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (!source.hasMore && source.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            tr('state.seenEverything', "You've seen everything"),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.lg);
  }
}
