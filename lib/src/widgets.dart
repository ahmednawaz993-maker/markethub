part of '../main.dart';

// Reusable UI widgets shared across screens.

/// Looks up a palette [Color] by its display name (case-insensitive). Returns
/// null for an unknown/legacy free-text colour.
Color? productColorByName(String name) {
  final n = name.trim().toLowerCase();
  for (final (pn, pc) in kProductColors) {
    if (pn.toLowerCase() == n) return pc;
  }
  return null;
}

/// Daraz-style colour picker: a wrap of round colour swatches from the fixed
/// [kProductColors] palette. Tap a swatch to select it (tap again to clear).
/// The selected colour NAME is reported via [onChanged]. Used by sellers when
/// posting and by buyers in the filter sheet.
class ColorSwatchSelector extends StatelessWidget {
  final String selected; // selected colour name, '' = none
  final ValueChanged<String> onChanged;
  final String label;
  const ColorSwatchSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.label = 'Colour',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Text(
            selected.isEmpty ? '$label (optional)' : '$label:  $selected',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (name, color) in kProductColors)
              _ColorSwatch(
                name: name,
                color: color,
                selected: selected == name,
                onTap: () => onChanged(selected == name ? '' : name),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = color.computeLuminance() > 0.7;
    final isMulti = name == 'Multicolour';
    return Tooltip(
      message: name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isMulti ? null : color,
            gradient: isMulti
                ? const SweepGradient(
                    colors: [
                      Color(0xFFD32F2F),
                      Color(0xFFFBC02D),
                      Color(0xFF2E7D32),
                      Color(0xFF1976D2),
                      Color(0xFF7B1FA2),
                      Color(0xFFD32F2F),
                    ],
                  )
                : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? kPakGreen
                  : (isLight ? Colors.grey.shade400 : Colors.transparent),
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kPakGreen.withValues(alpha: 0.45),
                      blurRadius: 5,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: (isLight || isMulti) ? Colors.black87 : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

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
            count == 0 ? 'No reviews' : '${rating.toStringAsFixed(1)} ($count)',
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

/// Title-cases a free-typed place name, e.g. "chak 51 gb" -> "Chak 51 Gb".
String titleCasePlace(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Opens a searchable, full-height place picker. Returns the chosen place, or
/// null if dismissed. Much friendlier on mobile than a 190-item dropdown.
///
/// When [allowCustom] is true, a `Use "…"` option (with whatever was typed)
/// appears at the top whenever the search text doesn't exactly match a listed
/// place — so a
/// resident of any small village or town not in the curated list can still add
/// and select their own location. (Kept off for filters, where selecting a city
/// nobody has posted from would just return nothing.)
Future<String?> showCityPicker(
  BuildContext context, {
  bool includeAll = false,
  bool allowCustom = false,
}) {
  final options = [if (includeAll) 'All', ...(pakistanCities.toList()..sort())];

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final q = query.trim();
          final filtered = options
              .where((c) => c.toLowerCase().contains(q.toLowerCase()))
              .toList();
          // Offer the typed text as a custom place when it isn't already an
          // exact (case-insensitive) match in the list.
          final hasExact = options.any(
            (c) => c.toLowerCase() == q.toLowerCase(),
          );
          final showCustom = allowCustom && q.isNotEmpty && !hasExact;
          final custom = titleCasePlace(q);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    allowCustom ? 'City / Town / Village' : 'Select City',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: allowCustom
                            ? 'Search or type your town / village...'
                            : 'Search city...',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: (filtered.isEmpty && !showCustom)
                        ? const Center(child: Text('No place found'))
                        : ListView.builder(
                            itemCount: filtered.length + (showCustom ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (showCustom && index == 0) {
                                return ListTile(
                                  leading: const Icon(
                                    Icons.add_location_alt,
                                    color: kPakGreen,
                                  ),
                                  title: Text('Use "$custom"'),
                                  subtitle: const Text('Add my town / village'),
                                  onTap: () => Navigator.pop(context, custom),
                                );
                              }
                              final city =
                                  filtered[index - (showCustom ? 1 : 0)];
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
  final bool allowCustom;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const CitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'City',
    this.includeAll = false,
    this.allowCustom = false,
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
                allowCustom: allowCustom,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.black54;
    final placeholderBg = isDark ? Colors.white10 : Colors.grey.shade200;

    return FocusableTap(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdDetailsScreen(listing: listing)),
      ),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (img.isNotEmpty)
                    Image.network(
                      img.first,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: placeholderBg,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stack) => Container(
                        color: placeholderBg,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 38,
                          color: muted,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: placeholderBg,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_outlined, size: 38, color: muted),
                    ),
                  // Top scrim keeps the FEATURED badge legible over any image.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (listing.isCurrentlyFeatured)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE0B33A), kGold],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: kGold.withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (img.length > 1)
                    Positioned(
                      bottom: 7,
                      left: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${img.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (listing.isSold) const SoldTag(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (productColorByName(
                            listing.attributes['Color'] ?? '',
                          ) !=
                          null) ...[
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: productColorByName(
                              listing.attributes['Color'] ?? '',
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.shade400,
                              width: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          listing.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    priceLabel(listing),
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF66BB6A)
                          : const Color(0xFF1B8E3C),
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: muted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          listing.city.isEmpty
                              ? listing.location
                              : listing.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
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
        final listings = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where((l) => l.isApproved)
            .toList();
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
  bool get isFav => favoriteListings.any((i) => i.id == widget.listing.id);

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
    final colorSwatch = productColorByName(l.attributes['Color'] ?? '');
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
                            Icon(Icons.south, color: Colors.white, size: 9),
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
                  Row(
                    children: [
                      if (colorSwatch != null) ...[
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: colorSwatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.shade400,
                              width: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          l.title.isEmpty ? 'Untitled ad' : l.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
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
                      style: TextStyle(fontSize: 10.5, color: Colors.grey[700]),
                    ),
                  ],
                  if (l.deliveryAvailable) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: const [
                        Icon(Icons.delivery_dining, size: 13, color: kPakGreen),
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
                      Icon(
                        Icons.location_on,
                        size: 11,
                        color: Colors.grey[500],
                      ),
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
