part of '../main.dart';

// Seller profile and following.

class SellerProfileScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;

  const SellerProfileScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(sellerId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          String memberSince = '';
          final created = data['createdAt'];
          if (created is Timestamp) {
            final d = created.toDate();
            memberSince = 'Member since ${d.month}/${d.year}';
          }
          final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
          final sum = (data['ratingSum'] as num?)?.toDouble() ?? 0;
          final avg = count > 0 ? sum / count : 0.0;
          final verified =
              data['verified'] == true || data['idVerified'] == true;
          final isBusiness = data['isBusiness'] == true;
          final businessName = data['businessName']?.toString() ?? '';
          final tagline = data['tagline']?.toString() ?? '';
          final logoUrl = data['logoUrl']?.toString() ?? '';
          final coverUrl = data['coverUrl']?.toString() ?? '';
          final displayName = (isBusiness && businessName.isNotEmpty)
              ? businessName
              : (sellerName.isEmpty ? 'Seller' : sellerName);
          final me = FirebaseAuth.instance.currentUser;
          final isSelf = me != null && me.uid == sellerId;
          final storeCategory = data['storeCategory']?.toString() ?? '';
          final storePolicies = data['storePolicies']?.toString() ?? '';

          return CustomScrollView(
            slivers: [
              // Collapsing storefront hero: full-bleed cover with the logo,
              // chips and store name; on scroll it minimises into a compact
              // branded app bar so the products get the full screen.
              _StoreHeroBar(
                displayName: displayName,
                tagline: tagline,
                logoUrl: logoUrl,
                coverUrl: coverUrl,
                isBusiness: isBusiness,
                verified: verified,
                storeCategory: storeCategory,
              ),
              SliverToBoxAdapter(
                child: _StoreInfoCard(
                  sellerId: sellerId,
                  sellerName: sellerName,
                  displayName: displayName,
                  tagline: tagline,
                  isBusiness: isBusiness,
                  avg: avg,
                  count: count,
                  memberSince: memberSince,
                  storePolicies: storePolicies,
                  isSelf: isSelf,
                ),
              ),
              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Products',
                  icon: Icons.inventory_2_outlined,
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.lg,
                    AppSpacing.page,
                    AppSpacing.md,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildProducts(context)),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.navClearance),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProducts(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('userId', isEqualTo: sellerId)
          .where('approvalStatus', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Couldn’t load ads. Please try again.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final listings =
            snapshot.data!.docs
                .map((d) => Listing.fromDoc(d))
                .where((l) => l.isApproved)
                .toList()
              ..sort((a, b) {
                final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                return bt.compareTo(at);
              });

        if (listings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: EmptyStateWidget(
              icon: Icons.inventory_2_outlined,
              title: 'No products in this store yet',
              subtitle:
                  'Check back soon — this seller is just getting started.',
            ),
          );
        }

        // Group the seller's products by category so a store with items across
        // several categories shows them as sections — all of the seller's
        // products live together here in their store.
        final groups = <String, List<Listing>>{};
        for (final l in listings) {
          final c = l.category.isEmpty ? 'Other' : l.category;
          (groups[c] ??= []).add(l);
        }
        final cats = groups.keys.toList()..sort();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final cat in cats) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('(${groups[cat]!.length})', style: AppType.caption),
                  ],
                ),
              ),
              Padding(
                padding: AppSpacing.pageH,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = MarketplaceListingCard.columnsFor(
                      MediaQuery.of(context).size.width,
                    );
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // Same delegate as every other listing grid, so the
                      // store's cards match the feed exactly.
                      gridDelegate: MarketplaceListingCard.gridDelegate(
                        context,
                        availableWidth: constraints.maxWidth,
                        columns: columns,
                      ),
                      itemCount: groups[cat]!.length,
                      itemBuilder: (context, i) =>
                          _StoreProductCard(listing: groups[cat]![i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        );
      },
    );
  }
}

/// The collapsing storefront hero. Expanded it's a full-bleed cover with the
/// logo, chips and store name; as the user scrolls it minimises (parallax +
/// fade) into a compact branded app bar, giving products the full screen.
class _StoreHeroBar extends StatelessWidget {
  final String displayName;
  final String tagline;
  final String logoUrl;
  final String coverUrl;
  final bool isBusiness;
  final bool verified;
  final String storeCategory;

  const _StoreHeroBar({
    required this.displayName,
    required this.tagline,
    required this.logoUrl,
    required this.coverUrl,
    required this.isBusiness,
    required this.verified,
    required this.storeCategory,
  });

  Widget _chip(String text, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
      ],
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      stretch: true,
      backgroundColor: kPakGreen,
      foregroundColor: Colors.white,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
        // Leave room on the left for the back button (collapsed) and on the
        // right for the logo (expanded).
        titlePadding: const EdgeInsetsDirectional.only(
          start: 54,
          bottom: 14,
          end: 92,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 16, color: Colors.white),
            ],
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl.isNotEmpty)
              Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _HeroGradient(),
              )
            else
              const _HeroGradient(),
            // Darken toward the bottom so the white title/logo stay legible.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.66),
                  ],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    if (isBusiness) _chip('BUSINESS', kPakGreen),
                    const Spacer(),
                    if (storeCategory.isNotEmpty) _chip(storeCategory, kGold),
                  ],
                ),
              ),
            ),
            // Store logo, bottom-right, with a white ring + shadow.
            Positioned(
              right: 14,
              bottom: 12,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white,
                  backgroundImage: logoUrl.isNotEmpty
                      ? NetworkImage(logoUrl)
                      : null,
                  child: logoUrl.isEmpty
                      ? Icon(
                          isBusiness ? Icons.storefront : Icons.person,
                          size: 32,
                          color: kPakGreen,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroGradient extends StatelessWidget {
  const _HeroGradient();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [kPakGreen, kPakGreenLight],
      ),
    ),
  );
}

