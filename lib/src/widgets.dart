part of '../main.dart';

// Reusable UI widgets shared across screens.

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen flag-green gradient with a faint crescent-and-star motif.
/// Rendered once behind every route via [MaterialApp.builder]; scaffolds are
/// transparent so this shows through on every page.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kPakGreenDeep, kPakGreen, kPakGreenDeep],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Crescent + star watermark (subtle, premium feel).
          Positioned(
            top: 60,
            right: -30,
            child: Opacity(
              opacity: 0.06,
              child: Transform.rotate(
                angle: 0.35,
                child: const Icon(
                  Icons.nightlight_round,
                  size: 280,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 90,
            right: 150,
            child: Opacity(
              opacity: 0.06,
              child: Icon(Icons.star, size: 110, color: Colors.white),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// Comprehensive list of Pakistani cities and towns (big and small), across all
// provinces, ICT, AJK and Gilgit-Baltistan. Kept alphabetical for the picker.
class StarRating extends StatelessWidget {
  final double rating;
  final double size;
  final int? count;
  final Color color;

  const StarRating({
    super.key,
    required this.rating,
    this.size = 16,
    this.count,
    this.color = kGold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: size,
            color: color,
          ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            count == 0
                ? 'No reviews'
                : '${rating.toStringAsFixed(1)} ($count)',
            style: TextStyle(fontSize: size * 0.8, color: Colors.grey[700]),
          ),
        ],
      ],
    );
  }
}

/// Adds or updates the current user's review of a seller and keeps the seller's
/// aggregate rating (ratingSum/ratingCount on their user doc) consistent.
class FocusableTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  final BorderRadius borderRadius;

  const FocusableTap({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) {
        setState(() => _focused = value);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _focused ? kGold : Colors.transparent,
            width: 3,
          ),
        ),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Opens a searchable, full-height city picker. Returns the chosen city, or
/// null if dismissed. Much friendlier on mobile than a 190-item dropdown.
Future<String?> showCityPicker(
  BuildContext context, {
  bool includeAll = false,
}) {
  final options = [if (includeAll) 'All', ...(pakistanCities.toList()..sort())];

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = options
              .where((c) => c.toLowerCase().contains(query.toLowerCase()))
              .toList();

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    'Select City',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search city...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No city found'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final city = filtered[index];
                              return ListTile(
                                title: Text(city),
                                onTap: () => Navigator.pop(context, city),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// A tap-to-open city field that mirrors a form dropdown but uses the
/// searchable [showCityPicker].
class CitySelector extends StatelessWidget {
  final String value;
  final String label;
  final bool includeAll;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const CitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'City',
    this.includeAll = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final selected = await showCityPicker(
                context,
                includeAll: includeAll,
              );
              if (selected != null) onChanged(selected);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_city, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(value)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// A "SOLD" overlay for sold listings. Must be placed inside a Stack.
class SoldTag extends StatelessWidget {
  const SoldTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: -0.14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'SOLD',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// A compact ad card used in the horizontal Home rails.
class HorizontalAdCard extends StatelessWidget {
  final Listing listing;

  const HorizontalAdCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final img = listing.galleryImages;
    final w = MediaQuery.of(context).size.width;
    // Narrower cards on phones so ~2 peek into view and feel app-like.
    final cardWidth = w < 600 ? (w * 0.44).clamp(150.0, 190.0) : 220.0;

    return FocusableTap(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
      ),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(6),
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: img.isNotEmpty
                          ? Image.network(
                              img.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Container(
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 40),
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.grey.shade300,
                              child: const Center(
                                child: Icon(Icons.image, size: 40),
                              ),
                            ),
                    ),
                    if (listing.isCurrentlyFeatured)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kGold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FEATURED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    if (listing.isSold) const SoldTag(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      priceLabel(listing),
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      listing.city.isEmpty ? listing.location : listing.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal rail of ads fed by a Firestore [stream]. Hides itself
/// entirely when the stream has no results (so empty sections never show).
class AdsRail extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Stream<QuerySnapshot> stream;

  const AdsRail({
    super.key,
    required this.title,
    required this.stream,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final listings =
            snapshot.data!.docs.map((d) => Listing.fromDoc(d)).toList();
        if (listings.isEmpty) return const SizedBox.shrink();
        final phone = isPhone(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: phone ? 19 : 22),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: phone ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: phone ? 208 : 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: listings.length,
                itemBuilder: (context, index) =>
                    HorizontalAdCard(listing: listings[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single promo banner definition for the home carousel.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Container(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 16, width: 90, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 6),
                Container(height: 10, width: 70, color: Colors.grey.shade200),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dubizzle-style 2-column feed card: image with heart + featured badge, then
/// bold price, title, and location/time. Fills its grid cell.
class FeedAdCard extends StatefulWidget {
  final Listing listing;

  const FeedAdCard({super.key, required this.listing});

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  bool get isFav =>
      favoriteListings.any((i) => i.id == widget.listing.id);

  void toggleFav() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final was = isFav;
    setState(() {
      if (was) {
        favoriteListings.removeWhere((i) => i.id == widget.listing.id);
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
    if (was) {
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
    final l = widget.listing;
    final img = l.galleryImages;
    final posted = timeAgo(l.createdAt);
    final isNew =
        l.createdAt != null &&
        DateTime.now().difference(l.createdAt!.toDate()).inHours < 24;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: l)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img.isNotEmpty
                      ? Image.network(
                          img.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, e, s) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 36),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.image, size: 36),
                          ),
                        ),
                  if (l.isCurrentlyFeatured)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kGold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'FEATURED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: toggleFav,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white70,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                  if (l.sellerVerified)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (!l.isCurrentlyFeatured && !l.isSold && isNew)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kPakGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (!l.isCurrentlyFeatured &&
                      !l.isSold &&
                      !isNew &&
                      l.hasRecentPriceDrop)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.south,
                              color: Colors.white,
                              size: 9,
                            ),
                            SizedBox(width: 1),
                            Text(
                              'PRICE DROP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (l.isSold) const SoldTag(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          priceLabel(l),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (l.hasRecentPriceDrop) ...[
                        const SizedBox(width: 5),
                        Text(
                          formatPrice(l.previousPrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.title.isEmpty ? 'Untitled ad' : l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                  ),
                  if (l.condition.isNotEmpty && l.condition != 'N/A') ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: l.condition == 'New'
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.condition,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: l.condition == 'New'
                              ? Colors.green.shade800
                              : Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                  if ((l.category == 'Motors' ||
                          l.category == 'Commute & Rides') &&
                      l.attributes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      l.attributes.values.take(2).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                  if (l.deliveryAvailable) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: const [
                        Icon(
                          Icons.delivery_dining,
                          size: 13,
                          color: kPakGreen,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Delivery',
                          style: TextStyle(
                            fontSize: 10,
                            color: kPakGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 1),
                      Expanded(
                        child: Text(
                          l.city.isEmpty ? l.location : l.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      if (posted.isNotEmpty)
                        Text(
                          posted,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
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
// Home
// ---------------------------------------------------------------------------

/// Compact gradient shortcut tile used in the home quick-access row.
