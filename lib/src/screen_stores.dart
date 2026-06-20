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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront,
              title: 'No stores yet',
              subtitle: 'Business accounts will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final name = d['businessName']?.toString().isNotEmpty == true
                  ? d['businessName'].toString()
                  : (d['email']?.toString() ?? 'Business');
              final tagline = d['tagline']?.toString() ?? '';
              final logo = d['logoUrl']?.toString() ?? '';
              final featured = d['featuredBusiness'] == true;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: kPakGreen.withValues(alpha: 0.12),
                    backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
                    child: logo.isEmpty
                        ? const Icon(Icons.storefront, color: kPakGreen)
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (featured) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, color: kGold, size: 16),
                      ],
                    ],
                  ),
                  subtitle: tagline.isEmpty ? null : Text(tagline),
                  trailing: const Icon(Icons.chevron_right),
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
          );
        },
      ),
    );
  }
}

/// Full grid of every category.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cats = appCategories.where((c) => c.title != 'All').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('All Categories')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.95,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CategoryScreen(title: c.title)),
            ),
            child: Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: kPakGreen.withValues(alpha: 0.12),
                    child: Icon(c.icon, color: kPakGreen, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      c.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Home rail of paid Featured Businesses (admin-approved). Hidden when empty.
