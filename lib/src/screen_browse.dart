part of '../main.dart';

// Category / search / listings browser and listing cards.

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
                            initialMinPrice: (d['minPrice'] as num?)?.toDouble(),
                            initialMaxPrice: (d['maxPrice'] as num?)?.toDouble(),
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
  late String selectedSubcategory;
  String sortBy = 'Newest';
  late String cityFilter;
  double? minPrice;
  double? maxPrice;
  bool deliveryOnly = false;
  bool hideSold = false;
  String conditionFilter = 'Any'; // 'Any' | 'New' | 'Used'
  bool negotiableOnly = false;

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
    _listingsStream = q
        .orderBy('createdAt', descending: true)
        .limit(100)
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
    return count;
  }

  List<Listing> applyFilters(List<Listing> listings) {
    final query = searchText.trim().toLowerCase();

    final result = listings.where((listing) {
      final matchesSearch =
          query.isEmpty ||
          listing.title.toLowerCase().contains(query) ||
          listing.description.toLowerCase().contains(query) ||
          listing.location.toLowerCase().contains(query) ||
          listing.city.toLowerCase().contains(query) ||
          listing.category.toLowerCase().contains(query) ||
          listing.subcategory.toLowerCase().contains(query) ||
          listing.price.toLowerCase().contains(query) ||
          listing.attributes.values.any(
            (v) => v.toLowerCase().contains(query),
          );

      final matchesSub =
          selectedSubcategory == 'All' ||
          listing.subcategory == selectedSubcategory;

      final matchesCity =
          cityFilter == 'All' || listing.city == cityFilter;

      final price = parsePrice(listing.price);
      final matchesMin = minPrice == null || price >= minPrice!;
      final matchesMax = maxPrice == null || price <= maxPrice!;
      final matchesDelivery = !deliveryOnly || listing.deliveryAvailable;
      final matchesSold = !hideSold || !listing.isSold;
      final matchesCondition =
          conditionFilter == 'Any' || listing.condition == conditionFilter;
      final matchesNegotiable = !negotiableOnly || listing.negotiable;
      final notBlocked = !blockedUserIds.contains(listing.userId);

      return matchesSearch &&
          matchesSub &&
          matchesCity &&
          matchesMin &&
          matchesMax &&
          matchesDelivery &&
          matchesSold &&
          matchesCondition &&
          matchesNegotiable &&
          notBlocked;
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

    return StreamBuilder<QuerySnapshot>(
      stream: _listingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading listings: ${snapshot.error}'));
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by title, location or price...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    searchText = value;
                  });
                },
              ),
            ),
            // Sort + filter bar
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
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
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
                      subtitle: 'Try a different search or adjust your filters.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: filtered
                          .map((listing) => ListingCard(listing: listing))
                          .toList(),
                    ),
            ),
          ],
        );
      },
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

    return FocusableTap(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  hasImage
                      ? Image.network(
                          images.first,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox(
                              height: 170,
                              child: Center(
                                child: Icon(Icons.broken_image, size: 60),
                              ),
                            );
                          },
                        )
                      : const SizedBox(
                          height: 170,
                          child: Center(child: Icon(Icons.image, size: 60)),
                        ),
                  if (listing.isCurrentlyFeatured)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kGold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: Colors.red,
                        ),
                        onPressed: toggleFavorite,
                      ),
                    ),
                  ),
                  if (listing.isSold) const SoldTag(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title.isEmpty ? 'Untitled ad' : listing.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    priceLabel(listing),
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if ((listing.condition.isNotEmpty &&
                          listing.condition != 'N/A') ||
                      listing.deliveryAvailable) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (listing.condition.isNotEmpty &&
                            listing.condition != 'N/A')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: listing.condition == 'New'
                                  ? Colors.green.shade50
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              listing.condition,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: listing.condition == 'New'
                                    ? Colors.green.shade800
                                    : Colors.blue.shade800,
                              ),
                            ),
                          ),
                        if (listing.deliveryAvailable)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.delivery_dining,
                                size: 15,
                                color: kPakGreen,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Delivery',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: kPakGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          [
                            listing.city,
                            listing.location,
                          ].where((e) => e.isNotEmpty).join(', '),
                          style: const TextStyle(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (listing.condition.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: listing.condition == 'New'
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: listing.condition == 'New'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                          child: Text(
                            listing.condition,
                            style: TextStyle(
                              fontSize: 11,
                              color: listing.condition == 'New'
                                  ? Colors.green.shade800
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (posted.isNotEmpty)
                        Text(
                          posted,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
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
