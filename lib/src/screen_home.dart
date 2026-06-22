part of '../main.dart';

// Home feed and its rails.

class PromoBannerData {
  final String title;
  final String subtitle;
  final String image;
  final List<Color> colors; // gradient fallback if the image fails to load
  /// Category to open on tap; empty/null opens Post Ad.
  final String? category;
  /// If set, tapping opens this seller's storefront (business banner ads).
  final String? sellerId;

  const PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.colors,
    this.category,
    this.sellerId,
  });
}

/// Auto-advancing promotional banner carousel with dot indicators.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key});

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;

  // Default banners, used until/unless custom ones are configured in the
  // `banners` Firestore collection (each pointing to a Storage image).
  static const _defaultBanners = <PromoBannerData>[
    PromoBannerData(
      title: 'Cars & more',
      subtitle: 'Explore the best Motors deals',
      image:
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
      category: 'Motors',
    ),
    PromoBannerData(
      title: 'Find your home',
      subtitle: 'Browse Properties across Pakistan',
      image:
          'https://images.unsplash.com/photo-1560518883-ce09059eeffa?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
      category: 'Properties',
    ),
    PromoBannerData(
      title: 'Latest mobiles',
      subtitle: 'Phones, tablets & gadgets',
      image:
          'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=900&q=70',
      colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
      category: 'Mobiles & Tablets',
    ),
    PromoBannerData(
      title: 'Sell faster',
      subtitle: 'Post your ad free in 2 minutes',
      image:
          'https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?auto=format&fit=crop&w=900&q=70',
      colors: [kPakGreen, kPakGreenLight],
      category: null,
    ),
  ];

  List<PromoBannerData> _banners = _defaultBanners;

  @override
  void initState() {
    super.initState();
    _loadBanners();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % _banners.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Loads custom banners from Firestore (`banners` where active == true),
  /// falling back to the defaults if none are configured.
  Future<void> _loadBanners() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('banners')
          .where('active', isEqualTo: true)
          .get();
      final now = DateTime.now();
      final docs =
          snap.docs.where((d) {
            final until = d.data()['expiresAt'];
            return until is! Timestamp || until.toDate().isAfter(now);
          }).toList()..sort(
            (a, b) => ((a.data()['order'] as num?) ?? 0)
                .compareTo((b.data()['order'] as num?) ?? 0),
          );
      if (docs.isNotEmpty && mounted) {
        setState(() {
          _banners = docs.map((d) {
            final m = d.data();
            return PromoBannerData(
              title: m['title']?.toString() ?? '',
              subtitle: m['subtitle']?.toString() ?? '',
              image: m['imageUrl']?.toString() ?? '',
              colors: const [kPakGreen, kPakGreenLight],
              category: m['category']?.toString(),
              sellerId: m['sellerId']?.toString(),
            );
          }).toList();
        });
      }
    } catch (_) {
      // Keep defaults on any error.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _bannerGradient(List<Color> colors) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _banners.length,
            itemBuilder: (context, i) {
              final b = _banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Material(
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      final sid = b.sellerId;
                      final cat = b.category;
                      final Widget dest;
                      if (sid != null && sid.isNotEmpty) {
                        dest = SellerProfileScreen(
                          sellerId: sid,
                          sellerName: b.title,
                        );
                      } else if (cat != null && cat.isNotEmpty && cat != 'All') {
                        dest = CategoryScreen(title: cat);
                      } else {
                        dest = const AddListingScreen();
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => dest),
                      );
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Real photo (with gradient fallback while loading/on error).
                        Image.network(
                          b.image,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : _bannerGradient(b.colors),
                          errorBuilder: (context, e, s) =>
                              _bannerGradient(b.colors),
                        ),
                        // Dark scrim so the text stays readable over any photo.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                b.subtitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Tap to explore',
                                  style: TextStyle(
                                    color: b.colors.first,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _index ? kPakGreen : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grey placeholder shown in the feed grid while ads load.
class _HomeQuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  const _HomeQuickTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home banner nudging unverified users to verify (mandatory to transact).
/// Hidden for verified users, admins, and guests.
class VerifyBanner extends StatelessWidget {
  const VerifyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || isAdminUser()) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        if (data == null || data['idVerified'] == true) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user, color: Colors.blue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Verify your identity to post, buy, make offers and chat.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                ),
                child: const Text('Verify'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Light-themed "Recently viewed" rail for the mobile home. Hidden when empty.
class RecentlyViewedRail extends StatelessWidget {
  const RecentlyViewedRail({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('recentlyViewed')
          .orderBy('viewedAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final items = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .toList();
        if (items.length < 2) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  Icon(Icons.history, color: Colors.black54, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'Recently viewed',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 246,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: items.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(width: 165, child: FeedAdCard(listing: items[i])),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Home rail of the newest ads from sellers the user follows. Hidden when the
/// user follows nobody (or those sellers have no ads).
class FollowingRail extends StatelessWidget {
  const FollowingRail({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, followSnap) {
        if (!followSnap.hasData) return const SizedBox.shrink();
        final ids = followSnap.data!.docs.map((d) => d.id).toList();
        if (ids.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('listings')
              .where('userId', whereIn: ids)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final items =
                snapshot.data!.docs.map((d) => Listing.fromDoc(d)).toList()
                  ..sort((a, b) {
                    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bt.compareTo(at);
                  });
            if (items.isEmpty) return const SizedBox.shrink();
            final shown = items.take(12).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FollowingScreen()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Row(
                      children: [
                        Icon(Icons.people_alt, color: Colors.black54, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'From sellers you follow',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Spacer(),
                        Text(
                          'See all',
                          style: TextStyle(color: kPakGreen, fontSize: 13),
                        ),
                        Icon(Icons.chevron_right, color: kPakGreen, size: 18),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 246,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 165,
                        child: FeedAdCard(listing: shown[i]),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Home rail of ads whose price was recently reduced — a "deals" shelf. Hidden
/// when there are fewer than two live price-dropped ads.
class DealsRail extends StatelessWidget {
  const DealsRail({super.key});

  @override
  Widget build(BuildContext context) {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('priceDropAt', isGreaterThan: cutoff)
          .orderBy('priceDropAt', descending: true)
          .limit(15)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final items = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where((l) => !l.isSold && !isHiddenSeller(l.userId))
            .toList();
        if (items.length < 2) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: Colors.deepOrange,
                    size: 20,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Deals & price drops',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 246,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: items.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 165,
                    child: FeedAdCard(listing: items[i]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Directory of all business accounts (storefronts).
class FeaturedBusinessesRail extends StatelessWidget {
  const FeaturedBusinessesRail({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('featuredBusiness', isEqualTo: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final now = DateTime.now();
        final docs = snapshot.data!.docs.where((d) {
          final until = (d.data() as Map)['featuredBusinessUntil'];
          return until is! Timestamp || until.toDate().isAfter(now);
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              child: Row(
                children: [
                  const Icon(Icons.storefront, color: kPakGreen, size: 22),
                  const SizedBox(width: 6),
                  const Text(
                    'Featured Businesses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StoresScreen()),
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final name = d['businessName']?.toString() ?? 'Business';
                  final tagline = d['tagline']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerProfileScreen(
                          sellerId: docs[i].id,
                          sellerName: name,
                        ),
                      ),
                    ),
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kGold, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(
                            builder: (context) {
                              final logo = d['logoUrl']?.toString() ?? '';
                              return CircleAvatar(
                                radius: 28,
                                backgroundColor: kPakGreen.withValues(
                                  alpha: 0.12,
                                ),
                                backgroundImage: logo.isNotEmpty
                                    ? NetworkImage(logo)
                                    : null,
                                child: logo.isEmpty
                                    ? const Icon(
                                        Icons.storefront,
                                        color: kPakGreen,
                                        size: 30,
                                      )
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (tagline.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tagline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  String searchQuery = '';
  String homeCity = 'All Pakistan';
  String homeSort = 'Newest';
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ensure the profile exists first, then run the one-time location prompt so
    // the two writes don't race (ensureUserDoc does a non-merge set on create).
    ensureUserDoc().then((_) => maybePromptLocation());
    loadFavorites();
    loadBlocked();
    loadPlatformBlockedUsers().then((_) {
      if (mounted) setState(() {});
    });
    setupPushNotifications();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// Creates a `users/{uid}` profile doc the first time we see this account,
  /// so seller profiles can show a "Member since" date.
  Future<void> ensureUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'email': user.email ?? '',
        'isAnonymous': user.isAnonymous,
        'verified': user.emailVerified,
        'createdAt': Timestamp.now(),
      });
    } else if (snap.data()?['verified'] != user.emailVerified) {
      // Keep the public "Verified" badge in sync with email verification.
      await ref.set({'verified': user.emailVerified}, SetOptions(merge: true));
    }
  }

  /// One-time, post-login prompt asking the user to share their location. We
  /// remember that we asked (`locationAsked`) so it never shows again, whether
  /// they accept or decline. On accept we capture GPS and save it to the
  /// profile (visible to admins).
  Future<void> maybePromptLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (snap.data()?['locationAsked'] == true) return;
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.location_on, color: kPakGreen, size: 44),
          title: const Text('Share your location?'),
          content: const Text(
            'Allow PakBazar to use your location to show nearby ads and help '
            'keep the marketplace safe. You can turn this off anytime in your '
            'browser settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Share location'),
            ),
          ],
        ),
      );
      // Mark as asked regardless of the choice so this stays a one-time prompt.
      await ref.set({'locationAsked': true}, SetOptions(merge: true));
      if (share == true) {
        try {
          final pos = await determineCurrentPosition();
          await saveUserLocation(lat: pos.latitude, lng: pos.longitude);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not get your location: $e')),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> loadFavorites() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    favoriteListings.clear();
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();

    if (!mounted) return;

    setState(() {
      for (final doc in snapshot.docs) {
        favoriteListings.add(Listing.fromDoc(doc));
      }
    });
  }

  Future<void> loadBlocked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    blockedUserIds.clear();
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .get();
    blockedUserIds.addAll(snap.docs.map((d) => d.id));
    if (mounted) setState(() {});
  }

  void openSearch(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          initialQuery: query,
          // Scope search to the city chosen in the home location bar.
          initialCity: homeCity == 'All Pakistan' ? null : homeCity,
        ),
      ),
    );
  }

  Widget homeContent() =>
      isPhone(context) ? _mobileHome() : _desktopHome();

  /// Dubizzle-style phone home: search pill, round category strip, and a
  /// 2-column "Fresh recommendations" feed on a light background.
  Widget _mobileHome() {
    final w = MediaQuery.of(context).size.width;
    final cols = w > 1100 ? 4 : (w > 700 ? 3 : 2);
    final categories =
        appCategories.where((c) => c.title != 'All').toList();

    return Container(
      color: const Color(0xFFEFF1F2),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots(),
        builder: (context, snapshot) {
          var listings = (snapshot.data?.docs ?? [])
              .map((d) => Listing.fromDoc(d))
              .toList()
            ..sort((a, b) {
              // Available items first, then featured, then the chosen sort.
              if (a.isSold != b.isSold) return a.isSold ? 1 : -1;
              if (a.isCurrentlyFeatured != b.isCurrentlyFeatured) {
                return a.isCurrentlyFeatured ? -1 : 1;
              }
              switch (homeSort) {
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

          if (homeCity != 'All Pakistan') {
            listings =
                listings.where((l) => l.city == homeCity).toList();
          }
          if (blockedUserIds.isNotEmpty || platformBlockedUserIds.isNotEmpty) {
            listings = listings
                .where((l) => !isHiddenSeller(l.userId))
                .toList();
          }
          final featured = listings.where((l) => l.isCurrentlyFeatured).toList();
          final topDeals =
              listings.where((l) => !l.isSold && l.views > 0).toList()
                ..sort((a, b) => b.views.compareTo(a.views));
          final topDealsList = topDeals.take(10).toList();

          return RefreshIndicator(
            color: kPakGreen,
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 600));
              if (mounted) setState(() {});
            },
            child: CustomScrollView(
              slivers: [
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: kPakGreen,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(30),
                    child: TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => openSearch(v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Find cars, mobiles, property and more',
                        prefixIcon: const Icon(Icons.search, color: kPakGreen),
                        suffixIcon: Container(
                          margin: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: kPakGreen,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () =>
                                openSearch(searchController.text.trim()),
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final q in const [
                              'Cars',
                              'Mobiles',
                              'Property',
                              'Food & Grocery',
                              'Jobs',
                              'Laptops',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  backgroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  label: Text(q),
                                  onPressed: () => openSearch(q),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: VerifyBanner()),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                        child: Row(
                          children: [
                            const Text(
                              'Browse categories',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AllCategoriesScreen(),
                                ),
                              ),
                              child: const Text('See all'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CategoryScreen(title: cat.title),
                          ),
                        ),
                        child: SizedBox(
                          width: 74,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              CircleAvatar(
                                radius: 26,
                                backgroundColor:
                                    kPakGreen.withValues(alpha: 0.12),
                                child: Icon(
                                  cat.icon,
                                  color: kPakGreen,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cat.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: _HomeQuickTile(
                          icon: Icons.restaurant,
                          label: 'Food & Grocery',
                          colors: const [Color(0xFFFF7043), Color(0xFFE53935)],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CategoryScreen(title: 'Food & Grocery'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HomeQuickTile(
                          icon: Icons.storefront,
                          label: 'Browse Stores',
                          colors: const [Color(0xFF00897B), Color(0xFF00565B)],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StoresScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: PromoCarousel(),
                ),
              ),
              if (featuringEnabled.value)
                const SliverToBoxAdapter(child: FeaturedBusinessesRail()),
              if (topDealsList.length >= 3)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: Colors.deepOrange,
                              size: 22,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Top Deals',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Most viewed',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 246,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: topDealsList.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: 165,
                              child: FeedAdCard(listing: topDealsList[i]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (featured.isNotEmpty && featuringEnabled.value)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            Icon(Icons.star, color: kGold, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Featured',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 246,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          itemCount: featured.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: SizedBox(
                              width: 165,
                              child: FeedAdCard(listing: featured[i]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SliverToBoxAdapter(child: DealsRail()),
              const SliverToBoxAdapter(child: FollowingRail()),
              const SliverToBoxAdapter(child: RecentlyViewedRail()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recommended for you',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        initialValue: homeSort,
                        onSelected: (v) => setState(() => homeSort = v),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'Newest', child: Text('Newest')),
                          PopupMenuItem(
                            value: 'Price: Low to High',
                            child: Text('Price: Low to High'),
                          ),
                          PopupMenuItem(
                            value: 'Price: High to Low',
                            child: Text('Price: High to Low'),
                          ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort, size: 18, color: Colors.grey[700]),
                            const SizedBox(width: 4),
                            Text(
                              homeSort == 'Newest'
                                  ? 'Newest'
                                  : (homeSort == 'Price: Low to High'
                                        ? 'Price ↑'
                                        : 'Price ↓'),
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!snapshot.hasData)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => const _SkeletonCard(),
                      childCount: cols * 3,
                    ),
                  ),
                )
              else if (listings.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text('No ads yet. Be the first to post!'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => FeedAdCard(listing: listings[i]),
                      childCount: listings.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _desktopHome() {
    final filteredCategories = appCategories.where((category) {
      return category.title.toLowerCase().contains(
        searchQuery.trim().toLowerCase(),
      );
    }).toList();
    final phone = isPhone(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 10 : 16, 12, phone ? 10 : 16, 0),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search all ads...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => openSearch(searchController.text.trim()),
              ),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
            onSubmitted: (value) => openSearch(value.trim()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: () {
                        final w = MediaQuery.of(context).size.width;
                        if (w > 1100) return 4;
                        if (w > 700) return 3;
                        return 2;
                      }(),
                      childAspectRatio: phone ? 1.05 : 1.4,
                      crossAxisSpacing: phone ? 10 : 12,
                      mainAxisSpacing: phone ? 10 : 12,
                    ),
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, index) {
                      final category = filteredCategories[index];

                      return FocusableTap(
                        autofocus: index == 0,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CategoryScreen(title: category.title),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(category.icon, size: 42, color: kPakGreen),
                              const SizedBox(height: 12),
                              Text(
                                category.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                category.title == 'All'
                                    ? 'Browse all ads'
                                    : '${category.subcategories.length} subcategories',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (featuringEnabled.value)
                    AdsRail(
                      title: 'Featured',
                      icon: Icons.star,
                      stream: FirebaseFirestore.instance
                          .collection('listings')
                          .where('isFeatured', isEqualTo: true)
                          .limit(10)
                          .snapshots(),
                    ),
                  AdsRail(
                    title: 'Deals & price drops',
                    icon: Icons.local_fire_department,
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .where(
                          'priceDropAt',
                          isGreaterThan: Timestamp.fromDate(
                            DateTime.now().subtract(const Duration(days: 30)),
                          ),
                        )
                        .orderBy('priceDropAt', descending: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  AdsRail(
                    title: 'Latest Ads',
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .orderBy('createdAt', descending: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  AdsRail(
                    title: 'Trending',
                    icon: Icons.trending_up,
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .orderBy('views', descending: true)
                        .limit(10)
                        .snapshots(),
                  ),
                  if (FirebaseAuth.instance.currentUser != null)
                    AdsRail(
                      title: 'Recently Viewed',
                      icon: Icons.history,
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .collection('recentlyViewed')
                          .orderBy('viewedAt', descending: true)
                          .limit(10)
                          .snapshots(),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _postAd() async {
    if (!await ensureVerified(context)) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddListingScreen()),
    );
    if (mounted) setState(() {});
  }

  /// dubizzle-style home top bar: location selector + favorites + alerts.
  PreferredSizeWidget _homeAppBar() {
    return AppBar(
      titleSpacing: 12,
      title: InkWell(
        onTap: () async {
          final c = await showCityPicker(context, includeAll: true);
          if (!mounted) return;
          if (c != null) {
            final picked = c == 'All' ? 'All Pakistan' : c;
            setState(() => homeCity = picked);
            // Auto-save the chosen city to the profile for the admin panel.
            saveUserLocation(city: picked);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                homeCity,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.favorite_border, color: Colors.white),
          tooltip: 'Favorites',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavoritesScreen()),
          ),
        ),
        const NotificationBell(),
      ],
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = selectedIndex == index;
    final color = selected ? kPakGreen : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      const ChatsScreen(),
      const MyAdsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: selectedIndex == 0 ? _homeAppBar() : null,
      body: pages[selectedIndex],
      floatingActionButton: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          onPressed: _postAd,
          backgroundColor: kPakGreen,
          shape: const CircleBorder(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 22, color: Colors.white),
              Text(
                tr('nav.sell'),
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 62,
        color: Colors.white,
        elevation: 16,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _navItem(Icons.home, tr('nav.home'), 0),
            _navItem(Icons.chat, tr('nav.chats'), 1),
            const SizedBox(width: 64),
            _navItem(Icons.list_alt, tr('nav.myAds'), 2),
            _navItem(Icons.person, tr('nav.profile'), 3),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse + search + filters
// ---------------------------------------------------------------------------
