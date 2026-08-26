part of '../main.dart';

// ---------------------------------------------------------------------------
// PakBazar marketplace design system.
//
// One place that owns spacing, radii, typography and the reusable marketplace
// components (search bar, section headers, listing cards, rails, banners,
// bottom navigation, empty/loading states). Screens compose these instead of
// hand-rolling padding and text styles, so the whole app stays consistent.
//
// Colours live in theme.dart (AppColors) — this file never hardcodes a brand
// colour, so re-skinning PakBazar means editing one palette.
// ---------------------------------------------------------------------------

/// Spacing scale. Everything in the app is a multiple of 4.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Horizontal padding used by every page body and section header.
  static const double page = 16;

  /// Vertical gap between two top-level sections on a page.
  static const double section = 24;

  /// Bottom padding that keeps scrollable content clear of the fixed bottom
  /// navigation (bar height + centre button overhang + breathing room).
  static const double navClearance = 96;

  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: page);
  static const EdgeInsets pageAll = EdgeInsets.all(page);
}

/// Corner radii. Cards are 14, controls 12, pills fully rounded.
abstract final class AppRadius {
  /// Tightest radius in the app — colour swatches and small thumbnails, where
  /// 8 already reads as noticeably soft. Added because three call sites were
  /// using a bare 4: the gap was in the scale, not in them.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double card = 14;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static final BorderRadius rXs = BorderRadius.circular(xs);
  static final BorderRadius rSm = BorderRadius.circular(sm);
  static final BorderRadius rMd = BorderRadius.circular(md);
  static final BorderRadius rCard = BorderRadius.circular(card);
  static final BorderRadius rLg = BorderRadius.circular(lg);
  static final BorderRadius rXl = BorderRadius.circular(xl);
  static final BorderRadius rPill = BorderRadius.circular(pill);
}

/// Elevation for surfaces that should read as objects rather than as regions of
/// the page — principally the listing card, which is the most-repeated surface
/// in the app.
///
/// The two themes get depth from opposite mechanisms, which is why this is a
/// token and not a constant:
///
///  * **Light** — a soft two-layer shadow and NO border. The page sits on
///    #F7F8FA precisely so a white card reads as raised; a hairline on top of
///    that made a grid of cards read as one mesh of boxes instead of separate
///    objects.
///  * **Dark** — no shadow, keep the hairline. A shadow cast on a near-black
///    ground is invisible, so spending paint on it buys nothing; there, depth
///    comes from the surface being lighter than the page plus the border.
///
/// Tinted toward the app's ink navy rather than pure black, so the shade sits
/// in the same colour world as everything around it.
abstract final class AppShadow {
  /// Resting elevation for a card. Empty in dark mode by design — pair it with
  /// [cardBorder] so exactly one of the two is doing the work.
  static List<BoxShadow> get card => _dark
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0A1526),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x140A1526),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ];

  /// The hairline that replaces [card] in dark mode, and null in light where
  /// the shadow already separates the surface from the ground.
  static BoxBorder? get cardBorder =>
      _dark ? Border.all(color: AppColors.borderSoft) : null;
}

/// Shared text styles. Resolved against the live [AppColors] so they follow
/// light/dark mode without a BuildContext.
abstract final class AppType {
  static TextStyle get pageTitle => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static TextStyle get sectionTitle => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static TextStyle get cardTitle => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static TextStyle get price => TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static TextStyle get body =>
      TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4);

  static TextStyle get secondary =>
      TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35);

  static TextStyle get caption =>
      TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.3);

  static TextStyle get label => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.2,
  );
}

/// A soft card container: flat surface, hairline border, no heavy shadow.
/// The default wrapper for grouped content across the app.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.radius = AppRadius.card,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
    if (onTap != null) {
      content = InkWell(borderRadius: r, onTap: onTap, child: content);
    }
    // The surface is painted by a Material, not a DecoratedBox. Anything that
    // draws ink — an InkWell here, or a ListTile/InkWell nested in [child] —
    // paints onto the nearest Material ancestor, so a plain coloured box would
    // hide every tap ripple inside the card.
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: AppColors.borderSoft),
        ),
        child: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/// Every remote image in the app goes through here so placeholders, error
