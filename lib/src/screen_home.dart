part of '../main.dart';

// ---------------------------------------------------------------------------
// Home
//
// A marketplace home built entirely from the design system: a rounded search
// bar, a category strip, a "What's New on PakBazar" promo rail, Continue
// Browsing, Recent Searches, then category rails and the recommended feed.
//
// Every section renders nothing when it has no data, so the page never shows a
// heading above an empty gap.
// ---------------------------------------------------------------------------

/// A single promotional card definition for the "What's New" rail.
class PromoBannerData {
  final String title;
  final String subtitle;
  final String image;

  /// Small pill shown over the image (usually the category).
  final String badge;

  /// Category to open on tap; empty/null opens Post Ad.
  final String? category;

  /// If set, tapping opens this seller's storefront (business banner ads).
  final String? sellerId;

  const PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.image,
    this.badge = '',
    this.category,
    this.sellerId,
  });
}

/// "What's New on PakBazar" — a horizontally scrolling rail of wide promo
/// cards. Uses the admin-managed `banners` collection when it has entries, and
/// falls back to a curated PakBazar set otherwise.
class WhatsNewSection extends StatefulWidget {
  const WhatsNewSection({super.key});

  @override
  State<WhatsNewSection> createState() => _WhatsNewSectionState();
}

class _WhatsNewSectionState extends State<WhatsNewSection> {
  static const _defaultBanners = <PromoBannerData>[
    PromoBannerData(
      title: 'Find your next car',
      subtitle: 'Thousands of verified cars, bikes and parts',
      badge: 'Motors',
      image:
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=900&q=70',
      category: 'Motors',
    ),
    PromoBannerData(
      title: 'Sell your property',
      subtitle: 'Reach buyers and tenants across Pakistan',
      badge: 'Properties',
      image:
          'https://images.unsplash.com/photo-1560518883-ce09059eeffa?auto=format&fit=crop&w=900&q=70',
      category: 'Properties',
    ),
    PromoBannerData(
      title: 'Latest mobile phones',
      subtitle: 'Phones, tablets and accessories near you',
      badge: 'Mobiles & Tablets',
      image:
          'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=900&q=70',
      category: 'Mobiles & Tablets',
    ),
    PromoBannerData(
      title: 'Promote your business',
      subtitle: 'Open a PakBazar store and get discovered',
      badge: 'Business',
      image:
          'https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?auto=format&fit=crop&w=900&q=70',
    ),
  ];

  List<PromoBannerData> _banners = _defaultBanners;

