part of '../main.dart';

// The six-player board.
//
// A hexagon, not a bigger cross. Six arms will not fit a four-armed shape, so
// this is genuinely different geometry rather than a setting on the classic
// board — which is why it lives in its own file with its own painter.
//
// POLAR, NOT A GRID. The classic board is a 15x15 grid of squares and its
// geometry is a lookup table. Here every cell is placed from an angle and a
// radius, which is the natural way to describe a hexagon and avoids inventing
// a coordinate system that only one board uses. Cells are drawn as CIRCLES for
// the same reason: a square tile has to be rotated to sit correctly on a
// hexagonal path, and six different rotations of a rounded rectangle look worse
// than six circles do.
//
// The rules are untouched. LudoBoardSpec.six supplies the ring length, the
// starts, the safe squares and the arrows; the engine is the same engine. Only
// the drawing is new.

/// Where each seat's yard sits, as an angle in radians measured from straight
/// up, going clockwise. One per arm.
double ludoHexArmAngle(int seatIndex) =>
    -math.pi / 2 + seatIndex * (2 * math.pi / 6);

/// The centre of a ring cell, as a fraction of the board's half-size.
///
/// The ring is a hexagon walked corner to corner. Each of the six sides carries
/// [LudoBoardSpec.six.spacing] cells, and a cell's position is a straight
/// interpolation along its side — so the path is visibly a hexagon rather than
/// a circle, which is what makes the six arms legible.
Offset ludoHexRingPoint(int index, double radius) {
  const spec = LudoBoardSpec.six;
  final perSide = spec.spacing; // 12

  // Shifted by HALF A SIDE so that each colour's start square sits on its own
  // arm, directly outside its own yard. Without this the ring is a third of a
  // side out of phase and every colour begins beside its neighbour's corner —
  // invisible to the rules, obvious the moment the board is drawn, and exactly
  // the mistake the four-player board shipped with once.
  final shifted = (index - perSide ~/ 2 + spec.ringLength) % spec.ringLength;
  final side = (shifted ~/ perSide) % 6;
  final along = (shifted % perSide) / perSide;

  // The hexagon's corners sit between the arms, so the ring passes across the
  // face of each arm rather than through it.
  Offset corner(int i) {
    final a = ludoHexArmAngle(i) + math.pi / 6;
    return Offset(radius * math.cos(a), radius * math.sin(a));
  }

  final from = corner(side);
  final to = corner(side + 1);
  return Offset.lerp(from, to, along)!;
}

/// The centre of the i-th private square in a colour's run home, 0 nearest the
/// ring. They march straight down the arm's own axis to the middle.
Offset ludoHexHomePoint(LudoColor colour, int i, double radius) {
  final a = ludoHexArmAngle(colour.index);
  // Starts just inside the ring and stops short of the centre disc.
  final t = 0.80 - (i + 1) * (0.62 / (kLudoHomeColumnLength + 1));
  return Offset(radius * t * math.cos(a), radius * t * math.sin(a));
}

/// Where a colour's waiting tokens sit: out past the ring, on its own arm.
Offset ludoHexYardCentre(LudoColor colour, double radius) {
  final a = ludoHexArmAngle(colour.index);
  return Offset(radius * 1.18 * math.cos(a), radius * 1.18 * math.sin(a));
}

/// One waiting token's offset inside a yard, as a fraction of the yard radius.
const List<Offset> kLudoHexYardSlots = [
  Offset(-0.45, -0.45),
  Offset(0.45, -0.45),
  Offset(-0.45, 0.45),
  Offset(0.45, 0.45),
];

/// Where a token sits on the hexagonal board, in board coordinates centred on
/// the middle. Null is never returned; a finished token rests in the centre.
Offset ludoHexTokenPoint(
  LudoColor colour,
  int progress,
  int tokenIndex,
  double radius,
) {
  const spec = LudoBoardSpec.six;
  if (progress == kLudoInYard) {
    final c = ludoHexYardCentre(colour, radius);
    final slot = kLudoHexYardSlots[tokenIndex % 4];
    return c + Offset(slot.dx * radius * 0.16, slot.dy * radius * 0.16);
  }
  if (progress >= spec.home) {
    // Finished: parked in the centre, fanned out so four tokens are countable.
    final a = ludoHexArmAngle(colour.index);
    return Offset(
      radius * 0.10 * math.cos(a) + (tokenIndex - 1.5) * radius * 0.045,
      radius * 0.10 * math.sin(a),
    );
  }
  if (progress > spec.lastRingStep) {
    return ludoHexHomePoint(colour, progress - spec.lastRingStep - 1, radius);
  }
  final cell = (spec.startCellOf(colour) + progress) % spec.ringLength;
  return ludoHexRingPoint(cell, radius);
}

