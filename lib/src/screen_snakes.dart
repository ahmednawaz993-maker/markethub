part of '../main.dart';

// Saanp Seerhi, on one phone.
//
// Deliberately local-only for now, and that is a design decision rather than a
// shortcut. Ludo online carries a server-side roll, a rules mirror in Cloud
// Functions, security rules for every write, rooms, stakes and a bot that
// plays when somebody walks off — a large amount of machinery that exists
// because a Ludo game lasts twenty minutes and people leave halfway.
//
// A game of Saanp Seerhi is around forty rolls. It is the game you hand across
// the table, and it works perfectly with everybody looking at one screen. If
// people ask for it online, the engine is already pure and ready to be
// mirrored server-side; building that before anybody has played it would be
// guessing.

/// How long the board is left showing the roll before the piece sets off.
const Duration _kSnakesReadRoll = Duration(milliseconds: 380);

/// How long a snake or a ladder takes, once the piece has stepped.
const Duration _kSnakesSlide = Duration(milliseconds: 420);

class SnakesSetupScreen extends StatefulWidget {
  const SnakesSetupScreen({super.key});

  @override
  State<SnakesSetupScreen> createState() => _SnakesSetupScreenState();
}

class _SnakesSetupScreenState extends State<SnakesSetupScreen> {
  int _players = 2;
  bool _vsComputer = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saanp Seerhi')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Players', style: AppType.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Everybody plays on this phone — pass it round after each turn.',
                style: AppType.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final n in [2, 3, 4])
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _players == n,
                      onSelected: (_) => setState(() => _players = n),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _vsComputer,
                onChanged: (v) => setState(() => _vsComputer = v),
                title: const Text('Play against the computer'),
                subtitle: Text(
                  _vsComputer
                      ? 'You are red; the rest roll for themselves'
                      : 'Every colour is rolled by a person',
                  style: AppType.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SnakesScreen(players: _players, vsComputer: _vsComputer),
            ),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How it goes', style: AppType.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final line in const [
                'Roll and move. No six needed to start.',
                'A ladder carries you up, a snake takes you down.',
                'A six earns another roll — three in a row loses the turn.',
                'You must land on 100 exactly.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('•  $line', style: AppType.caption),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SnakesScreen extends StatefulWidget {
  const SnakesScreen({
    super.key,
    required this.players,
    required this.vsComputer,
  });

  final int players;
  final bool vsComputer;

  @override
  State<SnakesScreen> createState() => _SnakesScreenState();
}

class _SnakesScreenState extends State<SnakesScreen> {
  late SnakesGame _game = SnakesGame.newGame(widget.players);
  final _rng = math.Random();

  int? _dice;
  bool _busy = false;

  /// The computer's pending turn.
  ///
  /// Held so it can be CANCELLED. A bare Future.delayed with a `mounted` check
  /// inside guards the callback but leaves the timer itself running — so
  /// leaving the screen mid-game left a timer alive behind it, and a widget
  /// test that popped the screen failed at teardown with "a Timer is still
  /// pending". The guard hid the symptom; this removes the timer.
  Timer? _botTimer;

  /// What the board is showing while a move plays out. The piece steps to
  /// where the die landed first, and only then slides down the snake — showing
  /// the final square immediately would hide the whole point of the game.
  List<int>? _shown;

  bool get _isComputer => widget.vsComputer && _game.turn != 0;

  String _nameOf(int i) => widget.vsComputer
      ? (i == 0 ? 'You' : 'Computer $i')
      : 'Player ${i + 1}';

  @override
  void initState() {
    super.initState();
    _maybeComputerTurn();
  }