  @override
  void initState() {
    super.initState();
    _loadBanners();
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
            (a, b) => ((a.data()['order'] as num?) ?? 0).compareTo(
              (b.data()['order'] as num?) ?? 0,
            ),
          );
      if (docs.isNotEmpty && mounted) {
        setState(() {
          _banners = docs.map((d) {
            final m = d.data();
            return PromoBannerData(
              title: m['title']?.toString() ?? '',
              subtitle: m['subtitle']?.toString() ?? '',
              image: m['imageUrl']?.toString() ?? '',
              badge: m['category']?.toString() ?? '',
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

  void _open(PromoBannerData b) {
    final sid = b.sellerId;
    final cat = b.category;
    final Widget dest;
    if (sid != null && sid.isNotEmpty) {
      dest = SellerProfileScreen(sellerId: sid, sellerName: b.title);
    } else if (cat != null && cat.isNotEmpty && cat != 'All') {
      dest = CategoryScreen(title: cat);
    } else {
      dest = const AddListingScreen();
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => dest));
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    // One card plus a peek of the next, so the rail reads as scrollable.
    final cardWidth = (screenWidth - AppSpacing.page * 2 - 40).clamp(
      220.0,
      320.0,
    );
    final railHeight = FeaturedBannerCard.heightFor(context, cardWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.section),
        const SectionHeader(title: "What's New on PakBazar"),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: _banners.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final b = _banners[i];
              return FeaturedBannerCard(
                width: cardWidth,
                title: b.title,
                subtitle: b.subtitle,
                badge: b.badge,
                imageUrl: b.image,
                onTap: () => _open(b),
              );
            },
          ),
        ),
      ],
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            0,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: AppRadius.rCard,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user, color: AppColors.info, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Verify your identity to post, buy, make offers and chat.',
                    style: AppType.secondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VerificationScreen(),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Verify'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Home promo banner for the lucky-draw campaign. Renders nothing once the
/// campaign is over (luckyDrawActive() is false), so it AUTO-REMOVES itself on
/// 14 Aug 2026 with no update. Tapping it opens the Invite & Win screen.
class LuckyDrawBanner extends StatelessWidget {
  const LuckyDrawBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!luckyDrawActive()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        0,
      ),
      child: InkWell(
        borderRadius: AppRadius.rCard,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InviteFriendsScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPakGreen, kPakGreenLight],
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
            ),
            borderRadius: AppRadius.rCard,
          ),
          child: Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Win PKR 100,000!',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: kGold,
                            borderRadius: AppRadius.rSm,
                          ),
                          child: const Text(
                            '5 WINNERS',
                            style: TextStyle(
                              color: kPakGreenDeep,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Share more to win · draw on 14 Aug 2026',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.rPill,
                ),
                child: const Text(
                  'Invite',
                  style: TextStyle(
                    color: kPakGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round-icon category strip under the search bar.
class HomeCategoryStrip extends StatelessWidget {
  const HomeCategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the admin edits the catalog, so the strip reflects an edit
    // without the user restarting the app.
    return ValueListenableBuilder<int>(
      valueListenable: categoriesVersion,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final categories = visibleCategories
        .where((c) => c.title != 'All')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(
          title: 'Browse categories',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AllCategoriesScreen()),
          ),
        ),
        SizedBox(
          height: CategoryCard.heightFor(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => CategoryCard(
              icon: categories[i].icon,
              label: categories[i].title,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryScreen(title: categories[i].title),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Recent Searches" — device-local shortcuts back into the search screen.
/// Laid out horizontally when there is room and vertically on narrow screens,
/// so long queries never wrap into a column of letters.
class RecentSearchesSection extends StatelessWidget {
  final void Function(RecentSearch) onOpen;

  const RecentSearchesSection({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecentSearch>>(
      valueListenable: recentSearches,
      builder: (context, items, _) {
        if (items.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            // A card needs ~240px to show its query and meta line without
            // clipping; below that, stack the cards instead.
            final horizontal = constraints.maxWidth >= 360;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.section),
                SectionHeader(
                  title: 'Recent Searches',
                  actionLabel: 'Clear',
                  onAction: clearRecentSearches,
                ),
                if (horizontal)
                  SizedBox(
                    height: RecentSearchCard.height,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.page,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, i) => RecentSearchCard(
                        width: 250,
                        query: items[i].query,
                        category: items[i].category,
                        location: items[i].city,
                        imageUrl: items[i].imageUrl,
                        onTap: () => onOpen(items[i]),
                        onRemove: () => removeRecentSearch(items[i]),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: AppSpacing.pageH,
                    child: Column(
                      children: [
                        for (final s in items.take(5)) ...[
                          RecentSearchCard(
                            query: s.query,
                            category: s.category,
                            location: s.city,
                            imageUrl: s.imageUrl,
                            onTap: () => onOpen(s),
                            onRemove: () => removeRecentSearch(s),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
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

/// "Continue Browsing" — the listings this user recently opened.
class ContinueBrowsingRail extends StatelessWidget {
  const ContinueBrowsingRail({super.key});

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
            .where((l) => l.isApproved && !isHiddenSeller(l.userId))
            .toList();
        return HorizontalListingSection(
          title: 'Continue Browsing',
          subtitle: 'Pick up where you left off',
          icon: Icons.history,
          iconColor: AppColors.textSecondary,
          listings: items,
          minItems: 2,
        );
      },
    );
  }
}

/// Kept for compatibility with older call sites; renders Continue Browsing.
class RecentlyViewedRail extends StatelessWidget {
  const RecentlyViewedRail({super.key});

  @override
  Widget build(BuildContext context) => const ContinueBrowsingRail();
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
              .where('approvalStatus', isEqualTo: 'approved')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final items =
                snapshot.data!.docs
                    .map((d) => Listing.fromDoc(d))
                    .where((l) => l.isApproved)
                    .toList()
                  ..sort((a, b) {
                    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bt.compareTo(at);
                  });
            return HorizontalListingSection(
              title: 'From sellers you follow',
              icon: Icons.people_alt_outlined,
              listings: items.take(12).toList(),
              onSeeAll: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FollowingScreen()),
              ),
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
          .where('approvalStatus', isEqualTo: 'approved')
          .where('priceDropAt', isGreaterThan: cutoff)
          .orderBy('priceDropAt', descending: true)
          .limit(15)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final items = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where(
              (l) =>
                  !l.isSold &&
                  l.isPubliclyVisible &&
                  l.isApproved &&
                  !isHiddenSeller(l.userId),
            )
            .toList();
        return HorizontalListingSection(
          title: 'Deals & price drops',
          icon: Icons.local_fire_department_outlined,
          iconColor: Colors.deepOrange,
          listings: items,
          minItems: 2,
        );
      },
    );
  }
}

/// Rail of admin-featured business storefronts.
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
            const SizedBox(height: AppSpacing.section),
            SectionHeader(
              title: 'Featured businesses',
              icon: Icons.storefront_outlined,
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoresScreen()),
              ),
            ),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.page,
                ),
                itemCount: docs.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final name = d['businessName']?.toString() ?? 'Business';
                  final tagline = d['tagline']?.toString() ?? '';
                  return SizedBox(
                    width: 250,
                    child: SellerCard(
                      name: name,
                      subtitle: tagline,
                      avatarUrl: d['logoUrl']?.toString() ?? '',
                      verified: d['businessVerified'] == true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SellerProfileScreen(
                            sellerId: docs[i].id,
                            sellerName: name,
                          ),
                        ),
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

// ---------------------------------------------------------------------------
// Home screen + bottom navigation
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Bottom-bar tab: 0 Home, 1 Favorites, 2 Chats, 3 Menu. (The centre Sell
  /// button pushes a route rather than switching tabs.)
  int selectedIndex = 0;
  String homeCity = 'All Pakistan';
  String homeSort = 'Newest';
  final searchController = TextEditingController();

  /// The "Recommended for you" grid. Paged so the feed no longer stops dead at
  /// 60 ads. The RAILS above it deliberately keep their own bounded window —
  /// they each show ~10 items drawn from a nationwide sample, so feeding them
  /// from a paged source would leave them showing whatever happened to be on
  /// page one.
  late final PagedListings _feedSource;

  @override
  void initState() {
    super.initState();
    _feedSource = PagedListings(
      query: FirebaseFirestore.instance
          .collection('listings')
          .where('approvalStatus', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true),
      clientFilter: _feedAccepts,
    );
    _feedSource.loadMore();
    // Ensure the profile exists first, then run the one-time location prompt so
    // the two writes don't race (ensureUserDoc does a non-merge set on create).
    // catchError matters: the `verified` sync inside ensureUserDoc can be
    // denied while the ID token's email_verified claim lags the client's view
    // of it (up to an hour after the user clicks the verification link). An
    // unhandled rejection there used to skip the location prompt entirely for
    // that session, on top of raising an async error.
    ensureUserDoc()
        .catchError((_) {})
        .then((_) => maybePromptLocation())
        .catchError((_) {});
    // Somebody who followed a shared link before signing in gets taken there
    // now — an ad or a Ludo board, whichever it was. After the first frame, so
    // the home screen exists underneath and going back returns here rather
    // than to nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resumePendingRoute(context);
    });
    loadFavorites();
    loadBlocked();
    loadPlatformBlockedUsers().then((_) {
      if (mounted) setState(() {});
    });
    loadStaffPermissions().then((_) {
      if (mounted) setState(() {});
    });
    setupPushNotifications();
    // Fold any guest cart (added while logged out) into the account, then keep
    // the badge in sync. Safe no-op when the guest cart is empty.
    mergeGuestCartIntoAccount();
    loadGuestCartCount();
    // Ask for a Play review only when the user is genuinely engaged (see
    // maybeShowReviewPrompt for the configurable eligibility rules). Home is a
    // safe, neutral screen — never checkout / payment / OTP / dispute / error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowReviewPrompt(context);
    });
  }

  @override
  void dispose() {
    _feedSource.dispose();
    searchController.dispose();
    super.dispose();
  }

  /// Which ads belong in the main feed: publicly visible, not from a seller
  /// this user (or the platform) has blocked, and matching the city filter.
  bool _feedAccepts(Listing l) {
    if (!l.isApproved || !l.isPubliclyVisible) return false;
    if (isHiddenSeller(l.userId)) return false;
    if (homeCity != 'All Pakistan' && l.city != homeCity) return false;
    return true;
  }

  /// Creates a `users/{uid}` profile doc the first time we see this account,
  /// so seller profiles can show a "Member since" date.
  Future<void> ensureUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      // Phone from OTP login (user.phoneNumber) or, for email sign-up, the
      // number entered on the form (pendingSignupPhone).
      final phone = (user.phoneNumber?.isNotEmpty == true)
          ? user.phoneNumber!
          : (pendingSignupPhone ?? '');
      pendingSignupPhone = null;
      // Public profile document: no contact PII. Every signed-in user can read
      // this collection (seller pages, Stores rails), and rules cannot filter
      // fields on read.
      // facebookId is Facebook's app-scoped id — unique to this app and useless
      // for looking the person up anywhere else. It lives on the public doc
      // because friend matching is a whereIn query across users, which a
      // private subcollection cannot serve.
      final facebookId = facebookIdOf(user);
      await ref.set({
        'isAnonymous': user.isAnonymous,
        'verified': user.emailVerified,
        'createdAt': Timestamp.now(),
        'facebookId': ?facebookId,
      });
      await savePrivateContact(user.uid, {
        'email': user.email ?? '',
        'phone': phone,
        'updatedAt': Timestamp.now(),
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
            // This shipped on the Play Store telling Android users to change
            // their browser settings.
            'Allow PakBazar to use your location to show nearby ads and help '
            'keep the marketplace safe. You can turn this off anytime in '
            'Settings.',
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

  /// Opens the search screen for [query], scoped to the home city, and
  /// remembers it in the device-local Recent Searches list.
  void openSearch(String query, {String category = '', String? thumbnail}) {
    final q = query.trim();
    if (q.isEmpty) return;
    final city = homeCity == 'All Pakistan' ? null : homeCity;
    addRecentSearch(
      RecentSearch(
        query: q,
        category: category,
        city: city ?? '',
        imageUrl: thumbnail ?? '',
      ),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: q, initialCity: city),
      ),
    );
  }

  Future<void> _pickCity() async {
    final c = await showCityPicker(context, includeAll: true);
    if (!mounted || c == null) return;
    final picked = c == 'All' ? 'All Pakistan' : c;
    setState(() => homeCity = picked);
    // The city is part of the feed's accept test, so previously loaded pages
    // no longer qualify.
    _feedSource.refresh();
    // Auto-save the chosen city to the profile for the admin panel.
    saveUserLocation(city: picked);
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

  // ── Home tab ─────────────────────────────────────────────────────────────

  /// The fixed top area: brand mark, search pill (with the city selector inside
  /// it) and the notification / cart bells.
  Widget _homeHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.page, AppSpacing.sm, AppSpacing.sm, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // The full horizontal lockup (dark green + gold on transparent),
              // which is the variant drawn for light backgrounds — it already
              // contains the wordmark, so no separate "PakBazar" label. In dark
              // mode the artwork sits on a dark slate header, so it gets a soft
              // light plate behind it to stay legible.
              Flexible(
                child: Container(
                  padding: appBrightnessValue == Brightness.dark
                      ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
                      : EdgeInsets.zero,
                  decoration: appBrightnessValue == Brightness.dark
                      ? BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: AppRadius.rSm,
                        )
                      : null,
                  child: Semantics(
                    label: 'PakBazar',
                    child: Image.asset(
                      'assets/pakbazar_logo.png',
                      height: 28,
                      fit: BoxFit.contain,
                      alignment: AlignmentDirectional.centerStart,
                      errorBuilder: (context, error, stack) => Text(
                        'PakBazar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (luckyDrawActive())
                IconButton(
                  icon: const Icon(Icons.card_giftcard, color: kGold),
                  tooltip: 'Invite & Win PKR 100,000',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const InviteFriendsScreen(),
                    ),
                  ),
                ),
              // Favourites lives here rather than in the bottom bar, which is
              // reserved for Home / Chats / Sell / My Ads / Menu. It is also
              // listed under Menu → Buying.
              IconButton(
                icon: const Icon(Icons.favorite_border),
                tooltip: 'Favorites',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                ),
              ),
              const CartBell(),
              const NotificationBell(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: AppSearchBar(
              controller: searchController,
              hintText: 'Search in PakBazar',
              onSubmitted: openSearch,
              locationLabel: homeCity == 'All Pakistan' ? 'Pakistan' : homeCity,
              onLocationTap: _pickCity,
            ),
          ),
        ],
      ),
    );
  }

  /// One `Popular in <category>` rail derived from the already-loaded feed, so
  /// it costs no extra Firestore reads or indexes.
  Widget _categoryRail(
    String title,
    String category,
    List<Listing> pool, {
    IconData? icon,
  }) {
    final items = pool
        .where((l) => l.category == category && !l.isSold)
        .take(12)
        .toList();
    return HorizontalListingSection(
      title: title,
      icon: icon,
      listings: items,
      minItems: 3,
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CategoryScreen(title: category)),
      ),
    );
  }

  Widget _homeTab() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _homeHeader(),
          Divider(height: 1, color: AppColors.borderSoft),
          Expanded(child: _homeFeed()),
        ],
      ),
    );
  }

  Widget _homeFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('approvalStatus', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(60)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorStateWidget(
            message: 'We couldn’t load the marketplace. Pull down to retry.',
            onRetry: () => setState(() {}),
          );
        }

        var listings =
            (snapshot.data?.docs ?? [])
                .map((d) => Listing.fromDoc(d))
                .where((l) => l.isApproved && l.isPubliclyVisible)
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

        // Everything visible to this user, before the city filter — the
        // category rails use this so they stay populated nationwide.
        if (blockedUserIds.isNotEmpty || platformBlockedUserIds.isNotEmpty) {
          listings = listings.where((l) => !isHiddenSeller(l.userId)).toList();
        }
        final nationwide = listings;
        final nearby = homeCity == 'All Pakistan'
            ? const <Listing>[]
            : listings.where((l) => l.city == homeCity).toList();
        final featured = nationwide
            .where((l) => l.isCurrentlyFeatured)
            .take(12)
            .toList();
        final topDeals =
            nationwide.where((l) => !l.isSold && l.views > 0).toList()
              ..sort((a, b) => b.views.compareTo(a.views));

        return RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            // Actually reload. This used to await a 500ms timer and no data,
            // so pulling down looked like a refresh without being one.
            await _feedSource.refresh();
            if (mounted) setState(() {});
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gridWidth = constraints.maxWidth - AppSpacing.page * 2;
              final columns = MarketplaceListingCard.columnsFor(
                constraints.maxWidth,
              );
              final delegate = MarketplaceListingCard.gridDelegate(
                context,
                availableWidth: gridWidth,
                columns: columns,
              );

              return AnimatedBuilder(
                animation: _feedSource,
                builder: (context, _) {
                  // Sorting applies to what has been loaded; scrolling widens
                  // the set. Same behaviour as before, except the window is no
                  // longer capped at 60.
                  final pagedFeed = _feedSource.items.toList()
                    ..sort((a, b) {
                      if (a.isSold != b.isSold) return a.isSold ? 1 : -1;
                      if (a.isCurrentlyFeatured != b.isCurrentlyFeatured) {
                        return a.isCurrentlyFeatured ? -1 : 1;
                      }
                      switch (homeSort) {
                        case 'Price: Low to High':
                          return parsePrice(
                            a.price,
                          ).compareTo(parsePrice(b.price));
                        case 'Price: High to Low':
                          return parsePrice(
                            b.price,
                          ).compareTo(parsePrice(a.price));
                        default:
                          final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                          final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                          return bt.compareTo(at);
                      }
                    });

                  return InfiniteScrollTrigger(
                    onLoadMore: _feedSource.loadMore,
                    child: CustomScrollView(
                      slivers: [
                        const SliverToBoxAdapter(child: LuckyDrawBanner()),
                        const SliverToBoxAdapter(child: VerifyBanner()),
                        const SliverToBoxAdapter(child: HomeCategoryStrip()),
                        const SliverToBoxAdapter(child: WhatsNewSection()),
                        SliverToBoxAdapter(
                          child: RecentSearchesSection(
                            onOpen: (s) =>
                                openSearch(s.query, category: s.category),
                          ),
                        ),
                        const SliverToBoxAdapter(child: ContinueBrowsingRail()),
                        if (featuringEnabled.value)
                          SliverToBoxAdapter(
                            child: HorizontalListingSection(
                              title: tr('home.featured', 'Featured on PakBazar'),
                              icon: Icons.star,
                              iconColor: kGold,
                              listings: featured,
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: HorizontalListingSection(
                            title: tr('home.topDeals', 'Top deals'),
                            subtitle: 'Most viewed this week',
                            icon: Icons.local_fire_department_outlined,
                            iconColor: Colors.deepOrange,
                            listings: topDeals.take(10).toList(),
                            minItems: 3,
                          ),
                        ),
                        if (nearby.isNotEmpty)
                          SliverToBoxAdapter(
                            child: HorizontalListingSection(
                              title: 'Nearby in $homeCity',
                              icon: Icons.near_me_outlined,
                              listings: nearby.take(12).toList(),
                              minItems: 3,
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: _categoryRail(
                            'Popular in Motors',
                            'Motors',
                            nationwide,
                            icon: Icons.directions_car_outlined,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _categoryRail(
                            'Popular in Properties',
                            'Properties',
                            nationwide,
                            icon: Icons.home_work_outlined,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _categoryRail(
                            'Latest mobile phones',
                            'Mobiles & Tablets',
                            nationwide,
                            icon: Icons.smartphone_outlined,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _categoryRail(
                            'Trending electronics',
                            'Electronics',
                            nationwide,
                            icon: Icons.devices_other_outlined,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _categoryRail(
                            'Fashion & essentials',
                            'Garments',
                            nationwide,
                            icon: Icons.checkroom_outlined,
                          ),
                        ),
                        const SliverToBoxAdapter(child: DealsRail()),
                        const SliverToBoxAdapter(child: FollowingRail()),
                        if (featuringEnabled.value)
                          const SliverToBoxAdapter(
                            child: FeaturedBusinessesRail(),
                          ),

                        // ── Recommended feed ──
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.section),
                        ),
                        SliverToBoxAdapter(
                          child: SectionHeader(
                            title: tr('home.recommended', 'Recommended for you'),
                            actionLabel: '',
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.page,
                              0,
                              AppSpacing.page,
                              AppSpacing.md,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _sortRow()),
                        if (pagedFeed.isEmpty && _feedSource.isLoading)
                          SliverPadding(
                            padding: AppSpacing.pageH,
                            sliver: SliverGrid(
                              gridDelegate: delegate,
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => const ListingCardSkeleton(),
                                childCount: columns * 3,
                              ),
                            ),
                          )
                        else if (pagedFeed.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: EmptyStateWidget(
                                icon: Icons.storefront_outlined,
                                title: homeCity == 'All Pakistan'
                                    ? 'No ads yet'
                                    : 'Nothing in $homeCity yet',
                                subtitle: homeCity == 'All Pakistan'
                                    ? 'Be the first to post an ad on PakBazar.'
                                    : 'Try another city, or post the first ad here.',
                                actionLabel: tr('action.postAd', 'Post an ad'),
                                onAction: _postAd,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: AppSpacing.pageH,
                            sliver: SliverGrid(
                              gridDelegate: delegate,
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => MarketplaceListingCard(
                                  listing: pagedFeed[i],
                                ),
                                childCount: pagedFeed.length,
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: PagedListingFooter(
                            source: _feedSource,
                            onRetry: _feedSource.loadMore,
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.navClearance),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _sortRow() {
    String label() => switch (homeSort) {
      'Price: Low to High' => 'Price: low to high',
      'Price: High to Low' => 'Price: high to low',
      _ => 'Newest first',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Fresh ads from across PakBazar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PopupMenuButton<String>(
            initialValue: homeSort,
            onSelected: (v) => setState(() => homeSort = v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'Newest', child: Text('Newest first')),
              PopupMenuItem(
                value: 'Price: Low to High',
                child: Text('Price: low to high'),
              ),
              PopupMenuItem(
                value: 'Price: High to Low',
                child: Text('Price: high to low'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.rPill,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    label(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Scaffold ─────────────────────────────────────────────────────────────

  /// Tabs the user has opened at least once. Home (0) is always built.
  final Set<int> _visitedTabs = {0};

  /// Builds a tab only after it has first been selected, then keeps it in the
  /// IndexedStack so its state and scroll position survive tab switches.
  Widget _lazyTab(int index, Widget Function() build) {
    if (selectedIndex == index) _visitedTabs.add(index);
    return _visitedTabs.contains(index) ? build() : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each visited tab's scroll position and streams alive,
    // so switching back is instant and doesn't re-read Firestore. Tabs are
    // built LAZILY (see _visitedTabs) — otherwise Favorites, Chats and Menu
    // would each open their Firestore listeners at launch, before the user has
    // even looked at them.
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [
          _homeTab(),
          _lazyTab(1, () => const ChatsScreen()),
          _lazyTab(2, () => const MyAdsScreen()),
          _lazyTab(3, () => const ProfileScreen()),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: selectedIndex,
        onTap: (i) => setState(() => selectedIndex = i),
        onSell: _postAd,
        sellLabel: tr('nav.sell'),
        destinations: [
          AppNavDestination(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: tr('nav.home'),
          ),
          AppNavDestination(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble,
            label: tr('nav.chats'),
          ),
          AppNavDestination(
            icon: Icons.list_alt_outlined,
            activeIcon: Icons.list_alt,
            label: tr('nav.myAds'),
          ),
          AppNavDestination(
            icon: Icons.menu,
            activeIcon: Icons.menu_open,
            label: tr('nav.menu'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse + search + filters
// ---------------------------------------------------------------------------
