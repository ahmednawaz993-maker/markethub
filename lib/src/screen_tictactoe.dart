part of '../main.dart';

// Tic-tac-toe, on one phone.
//
// The short game: it opens in a tap and costs nothing to abandon. Two people
// on one screen, or one against an opponent that on Hard cannot be beaten —
// a claim the tests check exhaustively rather than by spot-check, because it
// is either true or it is a lie a player will catch in three rounds.

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  TicBoard _board = ticNewBoard();
  TicMark _turn = TicMark.x;
  bool _vsComputer = true;
  bool _hard = true;
  bool _thinking = false;

  /// Kept across rounds, because a single game of tic-tac-toe is not a game —
  /// a run of them is.
  int _youWon = 0, _theyWon = 0, _drawn = 0;

  /// The human is always X and always opens. Alternating who starts is fairer
  /// in principle and confusing in practice on a board this small.
  static const TicMark _human = TicMark.x;
  static const TicMark _bot = TicMark.o;

  void _reset() => setState(() {
    _board = ticNewBoard();
    _turn = TicMark.x;
    _thinking = false;
  });

  void _play(int i) {
    if (_board[i] != null || ticIsOver(_board) || _thinking) return;
    if (_vsComputer && _turn != _human) return;
    _apply(i, _turn);
  }

  void _apply(int i, TicMark mark) {
    final next = [..._board]..[i] = mark;
    final over = ticIsOver(next);
    setState(() {
      _board = next;
      _turn = ticOther(mark);
      if (over) _recordResult(next);
    });
    GameSoundPlayer.instance.play(over ? GameSound.home : GameSound.move);
    if (!over && _vsComputer && _turn == _bot) _botTurn();
  }

  void _recordResult(TicBoard board) {
    final w = ticWinner(board);
    if (w == null) {
      _drawn++;
    } else if (!_vsComputer) {
      // Two people on one phone: X's column is "X wins".
      w == TicMark.x ? _youWon++ : _theyWon++;
    } else if (w == _human) {
      _youWon++;
    } else {
      _theyWon++;
    }
    if (w != null) GameSoundPlayer.instance.play(GameSound.win);
  }

  Future<void> _botTurn() async {
    setState(() => _thinking = true);
    // A beat, so the reply does not appear in the same frame as your own move.
    // The search itself takes under a millisecond; without the pause the board
    // simply changes twice at once and the game feels like it is playing you.
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    final move = _hard
        ? ticBestMove(_board, _bot)
        : ticEasyMove(_board, _bot);
    setState(() => _thinking = false);
    if (move != null) _apply(move, _bot);
  }

  @override
  Widget build(BuildContext context) {
    final line = ticWinningLine(_board);
    final winner = ticWinner(_board);
    final over = ticIsOver(_board);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tic Tac Toe'),
        actions: [
          IconButton(
            tooltip: 'New round',
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              _scoreboard(),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _grid(line),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                over
                    ? (winner == null
                          ? 'Drawn.'
                          : _vsComputer
                          ? (winner == _human ? 'You win.' : 'Computer wins.')
                          : '${winner == TicMark.x ? "X" : "O"} wins.')
                    : _thinking
                    ? 'Computer is thinking…'
                    : _vsComputer
                    ? (_turn == _human ? 'Your turn' : 'Computer’s turn')
                    : '${_turn == TicMark.x ? "X" : "O"} to play',
                style: AppType.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.md),
              if (over)
                FilledButton(
                  onPressed: _reset,
                  child: const Text('Play again'),
                ),
              const SizedBox(height: AppSpacing.lg),
              _options(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreboard() => Row(
    children: [
      _score(_vsComputer ? 'You' : 'X', _youWon, ludoColorOf(LudoColor.blue)),
      _score('Drawn', _drawn, AppColors.textSecondary),
      _score(
        _vsComputer ? 'Computer' : 'O',
        _theyWon,
        ludoColorOf(LudoColor.red),
      ),
    ],
  );

  Widget _score(String label, int value, Color colour) => Expanded(
    child: Column(
      children: [
        Text('$value', style: AppType.sectionTitle.copyWith(color: colour)),
        Text(label, style: AppType.caption),
      ],
    ),
  );

  Widget _grid(List<int>? line) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, c) {
        final cell = c.maxWidth / 3;
        return Stack(
          // Keyed so a test can tell a mark ON THE BOARD from the letter X in
          // the scoreboard above it.
          key: const ValueKey('ticBoard'),
          children: [
            for (var i = 0; i < 9; i++)
              Positioned(
                left: (i % 3) * cell,
                top: (i ~/ 3) * cell,
                width: cell,
                height: cell,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: _Cell(
                    mark: _board[i],
                    // The winning three stay lit; the rest fade back, so the
                    // line that won is readable without an arrow drawn over it.
                    dimmed: line != null && !line.contains(i),
                    onTap: () => _play(i),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _options() => AppCard(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _vsComputer,
          onChanged: (v) => setState(() {
            _vsComputer = v;
            _reset();
          }),
          title: const Text('Play against the computer'),
          subtitle: Text(
            _vsComputer ? 'You are X and go first' : 'Two players, one phone',
            style: AppType.caption,
          ),
        ),
        if (_vsComputer)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _hard,
            onChanged: (v) => setState(() {
              _hard = v;
              _reset();
            }),
            title: const Text('Hard'),
            subtitle: Text(
              _hard
                  ? 'Cannot be beaten — the best you can do is draw'
                  : 'Takes a win and blocks a loss, but does not plan',
              style: AppType.caption,
            ),
          ),
      ],
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.mark, required this.dimmed, required this.onTap});

  final TicMark? mark;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = mark == TicMark.x
        ? ludoColorOf(LudoColor.blue)
        : ludoColorOf(LudoColor.red);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: dimmed ? 0.35 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.rMd,
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: mark == null
              ? const SizedBox.expand()
              // Named, because a painted mark is silent to a screen reader —
              // it has no text in it to read out. This is also how the tests
              // tell an X from an O now that neither is a glyph.
              : Semantics(
                  label: mark == TicMark.x ? 'X' : 'O',
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: CustomPaint(
                      painter: _MarkPainter(mark: mark!, colour: colour),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The X and the O, drawn rather than typed.
///
/// A glyph is a dependency on the shipped font actually containing it, and
/// this app has shipped a blank button before for exactly that reason — an
/// icon that was not in the font at all, invisible in every test because the
/// test font draws a box for everything. Two strokes and a circle cannot go
/// missing, scale cleanly to any cell size, and answer to the app's palette.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.mark, required this.colour});

  final TicMark mark;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round
      ..color = colour;

    if (mark == TicMark.o) {
      canvas.drawCircle(c, r * 0.76, p);
      return;
    }
    final d = r * 0.66;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), p);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), p);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.colour != colour;
}
