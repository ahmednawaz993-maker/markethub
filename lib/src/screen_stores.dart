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
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: 'Please try again.',
            );
          }
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
                    backgroundImage: logo.isNotEmpty
                        ? NetworkImage(logo)
                        : null,
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

/// A distinct accent colour per category so the grid reads as colourful and
/// catchy. Titles map to a curated hue; anything unlisted cycles through the
/// same palette so new categories still get a sensible colour.
const Map<String, Color> _categoryColors = {
  'Food & Grocery': Color(0xFFF4511E), // deep orange
  'Motors': Color(0xFF1E88E5), // blue
  'Commute & Rides': Color(0xFF00897B), // teal
  'Properties': Color(0xFF43A047), // green
  'Mobiles & Tablets': Color(0xFF3949AB), // indigo
  'Electronics': Color(0xFF00ACC1), // cyan
  'Home & Furniture': Color(0xFF8D6E63), // brown
  'Crockery': Color(0xFFFB8C00), // amber
  'Garments': Color(0xFFD81B60), // pink
  'Men Essentials': Color(0xFF546E7A), // blue grey
  'Women Essentials': Color(0xFF8E24AA), // purple
  'Kids Essentials': Color(0xFF039BE5), // light blue
  'Jobs': Color(0xFF5E35B1), // deep purple
  'Services': Color(0xFFE53935), // red
  'Pets': Color(0xFF7CB342), // light green
  'Sports & Hobbies': Color(0xFFC0CA33), // lime
  'Business & Industrial': Color(0xFF6D4C41), // dark brown
  'Community': Color(0xFF00838F), // dark cyan
};

const List<Color> _categoryPalette = [
  Color(0xFFF4511E),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
  Color(0xFFFB8C00),
  Color(0xFFD81B60),
  Color(0xFF3949AB),
];

Color _categoryAccent(String title, int index) =>
    _categoryColors[title] ?? _categoryPalette[index % _categoryPalette.length];

/// Full grid of every category, each rendered as a colourful icon card.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cats = appCategories.where((c) => c.title != 'All').toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('All Categories')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.80,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          final accent = _categoryAccent(c.title, i);
          return Material(
            // Opaque light tile so the title/subtitle are readable over the
            // navy gradient (a translucent tint let the navy bleed through).
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryScreen(title: c.title),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Gradient icon badge — the catchy focal point.
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent,
                            Color.lerp(accent, Colors.black, 0.28)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(c.icon, color: Colors.white, size: 27),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      c.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Home rail of paid Featured Businesses (admin-approved). Hidden when empty.
