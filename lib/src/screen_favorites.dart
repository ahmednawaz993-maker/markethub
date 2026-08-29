part of '../main.dart';

// Saved / favorite ads.

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
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

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.favorite_border,
              title: 'No favorites yet',
              subtitle: 'Tap the heart on any ad to save it here.',
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
              return ListingCard(listing: Listing.fromDoc(docs[index]));
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

/// Lets a user set a public display name (shown on their ads instead of their
/// email address, for privacy).
