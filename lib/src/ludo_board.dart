part of '../main.dart';

// The Ludo board: geometry, painting and token hit-testing.
//
// The engine in ludo_engine.dart knows nothing about squares — it works in
// "progress along your own path", 0 to 57. Everything that turns that into a
// place on a 15x15 board lives here, so the rules stay testable without a
// screen and the drawing stays replaceable without touching the rules.
//
// THE GRID. A Ludo board is 15x15. The middle three rows and columns form a
// cross; the four 6x6 corners are the yards; the centre 3x3 is home. The ring
// runs around the cross in 52 cells, and each colour turns off it into a
// private column of six leading to the centre.

/// Row/column on the 15x15 board.
typedef LudoCell = ({int row, int col});

/// The 52 ring cells in path order, starting at Red's start square and running
/// clockwise. Every colour walks this same list, just entering at a different
/// index — which is exactly what [LudoColor.startCell] encodes.
const List<LudoCell> kLudoRing = [
  // left arm, heading right along row 6
  (row: 6, col: 1), (row: 6, col: 2), (row: 6, col: 3), (row: 6, col: 4),
  (row: 6, col: 5),
  // up column 6
  (row: 5, col: 6), (row: 4, col: 6), (row: 3, col: 6), (row: 2, col: 6),
  (row: 1, col: 6), (row: 0, col: 6),
  // across the top
  (row: 0, col: 7),
  // down column 8
  (row: 0, col: 8), (row: 1, col: 8), (row: 2, col: 8), (row: 3, col: 8),
  (row: 4, col: 8), (row: 5, col: 8),
  // right arm, heading right along row 6
  (row: 6, col: 9), (row: 6, col: 10), (row: 6, col: 11), (row: 6, col: 12),
  (row: 6, col: 13), (row: 6, col: 14),
  // down the right edge
  (row: 7, col: 14),
  // back left along row 8
  (row: 8, col: 14), (row: 8, col: 13), (row: 8, col: 12), (row: 8, col: 11),
  (row: 8, col: 10), (row: 8, col: 9),
  // down column 8
  (row: 9, col: 8), (row: 10, col: 8), (row: 11, col: 8), (row: 12, col: 8),
  (row: 13, col: 8), (row: 14, col: 8),
  // across the bottom
  (row: 14, col: 7),
  // up column 6
  (row: 14, col: 6), (row: 13, col: 6), (row: 12, col: 6), (row: 11, col: 6),
  (row: 10, col: 6), (row: 9, col: 6),
  // back left along row 8
  (row: 8, col: 5), (row: 8, col: 4), (row: 8, col: 3), (row: 8, col: 2),
  (row: 8, col: 1), (row: 8, col: 0),
  // up the left edge
  (row: 7, col: 0),
  (row: 6, col: 0),
];

/// The five private cells each colour runs down to reach the centre.
/// Index 0 is the first one off the ring; index 4 sits against the centre.
List<LudoCell> ludoHomeColumn(LudoColor c) => switch (c) {
  LudoColor.red => [for (var i = 1; i <= 5; i++) (row: 7, col: i)],
  LudoColor.green => [for (var i = 1; i <= 5; i++) (row: i, col: 7)],
  LudoColor.yellow => [for (var i = 13; i >= 9; i--) (row: 7, col: i)],
  LudoColor.blue => [for (var i = 13; i >= 9; i--) (row: i, col: 7)],
};

/// The 6x6 corner a colour's un-entered tokens wait in.
///
/// A colour's yard must touch its own START square, or a token appears to jump
/// across the board the moment it leaves the yard. Red starts at (6,1), which
/// sits directly under the top-left corner; the rest follow clockwise from
/// there. Getting this wrong is invisible to the rules and obvious on screen.
({int row, int col}) ludoYardOrigin(LudoColor c) => switch (c) {
  LudoColor.red => (row: 0, col: 0),
  LudoColor.green => (row: 0, col: 9),
  LudoColor.yellow => (row: 9, col: 9),
  LudoColor.blue => (row: 9, col: 0),
};

/// Where the four waiting tokens sit inside a yard, as offsets from its corner.
const List<({int row, int col})> kLudoYardSlots = [
  (row: 1, col: 1),
  (row: 1, col: 4),
  (row: 4, col: 1),
  (row: 4, col: 4),
];

/// The board cell a token occupies, or null when it has finished (it is then
/// drawn in the centre).
LudoCell? ludoCellFor(LudoColor color, int progress, int tokenIndex) {
  final pos = LudoTokenPos(progress);
  if (pos.inYard) {
    final o = ludoYardOrigin(color);
    final slot = kLudoYardSlots[tokenIndex % 4];
    return (row: o.row + slot.row, col: o.col + slot.col);
  }
  if (pos.isHome) return null;
  final ring = pos.ringCell(color);
  if (ring != null) return kLudoRing[ring];
  // Home column: progress 51..56 maps onto the six private cells.
  return ludoHomeColumn(color)[progress - kLudoLastRingStep - 1];
}

