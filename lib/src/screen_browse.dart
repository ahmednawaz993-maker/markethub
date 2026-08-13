part of '../main.dart';

// Category / search / listings browser and listing cards.

/// Levenshtein edit distance between [a] and [b], capped at [max]: returns a
/// value > [max] as soon as the distance is known to exceed it (cheap early
/// out for typo tolerance, which only cares about small distances).
int _editDistanceCapped(String a, String b, int max) {
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > max) return max + 1;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (i) => i);
  var curr = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= lb; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (curr[j - 1] + 1 < v) v = curr[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1; // whole row already past the cap
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[lb];
}

/// True if [token] is a close typo of any word in [words]. Only applied when a
/// plain substring match failed. Short tokens (<4) are excluded to avoid noisy
/// matches; the allowed distance grows for longer tokens (1 for 4-6 chars, 2
/// for 7+).
bool _fuzzyWordMatch(List<String> words, String token) {
  if (token.length < 4) return false;
  final maxDist = token.length >= 7 ? 2 : 1;
  for (final w in words) {
    if (w.length < 3) continue;
    if ((w.length - token.length).abs() > maxDist) continue;
    if (_editDistanceCapped(token, w, maxDist) <= maxDist) return true;
  }
  return false;
}

class CategoryScreen extends StatelessWidget {
  final String title;

  const CategoryScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListingsBrowser(category: title),
    );
  }
}

class SearchScreen extends StatelessWidget {
  final String initialQuery;
  final String? initialCity;

  const SearchScreen({super.key, this.initialQuery = '', this.initialCity});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListingsBrowser(
        initialQuery: initialQuery,
        initialCity: initialCity,
      ),
    );
  }
}

