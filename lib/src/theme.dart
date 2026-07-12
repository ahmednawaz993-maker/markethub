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

/// Centralised semantic colours. Screens should reference these instead of
/// hardcoding raw values, so contrast stays consistent everywhere.
///
/// The app renders content over a dark navy gradient (see [AppBackground]).
/// Two text families exist:
///  • `on-surface`  → dark text used on a white Card/surface ([textPrimary] …)
///  • `on-navy`     → light text used directly on the navy gradient ([onNavy] …)
/// Using the wrong family is exactly the low-contrast bug this system prevents.
abstract final class AppColors {
  // Brand
  static const Color primary = kPakGreen;
  static const Color primaryDeep = kPakGreenDeep;
  static const Color secondary = kGold;

  // Light surfaces (Cards, sheets, dialogs)
  static const Color surface = Colors.white;
  static Color surfaceVariant = const Color(0xFFF3F5F9); // subtle grey panel
  static const Color card = Colors.white;

  // Text ON a light surface (WCAG AA on white)
  static const Color textPrimary = Color(0xFF17223B); // ~15:1 on white
  static Color textSecondary = const Color(0xFF4A5568); // ~7:1 on white
  static Color textMuted = const Color(0xFF6B7280); // ~5:1 on white
  static const Color textOnPrimary = Colors.white;
  static const Color link = kPakGreenLight;

  // Text ON the navy gradient (light family)
  static const Color onNavy = Colors.white;
  static const Color onNavyMuted = Colors.white70;
  static const Color onNavyFaint = Colors.white60;

  // Lines
  static Color border = const Color(0xFFD8DEE9);
  static Color divider = const Color(0xFFE2E8F0);
  static Color disabled = const Color(0xFF9AA5B1);

  // Status / feedback (readable on white, distinguishable for colour-blind
  // users when paired with the status icon + text label helpers below)
  static const Color success = Color(0xFF1E7E45);
  static const Color warning = Color(0xFFB26A00);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF1565C0);
  static Color overlay = Colors.black.withValues(alpha: 0.45);
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

ThemeData buildAppTheme() {
  final base = ThemeData(
    primaryColor: kPakGreen,
    useMaterial3: false,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPakGreen,
      primary: kPakGreen,
      secondary: kGold,
    ),
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
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
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
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
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // Readable label / placeholder / error text on the white field.
      labelStyle: TextStyle(color: AppColors.textSecondary),
      floatingLabelStyle: const TextStyle(
        color: kPakGreen,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: AppColors.textMuted),
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPakGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: kPakGreen,
      secondarySelectedColor: kPakGreen,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: kPakGreen,
      // Darker than the old Colors.grey so unselected tabs meet the 4.5:1 AA
      // target instead of washing out.
      unselectedItemColor: AppColors.textMuted,
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
      backgroundColor: AppColors.primaryDeep,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: kGold,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: AppColors.textSecondary, height: 1.35),
    ),
    dividerColor: AppColors.divider,
    disabledColor: AppColors.disabled,
  );
}

/// True on phone-width screens (used to tune density/spacing for mobile).
bool isPhone(BuildContext context) => MediaQuery.of(context).size.width < 600;

/// Friendly empty-state placeholder (icon + message) for screens shown over
/// the green background.
