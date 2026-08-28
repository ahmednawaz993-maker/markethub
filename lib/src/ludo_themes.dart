part of '../main.dart';

// Board themes.
//
// Every big Ludo app ships a wardrobe of boards, and it is the cheapest
// freshness there is: the rules never change, so a player who has run out of
// new things to do still gets something new to look at.
//
// WHAT A THEME MAY AND MAY NOT CHANGE. It repaints the BOARD — the ground, the
// tiles, their edges, the centre. It never touches the four seat colours. Red,
// green, yellow and blue are how a player identifies their own tokens and reads
// whose turn it is; a theme that recoloured them would make the board prettier
// and the game unreadable. So the palette here is deliberately only the
// surfaces the tokens sit ON.

/// A board palette.
class LudoTheme {
  const LudoTheme({
    required this.id,
    required this.label,
    required this.surface,
    required this.line,
    required this.dark,
  });

  final String id;
  final String label;

  /// The colour of a track tile.
  final Color surface;

  /// Edges, stars and the centre marker are derived from this.
  final Color line;

  /// Whether [surface] is dark, so the painter tints the ground the correct
  /// way. Derived rather than guessed at paint time — a mid-tone surface is
  /// genuinely ambiguous and getting it wrong makes the track disappear, which
  /// has happened here once already.
  final bool dark;

  static const classic = LudoTheme(
    id: 'classic',
    label: 'Classic',
    surface: Color(0xFFFFFFFF),
    line: Color(0xFF7C8798),
    dark: false,
  );

  static const midnight = LudoTheme(
    id: 'midnight',
    label: 'Midnight',
    surface: Color(0xFF16213A),
    line: Color(0xFF7E93BC),
    dark: true,
  );

  static const sand = LudoTheme(
    id: 'sand',
    label: 'Sand',
    surface: Color(0xFFFBF3E4),
    line: Color(0xFFB79A6B),
    dark: false,
  );

  static const emerald = LudoTheme(
    id: 'emerald',
    label: 'Emerald',
    surface: Color(0xFF0E2A22),
    line: Color(0xFF6FB79A),
    dark: true,
  );

  static const List<LudoTheme> all = [classic, midnight, sand, emerald];

  static LudoTheme byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => classic);
}

const String _kLudoThemeKey = 'ludo_board_theme';

/// The chosen board. A [ValueNotifier] so switching repaints the board without
/// rebuilding the game around it.
final ValueNotifier<LudoTheme> ludoTheme = ValueNotifier<LudoTheme>(
  LudoTheme.classic,
);

Future<void> loadLudoTheme() async {
  try {
    final p = await SharedPreferences.getInstance();
    ludoTheme.value = LudoTheme.byId(p.getString(_kLudoThemeKey));
  } catch (_) {
    // Storage unavailable — Classic is a fine default.
  }
}

Future<void> setLudoTheme(LudoTheme theme) async {
  ludoTheme.value = theme;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLudoThemeKey, theme.id);
  } catch (_) {}
}

/// The board picker.
class LudoThemeSheet extends StatelessWidget {
  const LudoThemeSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ValueListenableBuilder<LudoTheme>(
      valueListenable: ludoTheme,
      builder: (context, current, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Board', style: AppType.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Changes the board only — your colour stays the same.',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          const LudoThemeStrip(),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    ),
  );
}

/// The row of board choices. Its own widget so the collection sheet and this
/// one cannot drift apart.
class LudoThemeStrip extends StatelessWidget {
  const LudoThemeStrip({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: ValueListenableBuilder<LudoTheme>(
      valueListenable: ludoTheme,
      builder: (context, current, _) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: LudoTheme.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final t = LudoTheme.all[i];
          return _ThemeSwatch(
            theme: t,
            selected: t.id == current.id,
            onTap: () => setLudoTheme(t),
          );
        },
      ),
    ),
  );
}

/// A miniature of the real board, so the choice is made by looking rather than
/// by reading a name.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final LudoTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? kPakGreen : AppColors.borderSoft,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.rMd,
            child: CustomPaint(
              painter: LudoBoardPainter(
                surface: theme.surface,
                line: theme.line,
                darkSurface: theme.dark,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          theme.label,
          style: AppType.caption.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? kPakGreen : AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