/// Paints the six-player hexagon.
class LudoHexBoardPainter extends CustomPainter {
  const LudoHexBoardPainter({
    required this.surface,
    required this.line,
    required this.darkSurface,
    this.arrows = false,
  });

  final Color surface;
  final Color line;
  final bool darkSurface;
  final bool arrows;

  @override
  void paint(Canvas canvas, Size size) {
    const spec = LudoBoardSpec.six;
    final centre = Offset(size.width / 2, size.height / 2);
    // Leaves room for the yards, which sit outside the ring.
    final radius = size.width * 0.38;
    final cell = radius * 0.085;

    final ground = Color.lerp(
      surface,
      darkSurface ? Colors.white : Colors.black,
      0.10,
    )!;
    final edge = Color.lerp(
      surface,
      darkSurface ? Colors.white : Colors.black,
      0.22,
    )!;
    final fill = Paint()..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.03),
      ),
      fill..color = ground,
    );

    Offset at(Offset p) => centre + p;

    // The six yards, drawn first so the ring sits over their edge.
    for (final c in spec.colours) {
      final base = ludoColorOf(c);
      final yard = at(ludoHexYardCentre(c, radius));
      final r = radius * 0.20;
      canvas.drawCircle(
        yard,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [Color.lerp(base, Colors.white, 0.22)!, base],
          ).createShader(Rect.fromCircle(center: yard, radius: r)),
      );
      canvas.drawCircle(yard, r * 0.74, fill..color = surface);
      for (final slot in kLudoHexYardSlots) {
        canvas.drawCircle(
          yard + Offset(slot.dx * r * 0.8, slot.dy * r * 0.8),
          cell * 0.82,
          fill..color = base.withValues(alpha: 0.16),
        );
      }
    }

    // The ring.
    for (var i = 0; i < spec.ringLength; i++) {
      final p = at(ludoHexRingPoint(i, radius));
      final owner = spec.colours
          .where((c) => spec.startCellOf(c) == i)
          .cast<LudoColor?>()
          .firstWhere((c) => true, orElse: () => null);

      if (owner != null) {
        canvas.drawCircle(p, cell, fill..color = ludoColorOf(owner));
        _chevron(canvas, p, cell * 0.8, _travelAngle(i, radius), Colors.white);
      } else {
        canvas.drawCircle(p, cell, fill..color = surface);
        canvas.drawCircle(
          p,
          cell,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = edge,
        );
        if (spec.safeCells.contains(i)) {
          _star(canvas, p, cell * 0.62, edge);
        }
        if (arrows && spec.arrows.containsKey(i)) {
          canvas.drawCircle(
            p,
            cell,
            fill..color = const Color(0xFF6C4AB6).withValues(alpha: 0.18),
          );
          _chevron(
            canvas,
            p,
            cell * 0.9,
            _travelAngle(i, radius),
            const Color(0xFF6C4AB6),
          );
        }
      }
    }

    // Six runs home, each deepening toward the middle so the direction reads.
    for (final c in spec.colours) {
      final base = ludoColorOf(c);
      for (var i = 0; i < kLudoHomeColumnLength; i++) {
        canvas.drawCircle(
          at(ludoHexHomePoint(c, i, radius)),
          cell * 0.92,
          fill
            ..color = Color.lerp(
              Color.lerp(base, Colors.white, 0.34)!,
              base,
              i / (kLudoHomeColumnLength - 1),
            )!,
        );
      }
    }

    // The centre: six wedges, one per arm, under a disc for finished tokens.
    final wedge = radius * 0.17;
    for (final c in spec.colours) {
      final a = ludoHexArmAngle(c.index);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy)
          ..lineTo(
            centre.dx + wedge * math.cos(a - math.pi / 6),
            centre.dy + wedge * math.sin(a - math.pi / 6),
          )
          ..lineTo(
            centre.dx + wedge * math.cos(a + math.pi / 6),
            centre.dy + wedge * math.sin(a + math.pi / 6),
          )
          ..close(),
        fill..color = ludoColorOf(c),
      );
    }
    canvas.drawCircle(centre, wedge * 0.42, fill..color = surface);
    _star(canvas, centre, wedge * 0.3, edge);
  }

  /// Direction of travel at a ring cell, read from the next cell along so the
  /// arrows can never disagree with the path.
  double _travelAngle(int i, double radius) {
    final a = ludoHexRingPoint(i, radius);
    final b = ludoHexRingPoint((i + 1) % LudoBoardSpec.six.ringLength, radius);
    return math.atan2(b.dy - a.dy, b.dx - a.dx);
  }

  void _chevron(Canvas canvas, Offset c, double r, double angle, Color color) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    Offset at(double d, double spread) => Offset(
      c.dx + d * math.cos(angle) + spread * math.cos(angle + math.pi / 2),
      c.dy + d * math.sin(angle) + spread * math.sin(angle + math.pi / 2),
    );
    canvas.drawPath(
      Path()
        ..moveTo(at(-r * 0.3, -r * 0.5).dx, at(-r * 0.3, -r * 0.5).dy)
        ..lineTo(at(r * 0.4, 0).dx, at(r * 0.4, 0).dy)
        ..lineTo(at(-r * 0.3, r * 0.5).dx, at(-r * 0.3, r * 0.5).dy),
      p,
    );
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(
        c.dx + radius * math.cos(a),
        c.dy + radius * math.sin(a),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(LudoHexBoardPainter old) =>
      old.surface != surface ||
      old.line != line ||
      old.darkSurface != darkSurface ||
      old.arrows != arrows;
}

