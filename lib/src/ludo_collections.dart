part of '../main.dart';

// Dice and token collections.
//
// The same idea as board themes and for the same reason: the rules never
// change, so a player who has run out of new things to do still gets something
// new to look at. Boards, dice and tokens are three independent choices, which
// is deliberate — three small sets that combine give far more variety than one
// long list of fixed presets, and a player gets to make it theirs rather than
// pick somebody else's.
//
// THE ONE RULE A TOKEN SKIN MAY NOT BREAK. Red, green, yellow, blue, purple and
// orange are how a player finds their own pieces and reads whose turn it is. A
// skin changes the SHAPE and the FINISH; the colour is never its to touch. That
// is why LudoTokenSkin carries a style and no palette at all — there is nothing
// in it that could recolour a seat even by mistake.

/// How a token is drawn. The seat colour is supplied separately.
enum LudoTokenStyle {
  /// A lit sphere. The original, and still the default.
  glossy,

  /// Flat colour with a white rim — clearest on a busy or dark board.
  flat,

  /// A thick ring. Reads well when several tokens share a square, because the
  /// board shows through the middle.
  ring,

  /// A faceted stone: a bright upper-left facet over a darker body.
  gem,
}

/// One token skin.
class LudoTokenSkin {
  const LudoTokenSkin({
    required this.id,
    required this.label,
    required this.style,
  });

  final String id;
  final String label;
  final LudoTokenStyle style;

  static const glossy = LudoTokenSkin(
    id: 'glossy',
    label: 'Classic',
    style: LudoTokenStyle.glossy,
  );
  static const flat = LudoTokenSkin(
    id: 'flat',
    label: 'Flat',
    style: LudoTokenStyle.flat,
  );
  static const ring = LudoTokenSkin(
    id: 'ring',
    label: 'Ring',
    style: LudoTokenStyle.ring,
  );
  static const gem = LudoTokenSkin(
    id: 'gem',
    label: 'Gem',
    style: LudoTokenStyle.gem,
  );

  static const List<LudoTokenSkin> all = [glossy, flat, ring, gem];

  static LudoTokenSkin byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => glossy);
}

/// One dice skin: the face, the pips, and the edge.
class LudoDiceSkin {
  const LudoDiceSkin({
    required this.id,
    required this.label,
    required this.face,
    required this.pip,
    required this.edge,
  });

  final String id;
  final String label;
  final Color face;
  final Color pip;
  final Color edge;

  static const ivory = LudoDiceSkin(
    id: 'ivory',
    label: 'Ivory',
    face: Color(0xFFFFFFFF),
    pip: Color(0xFF1B2430),
    edge: Color(0xFFD4DAE3),
  );
  static const gold = LudoDiceSkin(
    id: 'gold',
    label: 'Gold',
    face: Color(0xFFF5C452),
    pip: Color(0xFF5A3E06),
    edge: Color(0xFFC79A2E),
  );
  static const onyx = LudoDiceSkin(
    id: 'onyx',
    label: 'Onyx',
    face: Color(0xFF232A38),
    pip: Color(0xFFF2F5FA),
    edge: Color(0xFF3C4557),
  );
  static const jade = LudoDiceSkin(
    id: 'jade',
    label: 'Jade',
    face: Color(0xFF1F7A5A),
    pip: Color(0xFFEAFBF3),
    edge: Color(0xFF14543E),
  );

  static const List<LudoDiceSkin> all = [ivory, gold, onyx, jade];

  static LudoDiceSkin byId(String? id) =>
      all.firstWhere((d) => d.id == id, orElse: () => ivory);
}

const String _kLudoDiceKey = 'ludo_dice_skin';
const String _kLudoTokenKey = 'ludo_token_skin';

final ValueNotifier<LudoDiceSkin> ludoDiceSkin = ValueNotifier(
  LudoDiceSkin.ivory,
);
final ValueNotifier<LudoTokenSkin> ludoTokenSkin = ValueNotifier(
  LudoTokenSkin.glossy,
);

Future<void> loadLudoCollections() async {
  try {
    final p = await SharedPreferences.getInstance();
    ludoDiceSkin.value = LudoDiceSkin.byId(p.getString(_kLudoDiceKey));
    ludoTokenSkin.value = LudoTokenSkin.byId(p.getString(_kLudoTokenKey));
  } catch (_) {
    // Storage unavailable — the defaults are fine.
  }
}

Future<void> setLudoDiceSkin(LudoDiceSkin skin) async {
  ludoDiceSkin.value = skin;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLudoDiceKey, skin.id);
  } catch (_) {}
}

