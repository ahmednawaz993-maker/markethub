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
        body: const Center(
          child: Text(
            'Please log in to see saved searches',
            style: TextStyle(color: Colors.white70),
          ),
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved searches yet.\nTap the bell icon while browsing to '
                  'save a search and get alerts on new matching ads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _listingsStream;
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
    // Load a wide window so search covers effectively the whole catalogue (not
    // just the latest 100). Client-side token search then filters this set.
    _listingsStream = q
        .orderBy('createdAt', descending: true)
        .limit(1000)
        .snapshots();
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
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  CitySelector(
                    value: tempCity,
                    includeAll: true,
                    onChanged: (value) => setSheetState(() => tempCity = value),
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
                    alignment: Alignment.centerLeft,
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
                            Navigator.pop(context);
                          },
                          child: const Text('Reset'),
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
                            Navigator.pop(context);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
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

  List<Listing> applyFilters(List<Listing> listings) {
    // Split the query into words so an ad matches when EVERY word appears
    // somewhere in it (any field, any order) — e.g. "nike shoes" finds
    // "Shoes - Nike". Case-insensitive substring ("alphabetic") matching, so
    // partial words match too.
    final tokens = searchText
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final result = listings.where((listing) {
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
    }).toList();

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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search anything — title, category, brand, location…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            // Debounced: re-filter 250ms after the user stops typing, not on
            // every keystroke (which would rebuild the whole results list).
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                if (mounted) setState(() => searchText = value);
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: sortBy,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: sortOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => sortBy = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: openFilters,
                icon: const Icon(Icons.tune),
                label: Text(
                  activeFilterCount == 0
                      ? 'Filters'
                      : 'Filters ($activeFilterCount)',
                ),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  tooltip: 'Save this search & get alerts',
                  icon: const Icon(Icons.notification_add, color: kPakGreen),
                  onPressed: saveCurrentSearch,
                ),
              ),
            ],
          ),
        ),
        if (hasCategory)
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: subcategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final subcategory = subcategories[index];
                final isSelected = selectedSubcategory == subcategory;

                return ChoiceChip(
                  label: Text(subcategory),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      selectedSubcategory = subcategory;
                    });
                  },
                );
              },
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _listingsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading listings: ${snapshot.error}'),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              final allListings = docs.map((d) => Listing.fromDoc(d)).toList();
              final filtered = applyFilters(allListings);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} result'
                        '${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off,
                            title: 'No listings found',
                            subtitle:
                                'Try a different search or adjust your filters.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                ListingCard(listing: filtered[i]),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Listing card
// ---------------------------------------------------------------------------

class ListingCard extends StatefulWidget {
  final Listing listing;

  const ListingCard({super.key, required this.listing});

  @override
  State<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<ListingCard> {
  bool get isFavorite {
    return favoriteListings.any((item) => item.id == widget.listing.id);
  }

  void toggleFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final wasFavorite = isFavorite;

    setState(() {
      if (wasFavorite) {
        favoriteListings.removeWhere((item) => item.id == widget.listing.id);
      } else {
        favoriteListings.add(widget.listing);
      }
    });

    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.listing.id);

    if (wasFavorite) {
      await ref.delete();
    } else {
      await ref.set({
        ...widget.listing.toMap(),
        'savedListingId': widget.listing.id,
        'savedAt': Timestamp.now(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.galleryImages;
    final hasImage = images.isNotEmpty;
    final posted = timeAgo(listing.createdAt);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final showCondition =
        listing.condition.isNotEmpty && listing.condition != 'N/A';
    final isNew = listing.condition == 'New';

    return FocusableTap(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    Image.network(
                      images.first,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: muted,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_outlined, size: 48, color: muted),
                    ),
                  // Subtle top scrim so overlaid chips stay legible on any image.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.28),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (listing.isCurrentlyFeatured)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE0B33A), kGold],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: kGold.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: toggleFavorite,
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (listing.isSold) const SoldTag(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (productColorByName(
                            listing.attributes['Color'] ?? '',
                          ) !=
                          null) ...[
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: productColorByName(
                              listing.attributes['Color'] ?? '',
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          listing.title.isEmpty ? 'Untitled ad' : listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    priceLabel(listing),
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF66BB6A)
                          : const Color(0xFF1B8E3C),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (showCondition || listing.deliveryAvailable) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showCondition)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (isNew ? Colors.green : Colors.blue)
                                  .withValues(alpha: isDark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              listing.condition,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isNew
                                    ? (isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade800)
                                    : (isDark
                                          ? Colors.blue.shade200
                                          : Colors.blue.shade800),
                              ),
                            ),
                          ),
                        if (listing.deliveryAvailable)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: kPakGreen.withValues(
                                alpha: isDark ? 0.24 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delivery_dining,
                                  size: 14,
                                  color: isDark
                                      ? Colors.lightBlue.shade200
                                      : kPakGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Delivery',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.lightBlue.shade200
                                        : kPakGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: muted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          [
                            listing.city,
                            listing.location,
                          ].where((e) => e.isNotEmpty).join(', '),
                          style: TextStyle(color: muted, fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (posted.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          posted,
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post ad
// ---------------------------------------------------------------------------

/// Lists the user's saved ad drafts; tap to resume, swipe/delete to remove.
