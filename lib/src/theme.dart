part of '../main.dart';

// App colors and ThemeData.

// Brand palette — Midnight Navy + Gold (premium). The constant names are kept
// (kPakGreen*) to avoid a large rename across the app; they now hold navy.
const Color kPakGreenDeep = Color(0xFF0A1A33); // darkest navy (gradient ends)
const Color kPakGreen = Color(
  0xFF173A6B,
); // primary royal navy (buttons/accents)
const Color kPakGreenLight = Color(0xFF2E5AA0); // lighter navy accent
const Color kGold = Color(0xFFC9A227); // premium gold accent

// ── Theme mode (light / dark / system) ──────────────────────────────────────
//
// Light mode  = navy gradient chrome + WHITE cards + dark card text (the
//               original look).
// Dark mode   = a darker navy gradient + DARK-SLATE cards + light card text.
// The gradient stays navy in both, so on-navy white text/icons are correct in
// both modes and never change — only surfaces and their text flip.

/// Current theme mode; persisted and listened to by PakBazarApp. Defaults to
/// LIGHT (the established look) so no existing user's experience changes — dark
/// mode is strictly opt-in via the Appearance selector in settings.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);
const String _themeModePrefKey = 'app_theme_mode';

/// The brightness actually in effect this frame. MaterialApp's builder writes
/// it from the resolved Theme, so [AppColors] getters can return the right
/// family without every call site needing a BuildContext.
Brightness appBrightnessValue = Brightness.light;
bool get _dark => appBrightnessValue == Brightness.dark;

Future<void> loadSavedThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_themeModePrefKey)) {
      case 'light':
        appThemeMode.value = ThemeMode.light;
      case 'dark':
        appThemeMode.value = ThemeMode.dark;
      case 'system':
        appThemeMode.value = ThemeMode.system;
    }
  } catch (_) {}
}

Future<void> setThemeMode(ThemeMode mode) async {
  appThemeMode.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefKey, mode.name);
  } catch (_) {}
}

/// Centralised, theme-aware semantic colours. Screens reference these instead of
/// hardcoding raw values, so both light and dark modes stay readable.
///
/// Two text families exist:
///  • `on-surface`  → [textPrimary]… : dark in light mode, light in dark mode.
///  • `on-navy`     → [onNavy]…       : always light (the gradient is navy in
///    both modes). Using the wrong family is the low-contrast bug to avoid.
abstract final class AppColors {
  // Brand (constant)
  static const Color primary = kPakGreen;
  static const Color primaryDeep = kPakGreenDeep;
  static const Color secondary = kGold;

  // Surfaces — white in light, dark slate in dark (distinct from the gradient).
  static Color get surface => _dark ? const Color(0xFF17253F) : Colors.white;
  static Color get card => surface;
  static Color get surfaceVariant =>
      _dark ? const Color(0xFF0F1C33) : const Color(0xFFF3F5F9);

  // Text on a surface — flips with the surface.
  static Color get textPrimary =>
      _dark ? const Color(0xFFEAF0FA) : const Color(0xFF17223B);
  static Color get textSecondary =>
      _dark ? const Color(0xFFB4C1D8) : const Color(0xFF4A5568);
  static Color get textMuted =>
      _dark ? const Color(0xFF8B99B2) : const Color(0xFF6B7280);
  static const Color textOnPrimary = Colors.white;
  static Color get link => _dark ? const Color(0xFF83ABE8) : kPakGreenLight;

  // Text ON the navy gradient — always light (gradient is navy in both modes).
  static const Color onNavy = Colors.white;
  static const Color onNavyMuted = Colors.white70;
  static const Color onNavyFaint = Colors.white60;

  // Lines
  static Color get border =>
      _dark ? const Color(0xFF2D3F60) : const Color(0xFFD8DEE9);
  static Color get divider =>
      _dark ? const Color(0xFF25344F) : const Color(0xFFE2E8F0);
  static Color get disabled =>
      _dark ? const Color(0xFF5E6C88) : const Color(0xFF9AA5B1);

  // Status — lighter in dark mode so it stays legible on dark surfaces. Always
  // paired with statusIcon + a text label (never colour alone).
  static Color get success =>
      _dark ? const Color(0xFF55C98A) : const Color(0xFF1E7E45);
  static Color get warning =>
      _dark ? const Color(0xFFE7A23C) : const Color(0xFFB26A00);
  static Color get error =>
      _dark ? const Color(0xFFF08C8C) : const Color(0xFFC62828);
  static Color get info =>
      _dark ? const Color(0xFF6FA8E8) : const Color(0xFF1565C0);
  static Color get overlay =>
      Colors.black.withValues(alpha: _dark ? 0.6 : 0.45);
}

/// Brand colour for an order/payment status. Never the ONLY signal — always
/// paired with [statusIcon] + a text label (orderStatusLabel/paymentStatusLabel)
/// so status is legible without relying on colour alone (accessibility).
Color statusColor(String status) {
  switch (status) {
    case 'completed':
    case 'delivered':
    case 'buyer_confirmed':
    case 'released':
    case 'released_to_seller':
    case 'accepted':
    case 'paid':
    case 'held_by_platform':
      return AppColors.success;
    case 'pending':
    case 'pending_payment':
    case 'payment_pending':
    case 'processing':
    case 'cod_pending':
    case 'unpaid':
    case 'payment_review':
    case 'release_pending':
      return AppColors.warning;
    case 'shipped':
      return AppColors.info;
    case 'cancelled':
    case 'rejected':
    case 'failed':
      return AppColors.error;
    case 'refunded':
    case 'partially_refunded':
    case 'returned':
      return AppColors.textMuted;
    case 'disputed':
      return const Color(0xFF8E24AA); // purple — distinct from the others
    default:
      return AppColors.textMuted;
  }
}