/// fallbacks and fit are identical everywhere. Uses the Flutter image cache
/// (`Image.network` is backed by it) and decodes at the displayed size when a
/// width is known, which keeps long rails cheap to scroll.
class AppNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final IconData placeholderIcon;
  final double? iconSize;

  /// Overrides the decode width in logical pixels. Normally unnecessary — the
  /// widget measures itself and decodes to fit. Set it only where the layout
  /// width is much larger than the image is ever shown at.
  final double? decodeWidth;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image_outlined,
    this.iconSize,
    this.decodeWidth,
  });

  Widget _fallback(BuildContext context, IconData icon) {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(icon, size: iconSize ?? 32, color: AppColors.disabled),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) return _fallback(context, placeholderIcon);

    // Decode at the size we actually paint. Without this a 12 MP listing photo
    // decodes to roughly 48 MB of RGBA per card no matter how small the card
    // is, which is the single largest source of scroll jank and memory
    // pressure in long rails. Measuring here means every existing call site
    // gets the benefit without passing anything.
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
        final logicalWidth = decodeWidth ??
            (constraints.hasBoundedWidth && constraints.maxWidth > 0
                ? constraints.maxWidth
                : null);
        final cacheWidth = logicalWidth == null
            ? null
            : (logicalWidth * dpr).round().clamp(1, 4096);

        return Image.network(
          url,
          fit: fit,
          cacheWidth: cacheWidth,
          // Fade in rather than pop, and never show a raw grey flash.
          frameBuilder: (context, child, frame, wasSync) {
            if (wasSync || frame != null) return child;
            return _fallback(context, placeholderIcon);
          },
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const LoadingShimmer(),
          errorBuilder: (context, error, stack) =>
              _fallback(context, Icons.broken_image_outlined),
        );
      },
    );
  }
}

/// A gently animated placeholder used while content loads. Fills its parent,
/// so wrap it in a SizedBox/AspectRatio when a specific size is needed.
class LoadingShimmer extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;

  const LoadingShimmer({super.key, this.width, this.height, this.radius = 0});

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceVariant;
    final highlight = AppColors.shimmerHighlight;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 2 - 1; // -1 .. 1
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.radius > 0
                  ? BorderRadius.circular(widget.radius)
                  : null,
              gradient: LinearGradient(
                begin: Alignment(-1 + t, -0.3),
                end: Alignment(1 + t, 0.3),
                colors: [base, highlight, base],
                stops: const [0.1, 0.5, 0.9],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A listing-card-shaped skeleton for grids and rails while data loads.
class ListingCardSkeleton extends StatelessWidget {
  const ListingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Matches the real card's elevation so the skeleton does not visibly
    // change shape when the data arrives.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.rCard,
        border: AppShadow.cardBorder,
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: LoadingShimmer()),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingShimmer(height: 14, width: 84, radius: AppRadius.sm),
                const SizedBox(height: AppSpacing.sm),
                LoadingShimmer(
                  height: 11,
                  width: double.infinity,
                  radius: AppRadius.sm,
                ),
                const SizedBox(height: 6),
                LoadingShimmer(height: 10, width: 70, radius: AppRadius.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons, empty and error states
// ---------------------------------------------------------------------------

/// The app's standard full-width call to action (Post ad, Checkout, Save…).
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;
  final bool outlined;
  final Color? color;

  const PrimaryActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.expand = true,
    this.outlined = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = busy
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );

    final button = outlined
        ? OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: color ?? AppColors.accent,
              side: BorderSide(color: color ?? AppColors.accent, width: 1.4),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            ),
            child: child,
          )
        : ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: color ?? AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
            ),
            child: child,
          );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Friendly empty state: icon, headline, optional supporting line and action.