Color ludoColorOf(LudoColor c) => switch (c) {
  LudoColor.red => const Color(0xFFD7263D),
  LudoColor.green => const Color(0xFF157F3B),
  LudoColor.yellow => const Color(0xFFE8A33D),
  LudoColor.blue => const Color(0xFF1B6CA8),
};

/// Paints the static board: yards, ring, home columns, centre and stars.
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter({required this.surface, required this.line});

  final Color surface;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 15.0; // one cell
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;

    Rect cellRect(int row, int col) =>
        Rect.fromLTWH(col * u, row * u, u, u);

    // Ground.
    fill.color = surface;
    canvas.drawRect(Offset.zero & size, fill);

    // Yards: a big rounded block of colour with a pale inner well.
    for (final c in LudoColor.values) {
      final o = ludoYardOrigin(c);
      fill.color = ludoColorOf(c);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.col * u, o.row * u, u * 6, u * 6),
          Radius.circular(u * 0.6),
        ),
        fill,
      );
      fill.color = surface;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH((o.col + 1) * u, (o.row + 1) * u, u * 4, u * 4),
          Radius.circular(u * 0.4),
        ),
        fill,
      );
    }

    // Ring.
    for (var i = 0; i < kLudoRing.length; i++) {
      final cell = kLudoRing[i];
      final r = cellRect(cell.row, cell.col);
      // A colour's start square is painted in that colour so players can see
      // where they join; the other safe squares get a star instead.
      final owner = LudoColor.values
          .where((c) => c.startCell == i)
          .cast<LudoColor?>()
          .firstWhere((c) => true, orElse: () => null);
      fill.color = owner != null
          ? ludoColorOf(owner).withValues(alpha: 0.85)
          : surface;
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
      if (owner == null && kLudoSafeCells.contains(i)) {
        _star(canvas, r.center, u * 0.30, line.withValues(alpha: 0.55));
      }
    }

    // Home columns.
    for (final c in LudoColor.values) {
      fill.color = ludoColorOf(c).withValues(alpha: 0.75);
      for (final cell in ludoHomeColumn(c)) {
        final r = cellRect(cell.row, cell.col);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, stroke);
      }
    }

    // Centre: four triangles meeting in the middle, one per colour.
    final centre = Offset(size.width / 2, size.height / 2);
    final tl = Offset(6 * u, 6 * u);
    final tr = Offset(9 * u, 6 * u);
    final br = Offset(9 * u, 9 * u);
    final bl = Offset(6 * u, 9 * u);
    void tri(Offset a, Offset b, LudoColor c) {
      fill.color = ludoColorOf(c);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(centre.dx, centre.dy)
          ..close(),
        fill,
      );
    }

    tri(bl, tl, LudoColor.red); // red arrives from the left
    tri(tl, tr, LudoColor.green); // green from the top
    tri(tr, br, LudoColor.yellow); // yellow from the right
    tri(br, bl, LudoColor.blue); // blue from the bottom
    canvas.drawRect(Rect.fromPoints(tl, br), stroke);
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(LudoBoardPainter old) =>
      old.surface != surface || old.line != line;
}

/// The board plus its tokens. Tapping a token that has a legal move plays it.
/// The board plus its tokens. Tapping a token that has a legal move plays it.
///
/// It animates any position change it is HANDED rather than being told to move.
/// That matters because moves arrive from three places — this player, an
/// opponent's device, and the server playing a bot or an abandoned turn — and
/// only the board knows what actually changed. Diffing the incoming state means
/// all three animate identically with no coordination between them.
class LudoBoard extends StatefulWidget {
  const LudoBoard({
    super.key,
    required this.game,
    required this.moves,
    this.onMove,
    this.highlightColor,
  });

  final LudoGame game;

  /// Moves currently playable. Tokens with a move get a ring and a tap target.
  final List<LudoMove> moves;
  final void Function(LudoMove)? onMove;

  /// Whose turn to emphasise, when it is not simply [LudoGame.currentPlayer].
  final LudoColor? highlightColor;

  @override
  State<LudoBoard> createState() => _LudoBoardState();
}

/// One token in flight.
class _Flight {
  const _Flight({
    required this.color,
    required this.tokenIndex,
    required this.from,
    required this.to,
  });

  final LudoColor color;
  final int tokenIndex;
  final int from;
  final int to;

  /// A token advancing walks the board square by square. A captured one flies
  /// straight back to its yard, because there is no path to retrace.
  bool get isWalk => from >= 0 && to > from;
  int get steps => isWalk ? to - from : 1;
}