/// A glyph for a status, so it reads at a glance without relying on colour.
IconData statusIcon(String status) {
  switch (status) {
    case 'completed':
    case 'released':
    case 'released_to_seller':
      return Icons.verified;
    case 'delivered':
    case 'buyer_confirmed':
      return Icons.check_circle;
    case 'accepted':
      return Icons.thumb_up_alt_outlined;
    case 'processing':
      return Icons.inventory_2_outlined;
    case 'shipped':
      return Icons.local_shipping_outlined;
    case 'pending':
    case 'pending_payment':
    case 'payment_pending':
    case 'payment_review':
    case 'release_pending':
      return Icons.schedule;
    case 'cod_pending':
    case 'unpaid':
      return Icons.payments_outlined;
    case 'held_by_platform':
    case 'paid':
      return Icons.lock_outline;
    case 'cancelled':
    case 'rejected':
    case 'failed':
      return Icons.cancel_outlined;
    case 'refunded':
    case 'partially_refunded':
      return Icons.currency_exchange;
    case 'returned':
      return Icons.assignment_return_outlined;
    case 'disputed':
      return Icons.gavel_outlined;
    default:
      return Icons.info_outline;
  }
}

/// A status pill that communicates state THREE ways — colour, icon and text
/// label — so it stays legible for colour-blind users and screen readers.
class StatusBadge extends StatelessWidget {
  final String status;
  final String label;
  final bool dense;
  const StatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Semantics(
      label: 'Status: $label',
      container: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 9,
          vertical: dense ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon(status), size: dense ? 12 : 14, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: dense ? 10.5 : 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white, rounded, elevated panel for placing dark-text content over the
/// navy gradient (prevents the dark-text-on-navy low-contrast bug). Use this
/// for list/detail bodies that aren't already inside a Card.
class SurfacePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  const SurfacePanel({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(12),
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A Light / Dark / System appearance selector for the settings screen.
class ThemeTile extends StatelessWidget {
  const ThemeTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        Widget chip(String label, ThemeMode m, IconData icon) => ChoiceChip(
          avatar: Icon(
            icon,
            size: 16,
            color: mode == m ? Colors.white : AppColors.textMuted,
          ),
          label: Text(
            label,
            style: TextStyle(
              color: mode == m ? Colors.white : AppColors.textSecondary,
            ),
          ),
          selected: mode == m,
          onSelected: (_) => setThemeMode(m),
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.brightness_6, color: kPakGreen),
                    const SizedBox(width: 8),
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    chip('System', ThemeMode.system, Icons.brightness_auto),
                    chip('Light', ThemeMode.light, Icons.light_mode),
                    chip('Dark', ThemeMode.dark, Icons.dark_mode),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Builds the light or dark theme. Because it is constructed once per mode
/// (not per frame), it uses explicit [brightness]-derived colours rather than
/// the live [AppColors] getters.
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF17253F) : Colors.white;
  final onSurface = dark ? const Color(0xFFEAF0FA) : const Color(0xFF17223B);
  final onSurfaceMuted = dark
      ? const Color(0xFFB4C1D8)
      : const Color(0xFF4A5568);
  final onSurfaceFaint = dark
      ? const Color(0xFF8B99B2)
      : const Color(0xFF6B7280);
  final borderCol = dark ? const Color(0xFF2D3F60) : const Color(0xFFD8DEE9);
  final dividerCol = dark ? const Color(0xFF25344F) : const Color(0xFFE2E8F0);
  final errorCol = dark ? const Color(0xFFF08C8C) : const Color(0xFFC62828);

  final base = ThemeData(
    brightness: brightness,
    primaryColor: kPakGreen,
    useMaterial3: false,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPakGreen,
      brightness: brightness,
      primary: kPakGreen,
      secondary: kGold,
      surface: surface,
      onSurface: onSurface,
      error: errorCol,
    ),
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    // Card text should be readable on the (mode-dependent) surface.
    textTheme: base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ),
    appBarTheme: const AppBarTheme(
      // The app bar sits on the navy gradient in both modes → white text.
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPakGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPakGreen,
        side: const BorderSide(color: kPakGreen, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPakGreen),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPakGreen,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // Readable label / placeholder / error text on the field, both modes.
      labelStyle: TextStyle(color: onSurfaceMuted),
      floatingLabelStyle: TextStyle(
        color: dark ? const Color(0xFF83ABE8) : kPakGreen,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: onSurfaceFaint),
      errorStyle: TextStyle(color: errorCol, fontWeight: FontWeight.w600),
      prefixIconColor: onSurfaceMuted,
      suffixIconColor: onSurfaceMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderCol),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderCol),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xFF83ABE8) : kPakGreen,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorCol, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorCol, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: kPakGreen,
      secondarySelectedColor: kPakGreen,
      labelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: dark ? const Color(0xFF83ABE8) : kPakGreen,
      // Meets the 4.5:1 AA target for unselected tabs in both modes.
      unselectedItemColor: onSurfaceFaint,
      type: BottomNavigationBarType.fixed,
      elevation: 16,
      // Smaller labels so all 5 items fit comfortably on narrow phones.
      selectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kPakGreenDeep,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: kGold,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: onSurfaceMuted, height: 1.35),
    ),
    dividerColor: dividerCol,
    disabledColor: dark ? const Color(0xFF5E6C88) : const Color(0xFF9AA5B1),
  );
}

/// True on phone-width screens (used to tune density/spacing for mobile).
bool isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

/// Friendly empty-state placeholder (icon + message) for screens shown over
/// the green background.
