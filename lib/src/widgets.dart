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

/// Legacy empty-state name kept for the ~40 call sites that use it. It now
/// renders the marketplace [EmptyStateWidget] (light surface, dark text).
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
  Widget build(BuildContext context) =>
      EmptyStateWidget(icon: icon, title: title, subtitle: subtitle);
}

/// The page canvas behind every route, rendered once via [MaterialApp.builder].
///
/// The app used to paint a full-screen navy gradient here, which forced every
/// screen to use white-on-navy text. It is now a flat marketplace background —
/// near-white in light mode, deep navy in dark mode — so screens use one
/// consistent on-surface text family and cards read as raised.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
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
            style: TextStyle(
              fontSize: size * 0.8,
              color: AppColors.textSecondary,
            ),
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
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
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
            Icon(Icons.location_city, size: 20, color: AppColors.textMuted),
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
                borderRadius: AppRadius.rSm,
              ),
              child: const Text(
                'SOLD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
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

/// A compact ad card for the home rails.
///
/// Kept as a name so existing call sites keep working; the implementation is
/// the shared [MarketplaceListingCard]. Sizes itself for a horizontal rail.
class HorizontalAdCard extends StatelessWidget {
  final Listing listing;

  const HorizontalAdCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cardWidth = w < 380 ? 152.0 : (w < 600 ? 168.0 : 190.0);
    return SizedBox(
      width: cardWidth,
      height: MarketplaceListingCard.heightFor(context, cardWidth),
      child: MarketplaceListingCard(listing: listing),
    );
  }
}

/// A titled horizontal rail of ads fed by a Firestore [stream]. Hides itself
/// entirely when the stream has no results (so empty sections never show).
class AdsRail extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Stream<QuerySnapshot> stream;
  final VoidCallback? onSeeAll;

  const AdsRail({
    super.key,
    required this.title,
    required this.stream,
    this.icon,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final listings = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where((l) => l.isApproved && !isHiddenSeller(l.userId))
            .toList();
        return HorizontalListingSection(
          title: title,
          icon: icon,
          listings: listings,
          onSeeAll: onSeeAll,
        );
      },
    );
  }
}

/// The 2-column feed card used by grids and rails.
///
/// Kept as a name so existing call sites keep working; the implementation is
/// the shared [MarketplaceListingCard]. It fills its parent, so place it in a
/// grid cell or a sized rail slot.
class FeedAdCard extends StatelessWidget {
  final Listing listing;

  const FeedAdCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) =>
      MarketplaceListingCard(listing: listing);
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

/// Compact gradient shortcut tile used in the home quick-access row.