class _LudoBoardState extends State<LudoBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// Where the tokens are currently DRAWN, which lags the game state while a
  /// move plays out.
  Map<LudoColor, List<int>> _shown = {};
  List<_Flight> _flights = const [];

  /// Timed per square, not per move — a six should visibly take longer than a
  /// one, the way it does on a real board.
  static const Duration _perStep = Duration(milliseconds: 105);
  static const Duration _hop = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _shown = _copy(widget.game.positions);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {
          _shown = _copy(widget.game.positions);
          _flights = const [];
        });
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static Map<LudoColor, List<int>> _copy(Map<LudoColor, List<int>> m) => {
    for (final e in m.entries) e.key: List<int>.from(e.value),
  };

  @override
  void didUpdateWidget(LudoBoard old) {
    super.didUpdateWidget(old);
    final next = widget.game.positions;
    final flights = <_Flight>[];
    for (final color in widget.game.players) {
      final now = next[color];
      final was = _shown[color];
      if (now == null || was == null || was.length != now.length) continue;
      for (var i = 0; i < now.length; i++) {
        if (was[i] != now[i]) {
          flights.add(
            _Flight(color: color, tokenIndex: i, from: was[i], to: now[i]),
          );
        }
      }
    }
    if (flights.isEmpty) {
      // Nothing moved, but the seats may have changed while waiting to start.
      if (_flights.isEmpty) _shown = _copy(next);
      return;
    }
    // The longest walk sets the pace, so a capture and the move that caused it
    // land together instead of stuttering.
    final steps = flights
        .map((f) => f.isWalk ? f.steps : 0)
        .fold<int>(0, math.max);
    _c.duration = steps > 0 ? _perStep * steps : _hop;
    setState(() => _flights = flights);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final playable = {
      for (final m in widget.moves) '${m.color.name}:${m.tokenIndex}': m,
    };
    final flying = {
      for (final f in _flights) '${f.color.name}:${f.tokenIndex}': f,
    };

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / 15.0;
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final tokens = <Widget>[];
              // Finished tokens are stacked in the centre so a player can see
              // how many they have brought home at a glance.
              final homeTally = <LudoColor, int>{};

              for (final color in widget.game.players) {
                final list = _shown[color] ?? widget.game.positions[color]!;
                for (var i = 0; i < list.length; i++) {
                  final key = '${color.name}:$i';
                  final flight = flying[key];
                  final move = playable[key];

                  Offset at(int p) {
                    final cell = ludoCellFor(color, p, i);
                    if (cell != null) {
                      return Offset(cell.col * u, cell.row * u);
                    }
                    final n = homeTally[color] ?? 0;
                    final base = _centreSlot(color, u);
                    return Offset(base.dx + n * u * 0.18, base.dy);
                  }

                  Offset pos;
                  if (flight == null) {
                    final p = list[i];
                    if (ludoCellFor(color, p, i) == null) {
                      homeTally.update(color, (v) => v + 1, ifAbsent: () => 0);
                    }
                    pos = at(p);
                  } else if (flight.isWalk) {
                    // Square by square, easing between the two cells the token
                    // is between right now.
                    final travelled = _c.value * flight.steps;
                    final done = travelled.floor().clamp(0, flight.steps - 1);
                    final frac = (travelled - done).clamp(0.0, 1.0);
                    pos = Offset.lerp(
                      at(flight.from + done),
                      at(flight.from + done + 1),
                      frac,
                    )!;
                  } else {
                    // Captured, or stepping out of the yard: one smooth hop.
                    pos = Offset.lerp(
                      at(flight.from),
                      at(flight.to),
                      Curves.easeInOutCubic.transform(_c.value),
                    )!;
                  }

                  // A small lift mid-flight reads as the piece being picked up
                  // and put down, rather than sliding along the board.
                  final lift = flight == null
                      ? 0.0
                      : math.sin(_c.value * math.pi) * u * 0.18;

                  tokens.add(
                    Positioned(
                      left: pos.dx,
                      top: pos.dy - lift,
                      width: u,
                      height: u,
                      child: _Token(
                        color: color,
                        // A token in flight is not tappable — a second tap
                        // mid-animation would play a move against a board the
                        // player can no longer see.
                        playable: move != null && flight == null,
                        onTap: move == null || flight != null
                            ? null
                            : () => widget.onMove?.call(move),
                      ),
                    ),
                  );
                }
              }

              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: LudoBoardPainter(
                        surface: AppColors.surface,
                        line: AppColors.borderSoft,
                      ),
                    ),
                  ),
                  ...tokens,
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Where a finished token rests, inside that colour's centre triangle.
  Offset _centreSlot(LudoColor c, double u) => switch (c) {
    LudoColor.red => Offset(6.05 * u, 7.0 * u),
    LudoColor.green => Offset(7.0 * u, 6.05 * u),
    LudoColor.yellow => Offset(7.6 * u, 7.0 * u),
    LudoColor.blue => Offset(7.0 * u, 7.6 * u),
  };
}

class _Token extends StatelessWidget {
  const _Token({required this.color, required this.playable, this.onTap});

  final LudoColor color;
  final bool playable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ludoColorOf(color);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: playable ? Colors.white : Colors.white70,
              width: playable ? 2.5 : 1.5,
            ),
            boxShadow: playable
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
        ),
      ),
    );
  }
}
