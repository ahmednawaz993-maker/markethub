part of '../main.dart';

// Stores and all-categories browsing.

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stores & Businesses')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('isBusiness', isEqualTo: true)
            .limit(60)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorStateWidget(
              message: 'We couldn’t load stores right now.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.storefront_outlined,
              title: 'No stores yet',
              subtitle: 'Business accounts will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              // Never fall back to the email address: this list is public, so
              // that printed a stranger's email as their shop name.
              final name = d['businessName']?.toString().isNotEmpty == true
                  ? d['businessName'].toString()
                  : (d['displayName']?.toString().isNotEmpty == true
                        ? d['displayName'].toString()
                        : 'Business');
              final featured = d['featuredBusiness'] == true;
              return SellerCard(
                name: name,
                subtitle: d['tagline']?.toString() ?? '',
                avatarUrl: d['logoUrl']?.toString() ?? '',
                verified: d['businessVerified'] == true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (featured)
                      const Icon(Icons.star, color: kGold, size: 18),
                    Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerProfileScreen(
                      sellerId: docs[i].id,
                      sellerName: name,
                    ),
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

/// A distinct accent colour per category so the grid reads as colourful and
/// catchy. The colour is admin-editable and lives on the category itself; the
/// curated defaults and the palette fallback are in catalog.dart.
Color _categoryAccent(String title, int index) => categoryAccent(title, index);

/// Full grid of every category, each rendered as a colourful icon card.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: categoriesVersion,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final cats = visibleCategories.where((c) => c.title != 'All').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('All Categories')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Wider screens get more columns rather than stretched tiles.
          final columns = constraints.maxWidth >= 900
              ? 5
              : (constraints.maxWidth >= 600 ? 4 : 3);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.84,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final accent = _categoryAccent(c.title, i);
              return AppCard(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                  horizontal: AppSpacing.sm,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryScreen(title: c.title),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A flat tinted badge — the category's colour without the
                    // heavy gradient/shadow the rest of the app avoids.
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.rMd,
                        color: accent.withValues(alpha: 0.12),
                      ),
                      child: Icon(c.icon, color: accent, size: 24),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      c.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.subcategories.length} subcategories',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Home rail of paid Featured Businesses (admin-approved). Hidden when empty.