/// Replaces the old on-gradient [EmptyState] (which is now a thin alias).
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppType.secondary,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryActionButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Something went wrong, with a retry affordance.
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorStateWidget({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      subtitle: message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

/// The marketplace search field used on Home and above result lists.
///
/// Height is 54 (within the 52–58 target), fully rounded, hairline border, no
/// drop shadow. It can render either as a live text field ([onSubmitted]) or as
/// a tappable button that pushes the search screen ([onTap]).
class AppSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  /// Optional leading location button (label + tap target) rendered inside the
  /// pill, before the query text.
  final String? locationLabel;
  final VoidCallback? onLocationTap;

  /// Optional trailing action, e.g. a filter button.
  final Widget? trailing;

  const AppSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Search in PakBazar',
    this.onSubmitted,
    this.onChanged,
    this.onTap,
    this.locationLabel,
    this.onLocationTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final readOnly = onTap != null;

    final field = TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 14, color: AppColors.textMuted),
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 22, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: field),
          if (locationLabel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _SearchBarDivider(),
            Flexible(
              child: InkWell(
                borderRadius: AppRadius.rPill,
                onTap: onLocationTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          locationLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 2), trailing!],
        ],
      ),
    );
  }
}

class _SearchBarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsetsDirectional.only(end: 2),
    color: AppColors.divider,
  );
}

/// A circular icon button with an optional unread-count badge, sized to sit
/// comfortably beside the search bar (notifications, cart, …).
class AppIconBadgeButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  const AppIconBadgeButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.count = 0,
    this.tooltip = '',
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 24, color: iconColor ?? AppColors.textPrimary),
              if (count > 0)
                PositionedDirectional(
                  end: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: AppRadius.rPill,
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

/// "Popular in Cars                        See all ›" — the standard heading
/// above every section and rail.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.actionLabel = 'See all',
    this.onAction,
    this.padding = const EdgeInsetsDirectional.fromSTEB(AppSpacing.page, 0, AppSpacing.sm, AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: iconColor ?? AppColors.accent),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sectionTitle,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
              ],
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Listing cards
// ---------------------------------------------------------------------------

/// Adds/removes a listing from the signed-in user's favourites, keeping the
/// in-memory [favoriteListings] list and the Firestore subcollection in sync.
/// Extracted so every card shares exactly one implementation.
Future<void> toggleFavoriteListing(
  Listing listing, {
  required bool wasFav,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('favorites')
      .doc(listing.id);
  if (wasFav) {
    await ref.delete();
  } else {
    await ref.set({
      ...listing.toMap(),
      'savedListingId': listing.id,
      'savedAt': Timestamp.now(),
    });
  }
}

/// The single marketplace listing card used by every grid and rail in the app.
///
/// Layout is deliberately deterministic: the image takes all remaining height
/// (so image widths and shapes match across a row) and the info block sits at
/// its natural height with hard `maxLines` caps. That combination means it can
/// never produce a RenderFlex overflow — but it does require a **bounded
/// height** parent. Use [heightFor] for rails and [gridDelegate] for grids so
/// the image lands on the intended aspect ratio at any text scale.
class MarketplaceListingCard extends StatefulWidget {
  final Listing listing;

  /// Show the favourite heart. Off for the seller's own ads.
  final bool showFavorite;

  /// Called instead of the default push to the details screen.
  final VoidCallback? onTap;

  const MarketplaceListingCard({
    super.key,
    required this.listing,
    this.showFavorite = true,
    this.onTap,
  });

  /// Image aspect ratio (width / height) every card targets.
  static const double imageAspect = 1.18;

  /// Height of the text block below the image at the current text scale.
  static double infoHeightFor(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);
    // Read straight off the styles the card actually renders. These used to be
    // copied numbers, and they had already drifted: the caption step moved and
    // this still budgeted for the old size. Deriving it means the guarantee
    // cannot rot the next time the type scale moves.
    // Ceil PER LINE, because that is what the painter does: each line is laid
    // out to whole pixels independently, so summing ideal heights always lands
    // a hair short of what actually paints.
    double line(TextStyle t, {int lines = 1}) =>
        (ts.scale(t.fontSize!) * (t.height ?? 1.2)).ceilToDouble() * lines;
    return 18 // vertical padding
        +
        line(AppType.price) +
        3 +
        line(AppType.cardTitle, lines: 2) +
        5 +
        line(AppType.caption);
  }

  /// Total card height for a given card width — used by rails.
  static double heightFor(BuildContext context, double width) =>
      width / imageAspect + infoHeightFor(context);

  /// A grid delegate whose cells are exactly tall enough for this card, so the
  /// image keeps [imageAspect] and nothing overflows at large text scales.
  static SliverGridDelegate gridDelegate(
    BuildContext context, {
    required double availableWidth,
    required int columns,
    double spacing = AppSpacing.md,
  }) {
    final cellWidth = (availableWidth - spacing * (columns - 1)) / columns;
    final cellHeight = heightFor(context, cellWidth);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: cellWidth / cellHeight,
    );
  }

  /// Sensible column count for the available width.
  static int columnsFor(double width) {
    if (width >= 1100) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  @override
  State<MarketplaceListingCard> createState() => _MarketplaceListingCardState();
}