Future<void> setLudoTokenSkin(LudoTokenSkin skin) async {
  ludoTokenSkin.value = skin;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLudoTokenKey, skin.id);
  } catch (_) {}
}

/// Paints a token in the chosen style, in its own seat colour.
///
/// Shared by both boards so a skin cannot look one way on the cross and another
/// on the hexagon.
Decoration ludoTokenDecoration({
  required Color colour,
  required bool playable,
  required LudoTokenSkin skin,
}) {
  final border = Border.all(
    color: playable ? Colors.white : Colors.white.withValues(alpha: 0.75),
    width: playable ? 2.4 : 1.4,
  );
  final shadows = <BoxShadow>[
    // Every piece casts a small shadow, so it sits ON the board.
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 3,
      offset: const Offset(0, 1.5),
    ),
    if (playable)
      BoxShadow(
        color: colour.withValues(alpha: 0.65),
        blurRadius: 10,
        spreadRadius: 1.5,
      ),
  ];

  switch (skin.style) {
    case LudoTokenStyle.flat:
      return BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: border,
        boxShadow: shadows,
      );
    case LudoTokenStyle.ring:
      return BoxDecoration(
        shape: BoxShape.circle,
        // A thick coloured rim with the board showing through the middle.
        border: Border.all(color: colour, width: 5),
        color: Colors.white.withValues(alpha: 0.92),
        boxShadow: shadows,
      );
    case LudoTokenStyle.gem:
      return BoxDecoration(
        // A cut stone, not another sphere. At token size a diagonal gradient on
        // a circle is nearly indistinguishable from the glossy piece — the
        // SHAPE is what makes it a different collectable, and it is the only
        // thing a skin is allowed to change besides the finish.
        shape: BoxShape.rectangle,
        // AppRadius.xs, not a bare number: the design-token guard treats a raw
        // radius as drift, and it is right to — this is exactly how a scale
        // stops being a scale.
        borderRadius: AppRadius.rXs,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colour, Colors.white, 0.62)!,
            colour,
            Color.lerp(colour, Colors.black, 0.42)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        border: border,
        boxShadow: shadows,
      );
    case LudoTokenStyle.glossy:
      return BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.95,
          colors: [
            Color.lerp(colour, Colors.white, 0.5)!,
            colour,
            Color.lerp(colour, Colors.black, 0.3)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: border,
        boxShadow: shadows,
      );
  }
}

/// The specular dot, which only the glossy piece wears.
bool ludoTokenHasHighlight(LudoTokenSkin skin) =>
    skin.style == LudoTokenStyle.glossy;

/// The picker: board, dice and tokens, each previewed as itself.
class LudoCollectionSheet extends StatelessWidget {
  const LudoCollectionSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your collection', style: AppType.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Mix and match. Your seat colour never changes — only how the '
                  'board, the dice and your pieces look.',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          _Heading('Board'),
          const LudoThemeStrip(),
          _Heading('Dice'),
          SizedBox(
            height: 92,
            child: ValueListenableBuilder<LudoDiceSkin>(
              valueListenable: ludoDiceSkin,
              builder: (context, current, _) => ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: LudoDiceSkin.all.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) {
                  final d = LudoDiceSkin.all[i];
                  return _Swatch(
                    label: d.label,
                    selected: d.id == current.id,
                    onTap: () => setLudoDiceSkin(d),
                    // Shown as a real face, at a real value, so the choice is
                    // made by looking rather than by reading a name.
                    child: LudoDieFace(value: 5, size: 46, skin: d),
                  );
                },
              ),
            ),
          ),
          _Heading('Pieces'),
          SizedBox(
            height: 92,
            child: ValueListenableBuilder<LudoTokenSkin>(
              valueListenable: ludoTokenSkin,
              builder: (context, current, _) => ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: LudoTokenSkin.all.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) {
                  final t = LudoTokenSkin.all[i];
                  return _Swatch(
                    label: t.label,
                    selected: t.id == current.id,
                    onTap: () => setLudoTokenSkin(t),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Two colours, because the point of a piece is that you
                        // can tell yours from somebody else's.
                        for (final c in const [LudoColor.red, LudoColor.blue])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: DecoratedBox(
                                decoration: ludoTokenDecoration(
                                  colour: ludoColorOf(c),
                                  playable: false,
                                  skin: t,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Text(text, style: AppType.label),
  );
}

/// A framed preview with a caption, used for every row so the three sets read
/// as one collection rather than three unrelated pickers.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.child,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget child;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 66,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: selected ? kPakGreen : AppColors.borderSoft,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: child,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppType.caption.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? kPakGreen : AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
