part of '../main.dart';

// Saved / favorite ads.

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  /// Live listings for the ads saved here, by id.
  ///
  /// A favourite stores a COPY of the ad as it was when the heart was
  /// tapped. Months later that copy still shows the old price and still says
  /// the item is for sale — on the one screen people open specifically to
  /// check whether the thing they wanted is still there and still that price.
  /// The copy is what paints first, so the list appears instantly; this then
  /// replaces it with the truth.
  final Map<String, Listing> _live = {};

  /// Saved ads that no longer exist, so they can be marked rather than
  /// silently kept at a price nobody can buy them for.
  final Set<String> _gone = {};

  /// The set of ids the last refresh covered, so a stream tick that changes
  /// nothing does not re-read every listing.
  String _refreshedFor = '';

  /// Re-reads the saved ads, in batches, and repaints with whatever came back.
  Future<void> _refresh(List<String> ids) async {
    final key = ids.join(',');
    if (key == _refreshedFor) return;
    _refreshedFor = key;
    final found = <String, Listing>{};
    // Only ids we actually got an answer about. A batch can fail as a whole —
    // one ad going back into review makes it unreadable, and Firestore
    // refuses the entire query rather than omitting that document. Treating a
    // failed batch as "these are all gone" would put No longer available on
    // ads that are merely being re-checked.
    final answered = <String>{};
    for (final batch in idBatches(ids)) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('listings')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        answered.addAll(batch);
        for (final d in snap.docs) {
          found[d.id] = Listing.fromDoc(d);
        }
      } catch (_) {
        // Offline, or one of these is unreadable. The saved copies stay on
        // screen, which beats an error page over a list already visible.
        // The next batch is still worth trying.
      }
    }
    // Nothing came back at all — offline, most likely. Forget that this set
    // was attempted so the next tick tries again rather than leaving stale
    // copies on screen for the rest of the session.
    if (answered.isEmpty) _refreshedFor = '';
    if (!mounted) return;
    setState(() {
      _live
        ..clear()
        ..addAll(found);
      _gone
        ..clear()
        ..addAll(answered.where((id) => !found.containsKey(id)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favorites')),
        body: const EmptyStateWidget(
          icon: Icons.favorite_border,
          title: 'Log in to see your favorites',
          subtitle: 'Saved ads follow you across every device.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('favorites')
            // Capped: somebody who favourites everything they browse should
            // not end up with a screen that takes longer to open every week.
            .limit(kMyListCap)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateWidget(
              message: 'We couldn’t load your favorites. Please try again.',
              onRetry: () => setState(() {}),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = byNewestSaved(
            snapshot.data!.docs,
            (d) =>
                ((d.data() as Map)['savedAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0,
          );

          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.favorite_border,
              title: 'No favorites yet',
              subtitle: 'Tap the heart on any ad to save it here.',
            );
          }

          // After the frame, so the saved copies paint immediately and the
          // re-read never delays what the user is waiting to see.
          final ids = docs.map((d) => d.id).toList();
          WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(ids));

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final id = docs[index].id;
              final saved = Listing.fromDoc(docs[index]);
              if (_gone.contains(id)) {
                return _RemovedFavorite(
                  title: saved.title,
                  onRemove: () => FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('favorites')
                      .doc(id)
                      .delete(),
                );
              }
              return ListingCard(listing: _live[id] ?? saved);
            },
          );
        },
      ),
    );
  }
}

/// A saved ad that has since been taken down.
///
/// Leaving the stored copy on screen would keep offering an item nobody can
/// buy, at a price that no longer exists.
class _RemovedFavorite extends StatelessWidget {
  final String title;
  final VoidCallback onRemove;

  const _RemovedFavorite({required this.title, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.remove_shopping_cart_outlined,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isEmpty ? 'A saved ad' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.cardTitle.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text('No longer available', style: AppType.caption),
              ],
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

/// Lets a user set a public display name (shown on their ads instead of their
/// email address, for privacy).