class _MarketplaceListingCardState extends State<MarketplaceListingCard> {
  bool get _isFav => favoriteListings.any((i) => i.id == widget.listing.id);

  Future<void> _toggleFav() async {
    final was = _isFav;
    setState(() {
      if (was) {
        favoriteListings.removeWhere((i) => i.id == widget.listing.id);
      } else {
        favoriteListings.add(widget.listing);
      }
    });
    await toggleFavoriteListing(widget.listing, wasFav: was);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final images = l.galleryImages;
    final posted = timeAgo(l.createdAt);
    final swatch = productColorByName(l.attributes['Color'] ?? '');
    final isNew =
        l.createdAt != null &&
        DateTime.now().difference(l.createdAt!.toDate()).inHours < 24;

    // Geometry is untouched — same radius, same bounded height, so the
    // overflow-proof layout documented above still holds. Only the way the
    // card separates from the page changes: shadow in light, hairline in
    // dark. See [AppShadow].
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.rCard,
        border: AppShadow.cardBorder,
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              widget.onTap ??
              () => Navigator.push(
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
                    AppNetworkImage(
                      url: images.isEmpty ? '' : images.first,
                      iconSize: 34,
                    ),
                    // One badge only, by priority, so the corner never stacks.
                    if (l.isCurrentlyFeatured)
                      const _CardBadge(
                        label: 'FEATURED',
                        icon: Icons.star,
                        color: kGold,
                      )
                    else if (!l.isSold && isNew)
                      _CardBadge(label: 'NEW', color: AppColors.primary)
                    else if (!l.isSold && l.hasRecentPriceDrop)
                      _CardBadge(
                        label: 'PRICE DROP',
                        icon: Icons.south,
                        color: AppColors.error,
                      ),
                    if (images.length > 1)
                      PositionedDirectional(
                        start: 8,
                        bottom: 8,
                        child: _ImageCountPill(count: images.length),
                      ),
                    if (l.sellerVerified)
                      PositionedDirectional(
                        end: 8,
                        bottom: 8,
                        child: Tooltip(
                          message: 'Verified seller',
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.info,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_user,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (widget.showFavorite)
                      PositionedDirectional(
                        end: 6,
                        top: 6,
                        child: _HeartButton(active: _isFav, onTap: _toggleFav),
                      ),
                    if (l.isSold) const SoldTag(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
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
                            style: AppType.price,
                          ),
                        ),
                        if (l.hasRecentPriceDrop) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              formatPrice(l.previousPrice),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (swatch != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 3),
                            decoration: BoxDecoration(
                              color: swatch,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            l.title.isEmpty ? 'Untitled ad' : l.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.cardTitle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Both texts are flexible: on a narrow card at a large
                    // text scale the location shrinks first, then the relative
                    // time — neither can push the row past its width.
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            l.city.isEmpty ? l.location : l.city,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption,
                          ),
                        ),
                        if (posted.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              posted,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption,
                            ),
                          ),
                        ],
                      ],
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