/// The six-player board, with tappable tokens.
class LudoHexBoard extends StatelessWidget {
  const LudoHexBoard({
    super.key,
    required this.game,
    this.moves = const [],
    this.onMove,
  });

  final LudoGame game;
  final List<LudoMove> moves;
  final void Function(LudoMove move)? onMove;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LudoTheme>(
    valueListenable: ludoTheme,
    builder: (context, theme, _) => AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final size = c.maxWidth;
          final radius = size * 0.38;
          final centre = Offset(size / 2, size / 2);
          final tokenSize = radius * 0.17;

          final tokens = <Widget>[];
          for (final colour in game.players) {
            final mine = game.positions[colour]!;
            for (var i = 0; i < mine.length; i++) {
              final pos =
                  centre + ludoHexTokenPoint(colour, mine[i], i, radius);
              final move = moves.cast<LudoMove?>().firstWhere(
                (m) => m!.color == colour && m.tokenIndex == i,
                orElse: () => null,
              );
              tokens.add(
                Positioned(
                  left: pos.dx - tokenSize / 2,
                  top: pos.dy - tokenSize / 2,
                  width: tokenSize,
                  height: tokenSize,
                  child: _HexToken(
                    color: colour,
                    playable: move != null,
                    onTap: move == null ? null : () => onMove?.call(move),
                  ),
                ),
              );
            }
          }

          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: LudoHexBoardPainter(
                    surface: theme.surface,
                    line: theme.line,
                    darkSurface: theme.dark,
                    arrows: game.mode.arrows,
                  ),
                ),
              ),
              ...tokens,
            ],
          );
        },
      ),
    ),
  );
}

class _HexToken extends StatelessWidget {
  const _HexToken({required this.color, required this.playable, this.onTap});

  final LudoColor color;
  final bool playable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ludoColorOf(color);
    return ValueListenableBuilder<LudoTokenSkin>(
      valueListenable: ludoTokenSkin,
      builder: (context, skin, _) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // No inset here: hexagon tokens are positioned and sized exactly by
        // the layout, so padding them would shrink the piece rather than space
        // it. The cross board pads because its tokens fill a grid cell.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: ludoTokenDecoration(
            colour: c,
            playable: playable,
            skin: skin,
          ),
          // Only the glossy piece wears a specular dot; on a flat or ring
          // token it would read as a smudge.
          child: ludoTokenHasHighlight(skin)
              ? FractionallySizedBox(
                  widthFactor: 0.3,
                  heightFactor: 0.3,
                  alignment: const Alignment(-0.45, -0.55),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