/// Lists the current user's saved searches, with run + delete. Alerts fire
/// server-side (notifyOnNewListing) when a new ad matches one of these.
class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Searches')),
        body: const EmptyStateWidget(
          icon: Icons.bookmark_border,
          title: 'Log in to see saved searches',
          subtitle: 'Save a search to get alerted on new matching ads.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Searches')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('savedSearches')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorStateWidget(
              message: 'We could not load your saved searches.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.bookmark_border,
              title: 'No saved searches yet',
              subtitle:
                  'Tap the bell while browsing to save a search and get '
                  'alerts on new matching ads.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ListTile(
                  leading: const Icon(Icons.bookmark, color: kPakGreen),
                  title: Text(d['label']?.toString() ?? 'Saved search'),
                  subtitle: const Text('Tap to run · alerts on new matches'),
                  onTap: () {
                    final cat = d['category']?.toString();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(d['label']?.toString() ?? 'Results'),
                          ),
                          body: ListingsBrowser(
                            category: (cat == null || cat == 'All')
                                ? null
                                : cat,
                            initialQuery: d['query']?.toString() ?? '',
                            initialSubcategory: d['subcategory']?.toString(),
                            initialCity: d['city']?.toString(),
                            initialMinPrice: (d['minPrice'] as num?)
                                ?.toDouble(),
                            initialMaxPrice: (d['maxPrice'] as num?)
                                ?.toDouble(),
                          ),
                        ),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('savedSearches')
                        .doc(docs[index].id)
                        .delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Reusable browse surface: search box, subcategory chips (when a category is
/// given), sort + price/emirate filters, and the results list.
class ListingsBrowser extends StatefulWidget {
  final String? category;
  final String initialQuery;
  final String? initialSubcategory;
  final String? initialCity;
  final double? initialMinPrice;
  final double? initialMaxPrice;

  const ListingsBrowser({
    super.key,
    this.category,
    this.initialQuery = '',
    this.initialSubcategory,
    this.initialCity,
    this.initialMinPrice,
    this.initialMaxPrice,
  });

  @override
  State<ListingsBrowser> createState() => _ListingsBrowserState();
}

class _ListingsBrowserState extends State<ListingsBrowser> {
  late String searchText;
  late final TextEditingController searchController;
  late final PagedListings _source;
  Timer? _debounce;
  late String selectedSubcategory;
  String sortBy = 'Newest';
  late String cityFilter;
  double? minPrice;
  double? maxPrice;
  bool deliveryOnly = false;
  bool hideSold = false;
  String conditionFilter = 'Any'; // 'Any' | 'New' | 'Used'
  bool negotiableOnly = false;
  String colorFilter = ''; // '' = any colour

  /// Results view: a responsive card grid (default) or a compact list. The
  /// grid drops to one column automatically on very narrow screens.
  bool gridView = true;

  static const sortOptions = [
    'Newest',
    'Price: Low to High',
    'Price: High to Low',
  ];

  @override
  void initState() {
    super.initState();
    searchText = widget.initialQuery;
    searchController = TextEditingController(text: widget.initialQuery);
    selectedSubcategory = widget.initialSubcategory ?? 'All';
    cityFilter = widget.initialCity ?? 'All';
    minPrice = widget.initialMinPrice;
    maxPrice = widget.initialMaxPrice;

    // Build the listings stream ONCE. Otherwise every keystroke (setState)
    // recreates query.snapshots(), resetting the StreamBuilder to a loading
    // spinner and making the search box flicker / lose focus.
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'listings',
    );
    if (widget.category != null && widget.category != 'All') {
      q = q.where('category', isEqualTo: widget.category);
    }
    // Read-level moderation: only approved ads are fetched for public browsing.
    q = q.where('approvalStatus', isEqualTo: 'approved');
    // Paged rather than a fixed window. This used to pull 1000 documents on
    // every open — the app's largest single read cost — and still capped the
    // catalogue: ad number 1001 was invisible to search with nothing in the UI
    // to say so. matchesFilters is applied per document as pages arrive, and
    // PagedListings keeps fetching until it finds matches, so a search still
    // reaches the whole collection.
    _source = PagedListings(
      query: q.orderBy('createdAt', descending: true),
      clientFilter: matchesFilters,
    );
    _source.loadMore();
  }

  /// Applies a filter mutation and restarts paging, since a filter change
  /// invalidates every page loaded under the previous criteria.
  void _applyFilterChange(VoidCallback mutate) {
    setState(mutate);
    _restartPaging();
  }

  /// Restarts paging. Called whenever the search text or a filter changes,
  /// since those change which documents qualify.
  void _restartPaging() {
    _source.refresh();
  }

  /// Saves the current search criteria so the user can be alerted when a new
  /// matching ad is posted.
  Future<void> saveCurrentSearch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final parts = <String>[];
    if (searchText.trim().isNotEmpty) parts.add('"${searchText.trim()}"');
    if (hasCategory) parts.add(widget.category!);
    if (selectedSubcategory != 'All') parts.add(selectedSubcategory);
    if (cityFilter != 'All') parts.add('in $cityFilter');
    if (minPrice != null || maxPrice != null) {
      parts.add(
        'Rs ${minPrice?.toStringAsFixed(0) ?? '0'}-'
        '${maxPrice?.toStringAsFixed(0) ?? 'any'}',
      );
    }
    final label = parts.isEmpty ? 'All ads' : parts.join(' · ');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedSearches')
        .add({
          'label': label,
          'query': searchText.trim(),
          'category': widget.category ?? 'All',
          'subcategory': selectedSubcategory,
          'city': cityFilter,
          'minPrice': minPrice,
          'maxPrice': maxPrice,
          'createdAt': Timestamp.now(),
        });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "$label" — we\'ll alert you on new matches'),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _source.dispose();
    searchController.dispose();
    super.dispose();
  }

  bool get hasCategory => widget.category != null && widget.category != 'All';

  Future<void> openFilters() async {
    final minController = TextEditingController(
      text: minPrice == null ? '' : minPrice!.toStringAsFixed(0),
    );
    final maxController = TextEditingController(
      text: maxPrice == null ? '' : maxPrice!.toStringAsFixed(0),
    );
    String tempCity = cityFilter;
    bool tempDelivery = deliveryOnly;
    bool tempHideSold = hideSold;
    String tempCondition = conditionFilter;
    bool tempNegotiable = negotiableOnly;
    String tempColor = colorFilter;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsetsDirectional.only(
                start: 16,
                end: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              // City + 2 fields + condition Wrap + colour swatches + 3
              // switches + buttons do not fit a short screen, and certainly
              // not with the keyboard up.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CitySelector(
                      value: tempCity,
                      includeAll: true,
                      onChanged: (value) =>
                          setSheetState(() => tempCity = value),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min price',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max price',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Condition',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Any', ...itemConditions].map((c) {
                        final selected = tempCondition == c;
                        return ChoiceChip(
                          label: Text(c),
                          selected: selected,
                          selectedColor: kPakGreen.withValues(alpha: 0.18),
                          onSelected: (_) =>
                              setSheetState(() => tempCondition = c),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    ColorSwatchSelector(
                      label: 'Colour',
                      selected: tempColor,
                      onChanged: (v) => setSheetState(() => tempColor = v),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Negotiable price only'),
                      value: tempNegotiable,
                      activeThumbColor: kPakGreen,
                      onChanged: (v) => setSheetState(() => tempNegotiable = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delivery available only'),
                      value: tempDelivery,
                      activeThumbColor: kPakGreen,
                      onChanged: (v) => setSheetState(() => tempDelivery = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hide sold items'),
                      value: tempHideSold,
                      activeThumbColor: kPakGreen,
                      onChanged: (v) => setSheetState(() => tempHideSold = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                cityFilter = 'All';
                                minPrice = null;
                                maxPrice = null;
                                deliveryOnly = false;
                                hideSold = false;
                                conditionFilter = 'Any';
                                negotiableOnly = false;
                                colorFilter = '';
                              });
                              _restartPaging();
                              Navigator.pop(context);
                            },
                            child: Text(tr('action.reset', 'Reset')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                cityFilter = tempCity;
                                minPrice = double.tryParse(
                                  minController.text.trim(),
                                );
                                maxPrice = double.tryParse(
                                  maxController.text.trim(),
                                );
                                deliveryOnly = tempDelivery;
                                hideSold = tempHideSold;
                                conditionFilter = tempCondition;
                                negotiableOnly = tempNegotiable;
                                colorFilter = tempColor;
                              });
                              // Filters decide which documents qualify, so the
                              // already-loaded pages are no longer valid.
                              _restartPaging();
                              Navigator.pop(context);
                            },
                            child: Text(tr('action.apply', 'Apply')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    minController.dispose();
    maxController.dispose();
  }

  int get activeFilterCount {
    var count = 0;
    if (cityFilter != 'All') count++;
    if (minPrice != null) count++;
    if (maxPrice != null) count++;
    if (deliveryOnly) count++;
    if (hideSold) count++;
    if (conditionFilter != 'Any') count++;
    if (negotiableOnly) count++;
    if (colorFilter.isNotEmpty) count++;
    return count;
  }

  // Signature of the last search reported, so a rebuild does not re-report the
  // same search. Never contains the query TEXT — see below.
  String? _lastTrackedSearch;

  void _maybeTrackSearch(int resultCount) {
    final query = searchText.trim();
    final filters = activeFilterCount;
    if (query.isEmpty && filters == 0) return;
    // The signature includes the query only to detect change; it is local
    // state and never leaves the device.
    final signature = '$query|$filters|${widget.category}|$resultCount';
    if (signature == _lastTrackedSearch) return;
    _lastTrackedSearch = signature;
    trackSearch(
      resultCount: resultCount,
      hasFilters: filters > 0,
      category: widget.category ?? '',
    );
  }

  // Split the query into words so an ad matches when EVERY word appears
  // somewhere in it (any field, any order) — e.g. "nike shoes" finds
  // "Shoes - Nike". Case-insensitive substring ("alphabetic") matching, so
  // partial words match too.
  //
  // Memoised on searchText: the predicate below now runs per DOCUMENT as pages
  // stream in, so re-splitting the query for every listing would put a regex
  // split on the hot path.
  String? _tokenSource;
  List<String> _tokensCache = const <String>[];

  List<String> get _searchTokens {
    if (_tokenSource != searchText) {
      _tokenSource = searchText;
      _tokensCache = searchText
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
    }
    return _tokensCache;
  }

  /// Whether one listing satisfies the search text and every active filter.
  /// Used both to filter an in-memory list and, as pages arrive, to accept or
  /// reject each freshly fetched document.
  bool matchesFilters(Listing listing) {
    final tokens = _searchTokens;
    {
      // One searchable haystack covering every text field on the ad.
      final haystack = [
        listing.title,
        listing.description,
        listing.location,
        listing.city,
        listing.category,
        listing.subcategory,
        listing.condition,
        listing.unit,
        listing.sellerName,
        listing.price,
        ...listing.attributes.values,
      ].join(' ').toLowerCase();
      // Each query word must match the ad: as a substring (exact/partial), or
      // — if not found — as a close typo of one of the ad's words (edit
      // distance). Words are split out lazily, only when a typo path is hit.
      List<String>? words;
      final matchesSearch =
          tokens.isEmpty ||
          tokens.every((t) {
            if (haystack.contains(t)) return true;
            words ??= haystack
                .split(RegExp(r'[\s,.;:!/()\-]+'))
                .where((w) => w.isNotEmpty)
                .toList();
            return _fuzzyWordMatch(words!, t);
          });

      final matchesSub =
          selectedSubcategory == 'All' ||
          listing.subcategory == selectedSubcategory;

      final matchesCity = cityFilter == 'All' || listing.city == cityFilter;

      final price = parsePrice(listing.price);
      final matchesMin = minPrice == null || price >= minPrice!;
      final matchesMax = maxPrice == null || price <= maxPrice!;
      final matchesDelivery = !deliveryOnly || listing.deliveryAvailable;
      final matchesSold = !hideSold || !listing.isSold;
      final matchesCondition =
          conditionFilter == 'Any' || listing.condition == conditionFilter;
      final matchesNegotiable = !negotiableOnly || listing.negotiable;
      final matchesColor =
          colorFilter.isEmpty ||
          (listing.attributes['Color'] ?? '').toLowerCase() ==
              colorFilter.toLowerCase();
      final notBlocked = !isHiddenSeller(listing.userId);

      return matchesSearch &&
          matchesSub &&
          matchesCity &&
          matchesMin &&
          matchesMax &&
          matchesDelivery &&
          matchesSold &&
          matchesCondition &&
          matchesNegotiable &&
          matchesColor &&
          notBlocked &&
          listing.isPubliclyVisible &&
          listing.isApproved;
    }
  }

  /// Filters and sorts an in-memory list. Kept for callers that already hold
  /// every listing; paged surfaces use matchesFilters per document instead.
  List<Listing> applyFilters(List<Listing> listings) {
    final result = listings.where(matchesFilters).toList();

    result.sort((a, b) {
      // Available items first, then featured.
      if (a.isSold != b.isSold) return a.isSold ? 1 : -1;
      if (a.isCurrentlyFeatured != b.isCurrentlyFeatured) {
        return a.isCurrentlyFeatured ? -1 : 1;
      }
      switch (sortBy) {
        case 'Price: Low to High':
          return parsePrice(a.price).compareTo(parsePrice(b.price));
        case 'Price: High to Low':
          return parsePrice(b.price).compareTo(parsePrice(a.price));
        default:
          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final currentCategory = categoryByTitle(widget.category ?? 'All');
    final subcategories = ['All', ...currentCategory.subcategories];

    // The search box + filters live OUTSIDE the StreamBuilder so they're never
    // rebuilt by stream ticks or replaced by the loading spinner — the field
    // stays responsive and keeps focus. Only the results list reacts to data.
    return Column(
      children: [
        // ── Compact search + filter/sort header ──
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSearchBar(
                controller: searchController,
                hintText: tr('home.searchHint', 'Search title, brand, category or city'),
                // Debounced: re-filter 250ms after the user stops typing, not
                // on every keystroke (which would rebuild the results list).
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) {
                      setState(() => searchText = value);
                      _restartPaging();
                    }
                  });
                },
                onSubmitted: (value) {
                  _debounce?.cancel();
                  setState(() => searchText = value);
                  _restartPaging();
                },
                trailing: IconButton(
                  tooltip: 'Save this search & get alerts',
                  icon: Icon(Icons.notification_add, color: AppColors.accent),
                  onPressed: saveCurrentSearch,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 38,
                child: Row(
                  children: [
                    Expanded(
                      child: _HeaderPillButton(
                        icon: Icons.tune,
                        label: activeFilterCount == 0
                            ? 'Filters'
                            : 'Filters ($activeFilterCount)',
                        active: activeFilterCount > 0,
                        onTap: openFilters,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: PopupMenuButton<String>(
                        initialValue: sortBy,
                        onSelected: (v) => setState(() => sortBy = v),
                        itemBuilder: (context) => [
                          for (final s in sortOptions)
                            PopupMenuItem(value: s, child: Text(s)),
                        ],
                        child: _HeaderPillButton(
                          icon: Icons.swap_vert,
                          label: sortBy == 'Newest'
                              ? 'Newest'
                              : (sortBy == 'Price: Low to High'
                                    ? 'Price ↑'
                                    : 'Price ↓'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _HeaderPillButton(
                      icon: gridView ? Icons.view_list : Icons.grid_view,
                      label: '',
                      tooltip: gridView
                          ? 'Switch to list view'
                          : 'Switch to grid view',
                      onTap: () => setState(() => gridView = !gridView),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasCategory)
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                padding: AppSpacing.pageH,
                scrollDirection: Axis.horizontal,
                itemCount: subcategories.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final subcategory = subcategories[index];
                  return ChoiceChip(
                    label: Text(subcategory),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selectedSubcategory == subcategory
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                    selected: selectedSubcategory == subcategory,
                    onSelected: (_) => _applyFilterChange(
                      () => selectedSubcategory = subcategory,
                    ),
                  );
                },
              ),
            ),
          ),
        Divider(height: 1, color: AppColors.borderSoft),
        Expanded(
          child: AnimatedBuilder(
            animation: _source,
            builder: (context, _) {
              final loaded = _source.items;

              // First page still in flight.
              if (loaded.isEmpty && _source.isLoading) {
                return _resultsSkeleton();
              }
              // Nothing loaded and the very first fetch failed.
              if (loaded.isEmpty && _source.error != null) {
                return ErrorStateWidget(
                  message: 'We couldn’t load listings. Please try again.',
                  onRetry: _restartPaging,
                );
              }

              // Sorting applies to what has been loaded; scrolling further
              // widens the set. Reported once the query is exhausted so the
              // count is the real total, not a partial page.
              final sorted = applyFilters(loaded);
              if (!_source.hasMore) _maybeTrackSearch(sorted.length);

              if (sorted.isEmpty && !_source.hasMore) {
                return EmptyStateWidget(
                  icon: Icons.search_off,
                  title: tr('state.noResults', 'No listings found'),
                  subtitle: _source.scannedCount > 0
                      ? 'We looked through every ad and none matched. Try a '
                            'different search or adjust your filters.'
                      : 'Try a different search or adjust your filters.',
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.md,
                      AppSpacing.page,
                      AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        // "+" while more pages remain, so the count never
                        // claims to be the whole catalogue when it isn't.
                        '${sorted.length}${_source.hasMore ? '+' : ''} result'
                        '${sorted.length == 1 ? '' : 's'}',
                        style: AppType.label,
                      ),
                    ),
                  ),
                  Expanded(
                    child: InfiniteScrollTrigger(
                      onLoadMore: _source.loadMore,
                      child: _results(sorted),
                    ),
                  ),
                  PagedListingFooter(
                    source: _source,
                    onRetry: _source.loadMore,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Placeholder cards while the first page of results loads.
  Widget _resultsSkeleton() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = MarketplaceListingCard.columnsFor(constraints.maxWidth);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        gridDelegate: MarketplaceListingCard.gridDelegate(
          context,
          availableWidth: constraints.maxWidth - AppSpacing.page * 2,
          columns: columns,
        ),
        itemCount: columns * 3,
        itemBuilder: (_, _) => const ListingCardSkeleton(),
      );
    },
  );

  /// The result set as a responsive grid or a compact list.
  Widget _results(List<Listing> filtered) {
    if (!gridView) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, i) => ListingCard(listing: filtered[i]),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MarketplaceListingCard.columnsFor(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.navClearance,
          ),
          gridDelegate: MarketplaceListingCard.gridDelegate(
            context,
            availableWidth: constraints.maxWidth - AppSpacing.page * 2,
            columns: columns,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, i) =>
              MarketplaceListingCard(listing: filtered[i]),
        );
      },
    );
  }
}

/// A pill-shaped header control used for Filters / Sort / view toggle above the
/// results. Fixed height so the row never grows and pushes the grid down.
class _HeaderPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final String? tooltip;

  const _HeaderPillButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.accent : AppColors.textSecondary;
    Widget pill = Container(
      height: 38,
      padding: EdgeInsets.symmetric(
        horizontal: label.isEmpty ? AppSpacing.md : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: active ? AppColors.primarySoft : AppColors.surface,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: active ? AppColors.accent : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: fg),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (tooltip != null) pill = Tooltip(message: tooltip!, child: pill);
    if (onTap == null) return pill;
    return InkWell(borderRadius: AppRadius.rPill, onTap: onTap, child: pill);
  }
}

// ---------------------------------------------------------------------------
// Listing card
// ---------------------------------------------------------------------------

/// A full-width listing row for vertical lists (favourites, a seller's
/// catalogue, search's list view).
///
/// Kept as a name so existing call sites keep working; the implementation is
/// the shared [MarketplaceListingTile], so every list in the app has identical
/// image sizes, spacing and text caps.
class ListingCard extends StatelessWidget {
  final Listing listing;

  const ListingCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    return MarketplaceListingTile(
      listing: listing,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
      ),
      details: [
        if (listing.isCurrentlyFeatured)
          const MetaChip(icon: Icons.star, label: 'Featured', color: kGold),
        if (listing.condition.isNotEmpty && listing.condition != 'N/A')
          MetaChip(icon: Icons.label_outline, label: listing.condition),
        if (listing.deliveryAvailable)
          MetaChip(
            icon: Icons.delivery_dining,
            label: 'Delivery',
            color: AppColors.success,
          ),
        if (timeAgo(listing.createdAt).isNotEmpty)
          MetaChip(
            icon: Icons.access_time,
            label: timeAgo(listing.createdAt),
            color: AppColors.textMuted,
          ),
      ],
      trailing: _ListingCardHeart(listing: listing),
    );
  }
}

/// The favourite toggle shown on a [ListingCard], sharing the app-wide
/// favourites state and Firestore write.
class _ListingCardHeart extends StatefulWidget {
  final Listing listing;
  const _ListingCardHeart({required this.listing});

  @override
  State<_ListingCardHeart> createState() => _ListingCardHeartState();
}

class _ListingCardHeartState extends State<_ListingCardHeart> {
  bool get _isFav => favoriteListings.any((i) => i.id == widget.listing.id);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _isFav ? 'Remove from favourites' : 'Add to favourites',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        _isFav ? Icons.favorite : Icons.favorite_border,
        size: 20,
        color: _isFav ? AppColors.error : AppColors.textMuted,
      ),
      onPressed: () async {
        final was = _isFav;
        setState(() {
          if (was) {
            favoriteListings.removeWhere((i) => i.id == widget.listing.id);
          } else {
            favoriteListings.add(widget.listing);
          }
        });
        await toggleFavoriteListing(widget.listing, wasFav: was);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Post ad
// ---------------------------------------------------------------------------

/// Lists the user's saved ad drafts; tap to resume, swipe/delete to remove.