  Future<void> _roll() async {
    if (_busy || _game.isOver) return;
    setState(() {
      _busy = true;
      _dice = null;
    });
    GameSoundPlayer.instance.play(GameSound.dice);

    final value = _rng.nextInt(6) + 1;
    final before = _game;
    final next = before.roll(value);
    final move = next.lastMove!;

    setState(() => _dice = value);
    await Future<void>.delayed(_kSnakesReadRoll);
    if (!mounted) return;

    if (!move.blocked) {
      // Step to where the die landed.
      final stepped = [...before.positions]..[move.player] = move.landed;
      setState(() => _shown = stepped);
      GameSoundPlayer.instance.play(GameSound.move);
      await Future<void>.delayed(_kSnakesSlide);
      if (!mounted) return;
      if (move.jump != null) {
        GameSoundPlayer.instance.play(
          move.jump!.isSnake ? GameSound.capture : GameSound.home,
        );
        await Future<void>.delayed(_kSnakesSlide);
        if (!mounted) return;
      }
    }

    setState(() {
      _game = next;
      _shown = null;
      _busy = false;
    });
    if (next.isOver) {
      GameSoundPlayer.instance.play(GameSound.win);
    } else {
      _maybeComputerTurn();
    }
  }

  void _maybeComputerTurn() {
    _botTimer?.cancel();
    if (!_isComputer || _game.isOver) return;
    // A beat before the computer rolls. Instant, it reads as the app playing
    // itself rather than as an opponent taking a turn.
    _botTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted && _isComputer && !_game.isOver && !_busy) _roll();
    });
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final move = _game.lastMove;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saanp Seerhi'),
        actions: [
          IconButton(
            tooltip: 'Start again',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _game = SnakesGame.newGame(widget.players);
              _dice = null;
              _shown = null;
              _busy = false;
              _maybeComputerTurn();
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  for (var i = 0; i < widget.players; i++)
                    Expanded(
                      child: _PlayerChip(
                        name: _nameOf(i),
                        square: _game.positions[i],
                        colour: ludoColorOf(
                          kSnakesSeats[i % kSnakesSeats.length],
                        ),
                        active: _game.turn == i && !_game.isOver,
                      ),
                    ),
                ],
              ),
            ),
            // The board and the dice are ONE group, centred together. Left as
            // an Expanded board with the dice pinned to the bottom of the
            // screen, a tall phone put a hand's width of empty space between
            // the thing you look at and the thing you tap.
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: SnakesBoard(game: _game, shown: _shown),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            LudoDice(
                              value: _dice,
                              rolling: _busy && _dice == null,
                              enabled:
                                  !_busy && !_game.isOver && !_isComputer,
                              onTap: _roll,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: _status(move)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(SnakesMove? move) {
    if (_game.isOver) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_nameOf(_game.winner!)} wins', style: AppType.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          FilledButton(
            onPressed: () => setState(() {
              _game = SnakesGame.newGame(widget.players);
              _dice = null;
              _maybeComputerTurn();
            }),
            child: const Text('Play again'),
          ),
        ],
      );
    }

    // What just happened, in words. On a board this size a piece moving three
    // squares is easy to miss entirely, and "why am I suddenly at 19?" is the
    // question the game has to answer.
    String line;
    if (move == null) {
      line = 'Tap the dice to start.';
    } else if (move.blocked && move.dice == 6) {
      line = 'Three sixes — turn lost.';
    } else if (move.blocked) {
      line = '${_nameOf(move.player)} needs exactly '
          '${kSnakesHome - move.from} to finish.';
    } else if (move.jump?.isLadder ?? false) {
      line = 'Ladder! ${move.landed} up to ${move.to}.';
    } else if (move.jump?.isSnake ?? false) {
      line = 'Snake! ${move.landed} down to ${move.to}.';
    } else if (move.won) {
      line = 'Home!';
    } else {
      line = '${_nameOf(move.player)} moved to ${move.to}.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isComputer
              ? 'Computer is rolling…'
              // "You's turn" — the name of the human player in single-player
              // is "You", so the possessive has to be special-cased or the
              // status line is broken English on the most-played mode.
              : _nameOf(_game.turn) == 'You'
              ? 'Your turn'
              : "${_nameOf(_game.turn)}'s turn",
          style: AppType.sectionTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(line, style: AppType.caption),
      ],
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.name,
    required this.square,
    required this.colour,
    required this.active,
  });

  final String name;
  final int square;
  final Color colour;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: active ? colour.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: AppRadius.rMd,
      border: Border.all(
        color: active ? colour : AppColors.borderSoft,
        width: active ? 2 : 1,
      ),
    ),
    child: Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.caption,
        ),
        Text('$square', style: AppType.sectionTitle),
      ],
    ),
  );
}