/// The store's rating, tagline, follow / review actions and policies, in a
/// clean card that sits just under the hero.
class _StoreInfoCard extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  final String displayName;
  final String tagline;
  final bool isBusiness;
  final double avg;
  final int count;
  final String memberSince;
  final String storePolicies;
  final bool isSelf;

  const _StoreInfoCard({
    required this.sellerId,
    required this.sellerName,
    required this.displayName,
    required this.tagline,
    required this.isBusiness,
    required this.avg,
    required this.count,
    required this.memberSince,
    required this.storePolicies,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBusiness && tagline.isNotEmpty) ...[
                  Text(
                    tagline,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    StarRating(rating: avg, count: count, size: 16),
                    const Spacer(),
                    if (memberSince.isNotEmpty)
                      Text(
                        memberSince,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                if (!isSelf) ...[
                  const SizedBox(height: 10),
                  _FollowButton(sellerId: sellerId, sellerName: displayName),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showReviewDialog(context, sellerId),
                          icon: const Icon(Icons.rate_review),
                          label: const Text('Write a review'),
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReviewsScreen(
                                  sellerId: sellerId,
                                  sellerName: sellerName,
                                ),
                              ),
                            ),
                            child: Text('See $count reviews'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (storePolicies.isNotEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rule, size: 18, color: kPakGreen),
                      SizedBox(width: 6),
                      Text(
                        'Store policies',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(storePolicies),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TrustSafetyScreen(),
                      ),
                    ),
                    child: const Text(
                      "This store also follows PakBazar's platform rules ›",
                      style: TextStyle(
                        fontSize: 12,
                        color: kPakGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A premium product tile for the storefront grid — a clean image-forward card
/// with a prominent price, a single clear title line, a condition chip and the
/// location. Deliberately less busy than the feed's [FeedAdCard] so a store
/// reads like a polished catalogue.
/// A product card in a seller's storefront grid.
///
/// Kept as a name so the store layout keeps working; the implementation is the
/// shared [MarketplaceListingCard], so a seller's catalogue looks identical to
/// the home feed and search results.
class _StoreProductCard extends StatelessWidget {
  final Listing listing;
  const _StoreProductCard({required this.listing});

  @override
  Widget build(BuildContext context) =>
      MarketplaceListingCard(listing: listing);
}

/// Follow / unfollow toggle for a seller, with a live follower count. Follows
/// are denormalised both ways: `users/{sellerId}/followers/{myUid}` powers the
/// count, and `users/{myUid}/following/{sellerId}` powers the Following feed.
class _FollowButton extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const _FollowButton({required this.sellerId, required this.sellerName});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _busy = false;

  Future<void> _toggle(bool currentlyFollowing) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    final fs = FirebaseFirestore.instance;
    final followerDoc = fs
        .collection('users')
        .doc(widget.sellerId)
        .collection('followers')
        .doc(uid);
    final followingDoc = fs
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(widget.sellerId);
    try {
      final batch = fs.batch();
      if (currentlyFollowing) {
        batch.delete(followerDoc);
        batch.delete(followingDoc);
      } else {
        batch.set(followerDoc, {
          'followerUid': uid,
          'createdAt': Timestamp.now(),
        });
        batch.set(followingDoc, {
          'sellerName': widget.sellerName,
          'createdAt': Timestamp.now(),
        });
      }
      await batch.commit();
      if (mounted && !currentlyFollowing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You'll find their latest ads under Following"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final followerCol = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.sellerId)
        .collection('followers');
    return StreamBuilder<QuerySnapshot>(
      stream: followerCol.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final count = docs.length;
        final following = docs.any((d) => d.id == uid);
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: following
                  ? OutlinedButton.icon(
                      onPressed: _busy ? null : () => _toggle(true),
                      icon: const Icon(Icons.how_to_reg),
                      label: const Text('Following'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _busy ? null : () => _toggle(false),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Follow'),
                    ),
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$count follower${count == 1 ? '' : 's'}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shows the latest ads from sellers the current user follows.
class FollowingScreen extends StatelessWidget {
  const FollowingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: uid == null
          ? const EmptyState(icon: Icons.people_outline, title: 'Please log in')
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('following')
                  .orderBy('createdAt', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ids = snap.data!.docs.map((d) => d.id).toList();
                if (ids.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline,
                    title: "You're not following anyone yet",
                    subtitle:
                        "Open a seller's profile and tap Follow to see their "
                        'latest ads here.',
                  );
                }
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('listings')
                      .where('userId', whereIn: ids)
                      .where('approvalStatus', isEqualTo: 'approved')
                      .snapshots(),
                  builder: (context, ls) {
                    if (ls.hasError) {
                      return Center(
                        child: Text(
                          'Couldn’t load ads. Please try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.onNavyMuted),
                        ),
                      );
                    }
                    if (!ls.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final listings =
                        ls.data!.docs
                            .map((d) => Listing.fromDoc(d))
                            .where((l) => l.isApproved)
                            .toList()
                          ..sort((a, b) {
                            final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                            final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                            return bt.compareTo(at);
                          });
                    if (listings.isEmpty) {
                      return const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No ads yet',
                        subtitle:
                            "Sellers you follow haven't posted anything yet.",
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.lg,
                        AppSpacing.page,
                        AppSpacing.navClearance,
                      ),
                      itemCount: listings.length,
                      itemBuilder: (context, i) =>
                          ListingCard(listing: listings[i]),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------