class _CardBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _CardBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 7,
      start: 7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.rSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCountPill extends StatelessWidget {
  final int count;
  const _ImageCountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: AppRadius.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            color: Colors.white,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _HeartButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: active ? 'Remove from favourites' : 'Add to favourites',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
          ),
          child: Icon(
            active ? Icons.favorite : Icons.favorite_border,
            size: 17,
            color: active ? AppColors.error : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal listing row: fixed-size image on the left, an [Expanded]
/// information column in the middle, and a single trailing action slot. Used by
/// My Ads, Favourites, saved lists and search's list view — anywhere a full
/// card would waste vertical space.
class MarketplaceListingTile extends StatelessWidget {
  final Listing listing;
  final VoidCallback? onTap;

  /// Extra rows (status pills, stats) rendered under the location line.
  final List<Widget> details;

  /// Single trailing widget — normally a PopupMenuButton, never a row of
  /// icon buttons (which would squeeze the title).
  final Widget? trailing;

  /// Optional full-width action row placed under the tile body.
  final Widget? actions;

  const MarketplaceListingTile({
    super.key,
    required this.listing,
    this.onTap,
    this.details = const [],
    this.trailing,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final images = l.galleryImages;

    return AppCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: AppRadius.rMd,
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AppNetworkImage(
                          url: images.isEmpty ? '' : images.first,
                          iconSize: 28,
                        ),
                        if (l.isSold) const SoldTag(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.title.isEmpty ? 'Untitled ad' : l.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceLabel(l),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.price,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              l.city.isEmpty ? l.location : l.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption,
                            ),
                          ),
                        ],
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: details,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// A small labelled statistic ("128 views") for use in [MarketplaceListingTile]
/// details, seller headers and stat rows.
class MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const MetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: c,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rails
// ---------------------------------------------------------------------------

/// A titled, horizontally scrolling rail of [MarketplaceListingCard]s.
/// Renders nothing when [listings] is empty, so sections never leave a gap.
class HorizontalListingSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final List<Listing> listings;
  final VoidCallback? onSeeAll;

  /// Minimum number of listings required before the rail shows at all.
  final int minItems;

  const HorizontalListingSection({
    super.key,
    required this.title,
    required this.listings,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.onSeeAll,
    this.minItems = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (listings.length < minItems) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 380
        ? 152.0
        : (screenWidth < 600 ? 168.0 : 190.0);
    final railHeight = MarketplaceListingCard.heightFor(context, cardWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: iconColor,
          onAction: onSeeAll,
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: listings.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: MarketplaceListingCard(listing: listings[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Featured / promotional cards
// ---------------------------------------------------------------------------

/// A wide promotional card for the "What's New on PakBazar" rail: image on top
/// with a category badge, then a bold title and a supporting line. Fixed width
/// and hard `maxLines` caps keep every card in the rail identical.
class FeaturedBannerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? badge;
  final IconData fallbackIcon;
  final VoidCallback? onTap;
  final double width;

  const FeaturedBannerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.badge,
    this.fallbackIcon = Icons.local_offer_outlined,
    this.onTap,
    this.width = 268,
  });

  /// Total height of a card of [width] at the current text scale — used by the
  /// rail that hosts it so nothing is ever clipped.
  /// Text sizes used by BOTH the layout below and [heightFor]. Shared
  /// constants rather than repeated literals: the two had already drifted
  /// apart, leaving the title budgeted 0.5px short of what it renders.
  static const double _titleSize = 15.5;
  static const double _subtitleSize = 12;

  static double heightFor(BuildContext context, double width) {
    final ts = MediaQuery.textScalerOf(context);
    return width /
            1.75 // image
            +
        AppSpacing
            .md // gap
            +
        // Ceil per line, as in MarketplaceListingCard.infoHeightFor.
        (ts.scale(_titleSize) * 1.25).ceilToDouble() // title
        +
        3 +
        (ts.scale(_subtitleSize) * 1.3).ceilToDouble() * 2; // subtitle, 2 lines
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: AppRadius.rLg,
              child: AspectRatio(
                aspectRatio: 1.75,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(
                      url: imageUrl,
                      placeholderIcon: fallbackIcon,
                      iconSize: 40,
                    ),
                    if (badge != null && badge!.isNotEmpty)
                      PositionedDirectional(
                        top: AppSpacing.sm,
                        start: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.rSm,
                          ),
                          child: Text(
                            badge!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _titleSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _subtitleSize,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved/recent search rendered as a compact card: thumbnail, the query,
/// its category and location, and an optional remove button.
class RecentSearchCard extends StatelessWidget {
  final String query;
  final String category;
  final String location;
  final String imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  /// Fixed width when laid out horizontally; null makes the card fill its
  /// parent (the vertical layout used on narrow screens).
  final double? width;

  const RecentSearchCard({
    super.key,
    required this.query,
    this.category = '',
    this.location = '',
    this.imageUrl = '',
    this.onTap,
    this.onRemove,
    this.width,
  });

  static const double height = 74;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (category.isNotEmpty) category,
      if (location.isNotEmpty) location,
    ].join(' · ');

    return SizedBox(
      width: width,
      height: height,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        onTap: onTap,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.rSm,
              child: SizedBox(
                width: 54,
                height: 54,
                child: AppNetworkImage(
                  url: imageUrl,
                  placeholderIcon: Icons.search,
                  iconSize: 22,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppType.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// A round-icon category shortcut used in the home category strip and the
/// all-categories grid.
class CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double width;

  const CategoryCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.width = 76,
  });

  static double heightFor(BuildContext context) =>
      58 + AppSpacing.sm + MediaQuery.textScalerOf(context).scale(11) * 1.2 * 2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.accent, size: 26),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seller/store summary card: avatar, name, verification and a supporting line.
class SellerCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String avatarUrl;
  final bool verified;
  final double? rating;
  final int? reviewCount;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SellerCard({
    super.key,
    required this.name,
    this.subtitle,
    this.avatarUrl = '',
    this.verified = false,
    this.rating,
    this.reviewCount,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft,
            backgroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Icon(Icons.storefront, color: AppColors.accent, size: 24)
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 15, color: AppColors.info),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
                ],
                if (rating != null) ...[
                  const SizedBox(height: 4),
                  StarRating(rating: rating!, size: 13, count: reviewCount),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

/// A destination in [AppBottomNavigation].
class AppNavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const AppNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// The fixed marketplace bottom bar: two tabs, a raised centre Sell action,
/// then two more tabs. Selected tabs use the brand colour, unselected grey.
///
/// Content above it must reserve [AppSpacing.navClearance] at the bottom so
/// nothing ends up hidden behind the bar or the centre button.
class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onSell;
  final String sellLabel;

  /// Exactly four destinations; the Sell action sits between #1 and #2.
  final List<AppNavDestination> destinations;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onSell,
    required this.destinations,
    this.sellLabel = 'SELL',
  });

  static const double barHeight = 62;

  @override
  Widget build(BuildContext context) {
    assert(destinations.length == 4, 'AppBottomNavigation takes 4 tabs');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              _tab(0),
              _tab(1),
              SizedBox(width: 72, child: _sellButton(context)),
              _tab(2),
              _tab(3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int index) {
    final d = destinations[index];
    final selected = currentIndex == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => onTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? d.activeIcon : d.icon,
                size: 23,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  d.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.accent : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sellButton(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: sellLabel,
        child: GestureDetector(
          onTap: onSell,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 21, color: Colors.white),
                Text(
                  sellLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

/// A titled group of form fields, used by Add/Edit Listing, Checkout and the
/// address forms so every long form reads the same way.
class FormSection extends StatelessWidget {
  final String title;
  final String? description;
  final IconData? icon;
  final List<Widget> children;

  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.accent),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text(title, style: AppType.sectionTitle)),
              ],
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(description!, style: AppType.caption),
            ],
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A sticky bottom action bar for forms and detail screens. Sits above the
/// keyboard and the system inset, so its buttons are never covered.
class StickyActionBar extends StatelessWidget {
  final List<Widget> children;

  const StickyActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}
