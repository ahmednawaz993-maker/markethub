part of '../main.dart';

// The Saanp Seerhi board.
//
// Ten by ten, numbered from the bottom-left and snaking, because that is the
// board people already have a picture of in their heads. Everything here is
// drawn rather than shipped as an image: a picture would need four resolutions
// and would still be the wrong colours in dark mode, and a drawn board can be
// animated along.
//
// The snakes and ladders are drawn from the SAME list the rules use, so a
// snake can never be painted somewhere it does not exist — the classic bug on
// a board like this, and one nobody notices until a player lands on a snake
// that isn't there.

/// The seat colours, reusing the Ludo palette so the two games feel related.
const List<LudoColor> kSnakesSeats = [
  LudoColor.red,
  LudoColor.blue,
  LudoColor.green,
  LudoColor.yellow,
];

class SnakesBoardPainter extends CustomPainter {
  const SnakesBoardPainter({required this.dark});

  final bool dark;

  Color get _light => dark ? const Color(0xFF1B2A44) : const Color(0xFFFFF8E7);
  Color get _shade => dark ? const Color(0xFF15223A) : const Color(0xFFF3E4C3);
  Color get _ink => dark ? const Color(0xFF8AA0C4) : const Color(0xFF8A7143);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / kSnakesSide;
    final fill = Paint()..style = PaintingStyle.fill;
    final board = Offset.zero & size;

    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(u * 0.22)),
      fill..color = _light,
    );

    // Alternating tiles. Subtle: strong contrast here fights the snakes, which
    // are the thing the eye needs to follow.
    for (var square = 1; square <= kSnakesHome; square++) {
      final c = snakesCellOf(square);
      final r = Rect.fromLTWH(c.col * u, c.row * u, u, u);
      if ((c.row + c.col).isEven) {
        canvas.drawRect(r, fill..color = _shade);
      }
      // The number, small and in the corner, so a piece standing on the square
      // never hides it.
      final tp = TextPainter(
        text: TextSpan(
          text: '$square',
          style: TextStyle(
            fontSize: u * 0.22,
            color: _ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.left + u * 0.09, r.top + u * 0.07));
    }

    // The finish, so the last square looks like somewhere to arrive.
    final endCell = snakesCellOf(kSnakesHome);
    final endRect = Rect.fromLTWH(endCell.col * u, endCell.row * u, u, u);
    canvas.drawRect(endRect, fill..color = kLudoSafeStar.withValues(alpha: 0.9));

    for (final s in kSnakesAndLadders) {
      if (s.isLadder) {
        _ladder(canvas, _centreOf(s.from, u), _centreOf(s.to, u), u);
      } else {
        _snake(canvas, _centreOf(s.from, u), _centreOf(s.to, u), u);
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(u * 0.22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.05
        ..color = _ink.withValues(alpha: 0.45),
    );
  }

  Offset _centreOf(int square, double u) {
    final c = snakesCellOf(square);
    return Offset((c.col + 0.5) * u, (c.row + 0.5) * u);
  }

  /// Two rails and a run of rungs, drawn along the line between the squares.
  void _ladder(Canvas canvas, Offset from, Offset to, double u) {
    final along = to - from;
    final len = along.distance;
    if (len < 1) return;
    final dir = along / len;
    // Perpendicular, for the width of the ladder.
    final side = Offset(-dir.dy, dir.dx) * (u * 0.17);

    final rail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.075
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF9A6B3F);
    canvas.drawLine(from + side, to + side, rail);
    canvas.drawLine(from - side, to - side, rail);

    final rungs = (len / (u * 0.42)).round().clamp(2, 40);
    final rung = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.055
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFC08A52);
    for (var i = 1; i < rungs; i++) {
      final p = from + along * (i / rungs);
      canvas.drawLine(p + side, p - side, rung);
    }
  }

  /// A tapering body from head to tail, with a head and two eyes.
  void _snake(Canvas canvas, Offset head, Offset tail, double u) {
    final along = tail - head;
    final len = along.distance;
    if (len < 1) return;
    final dir = along / len;
    final side = Offset(-dir.dy, dir.dx);

    // Three control points, alternating sides, so the body reads as a snake
    // rather than a pipe. The wave scales with length: a short snake with a
    // big wave looks like a knot.
    final wave = (u * 0.55).clamp(0.0, len * 0.22);
    final path = Path()..moveTo(head.dx, head.dy);
    for (var i = 0; i < 3; i++) {
      final t0 = i / 3, t1 = (i + 1) / 3;
      final c = head + along * ((t0 + t1) / 2) + side * (i.isEven ? wave : -wave);
      final e = head + along * t1;
      path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }

    final green = HSLColor.fromAHSL(
      1,
      120 + (head.dx.round() % 60) - 30,
      0.45,
      dark ? 0.42 : 0.34,
    ).toColor();
    // Drawn twice: a dark outline under a lighter body, which is what makes it
    // read as a rounded thing lying ON the board rather than a line drawn
    // across it.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.30
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.22
        ..strokeCap = StrokeCap.round
        ..color = green,
    );

    canvas.drawCircle(head, u * 0.20, Paint()..color = green);
    canvas.drawCircle(
      head,
      u * 0.20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.03
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    for (final s in [1.0, -1.0]) {
      canvas.drawCircle(
        head + side * (u * 0.08 * s) - dir * (u * 0.05),
        u * 0.038,
        Paint()..color = Colors.black87,
      );
    }
  }

  @override
  bool shouldRepaint(SnakesBoardPainter old) => old.dark != dark;
}

/// The board with the pieces on it.
class SnakesBoard extends StatelessWidget {
  const SnakesBoard({super.key, required this.game, this.shown});

  final SnakesGame game;

  /// Positions to draw, when a move is being animated and they differ from the
  /// game's own. Null means "draw the game as it stands".
  final List<int>? shown;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final places = shown ?? game.positions;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = c.maxWidth / kSnakesSide;
          // Pieces sharing a square are fanned, for the same reason as on the
          // Ludo board: drawn on top of each other the lower one is invisible.
          final crowd = <int, List<int>>{};
          for (var i = 0; i < places.length; i++) {
            if (places[i] >= 1) {
              crowd.putIfAbsent(places[i], () => <int>[]).add(i);
            }
          }
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: SnakesBoardPainter(dark: dark)),
              ),
              for (var i = 0; i < places.length; i++)
                if (places[i] >= 1)
                  _piece(i, places[i], crowd[places[i]]!, u),
            ],
          );
        },
      ),
    );
  }

  Widget _piece(int player, int square, List<int> sharing, double u) {
    final cell = snakesCellOf(square);
    final n = sharing.length;
    final k = sharing.indexOf(player);
    final size = u * (n > 1 ? 0.44 : 0.56);
    final spread = n > 1 ? (k - (n - 1) / 2) * u * 0.26 : 0.0;
    final colour = ludoColorOf(kSnakesSeats[player % kSnakesSeats.length]);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: (cell.col + 0.5) * u - size / 2 + spread,
      top: (cell.row + 0.5) * u - size / 2,
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [
              Color.lerp(colour, Colors.white, 0.55)!,
              colour,
              Color.lerp(colour, Colors.black, 0.28)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: Colors.white, width: u * 0.035),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: u * 0.10,
              offset: Offset(0, u * 0.04),
            ),
          ],
        ),
      ),
    );
  }
}
