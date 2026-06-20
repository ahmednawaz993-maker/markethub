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
      appBar: AppBar(title: Text(sellerName.isEmpty ? 'Store' : sellerName)),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
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
              final verified = data['verified'] == true;
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

              Widget chip(String text, Color bg) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );

              return Column(
                children: [
                  // Branded shop banner: cover (or gradient) with the logo and
                  // store name overlaid, plus BUSINESS and category chips.
                  SizedBox(
                    height: 168,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coverUrl.isNotEmpty)
                          Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: kPakGreen),
                          )
                        else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [kPakGreen, kPakGreenLight],
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.62),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 12,
                          right: 12,
                          child: Row(
                            children: [
                              if (isBusiness) chip('BUSINESS', kPakGreen),
                              const Spacer(),
                              if (storeCategory.isNotEmpty)
                                chip(storeCategory, kGold),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              CircleAvatar(
                                radius: 34,
                                backgroundColor: Colors.white,
                                backgroundImage: logoUrl.isNotEmpty
                                    ? NetworkImage(logoUrl)
                                    : null,
                                child: logoUrl.isEmpty
                                    ? Icon(
                                        isBusiness
                                            ? Icons.storefront
                                            : Icons.person,
                                        size: 34,
                                        color: kPakGreen,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 21,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (verified ||
                                            data['idVerified'] == true) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.verified,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (isBusiness && tagline.isNotEmpty)
                                      Text(
                                        tagline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Rating, member-since and actions.
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              StarRating(rating: avg, count: count, size: 16),
                              const Spacer(),
                              if (memberSince.isNotEmpty)
                                Text(
                                  memberSince,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          if (!isSelf) ...[
                            const SizedBox(height: 10),
                            _FollowButton(
                              sellerId: sellerId,
                              sellerName: displayName,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        showReviewDialog(context, sellerId),
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
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Products',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('listings')
                  .where('userId', isEqualTo: sellerId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final listings = snapshot.data!.docs
                    .map((d) => Listing.fromDoc(d))
                    .toList()
                  ..sort((a, b) {
                    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bt.compareTo(at);
                  });

                if (listings.isEmpty) {
                  return const Center(
                    child: Text(
                      'No ads from this seller',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: listings.length,
                  itemBuilder: (context, i) => FeedAdCard(listing: listings[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
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
          ? const EmptyState(
              icon: Icons.people_outline,
              title: 'Please log in',
            )
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
                      .snapshots(),
                  builder: (context, ls) {
                    if (!ls.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final listings =
                        ls.data!.docs.map((d) => Listing.fromDoc(d)).toList()
                          ..sort((a, b) {
                            final at =
                                a.createdAt?.millisecondsSinceEpoch ?? 0;
                            final bt =
                                b.createdAt?.millisecondsSinceEpoch ?? 0;
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
                      padding: const EdgeInsets.all(16),
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
