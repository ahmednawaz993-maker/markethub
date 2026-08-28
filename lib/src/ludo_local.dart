part of '../main.dart';

// Pass-and-play: two to SIX people sharing one phone.
//
// The whole game lives in this widget. No room, no Firestore, no signalling,
// no sign-in — which is the point. A huge amount of Ludo is played by people in
// the same room, and every network feature this app has is overhead they do not
// need. It also works with no connection at all, which in Pakistan is a
// feature and not an edge case.
//
// NO COINS AND NO LEADERBOARD, deliberately. Every player here is the same
// device, so a "win" is worth exactly as much as the person holding the phone
// decides to award themselves. Paying coins for it would be farmable in about
// thirty seconds, and putting it on the leaderboard would make the weekly table
// meaningless. Rewards belong to games played against other people.
//
// THE DICE IS ROLLED ON THE DEVICE. Online it comes from the server, because
// there is somebody to cheat. Here the only person you could cheat is sitting
// next to you.

/// Where a local game is set up before it starts.
class LudoLocalSetupScreen extends StatefulWidget {
  const LudoLocalSetupScreen({super.key});

  @override
  State<LudoLocalSetupScreen> createState() => _LudoLocalSetupScreenState();
}

class _LudoLocalSetupScreenState extends State<LudoLocalSetupScreen> {
  int _players = 2;
  LudoMode _mode = LudoMode.classic;

  /// Names are optional. Asking four people to type before they can play is a
  /// wall in front of a game they wanted to start immediately, so the colours
  /// are the default and a name is something you can add if you want one.
  final Map<LudoColor, TextEditingController> _names = {
    for (final c in LudoColor.values) c: TextEditingController(),
  };

  /// Five or six players move to the hexagon, which is a different board with
  /// a longer ring — so the choice of player count IS the choice of board.
  LudoBoardSpec get _spec => LudoBoardSpec.forSeats(_players);

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<LudoColor> get _seated => LudoColor.values.take(_players).toList();

  void _start() {
    final names = <LudoColor, String>{
      for (final c in _seated)
        c: _names[c]!.text.trim().isEmpty
            ? c.label
            : _names[c]!.text.trim(),
    };
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LudoLocalGameScreen(
          game: LudoGame.newGame(_seated, mode: _mode),
          names: names,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pass and play')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'One phone, passed around. No internet needed and nothing is saved '
          'to your record — it is a game at the table.',
          style: AppType.secondary,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Players', style: AppType.label),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 2, label: Text('2')),
            ButtonSegment(value: 3, label: Text('3')),
            ButtonSegment(value: 4, label: Text('4')),
            ButtonSegment(value: 5, label: Text('5')),
            ButtonSegment(value: 6, label: Text('6')),
          ],
          selected: {_players},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _players = v.first),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _spec.seats == 6
              ? 'Five or six players use the hexagonal board — a longer track '
                    'and six home columns.'
              : 'Two to four players use the classic board.',
          style: AppType.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Game', style: AppType.label),
        const SizedBox(height: AppSpacing.sm),
        // RadioGroup rather than per-tile groupValue: the older form is
        // deprecated in this Flutter, and the analyzer is treated as a gate
        // here rather than noise to scroll past.
        RadioGroup<LudoMode>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? LudoMode.classic),
          child: Column(
            children: [
              for (final m in LudoMode.values)
                RadioListTile<LudoMode>(
                  value: m,
                  title: Text(m.label),
                  subtitle: Text(m.blurb, style: AppType.caption),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Names (optional)', style: AppType.label),
        const SizedBox(height: AppSpacing.sm),
        for (final c in _seated)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TextField(
              controller: _names[c],
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: c.label,
                border: const OutlineInputBorder(),
                // Centred in a fixed box rather than padded into place: a raw
                // inset here is exactly the drift the design-token guard
                // exists to stop, and it caught this one.
                prefixIcon: SizedBox(
                  width: 44,
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ludoColorOf(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start game'),
        ),
        const SizedBox(height: AppSpacing.navClearance),
      ],
    ),
  );
}

/// A local game in progress.
class LudoLocalGameScreen extends StatefulWidget {
  const LudoLocalGameScreen({
    super.key,
    required this.game,
    required this.names,
  });

  final LudoGame game;
  final Map<LudoColor, String> names;

  @override
  State<LudoLocalGameScreen> createState() => _LudoLocalGameScreenState();
}

class _LudoLocalGameScreenState extends State<LudoLocalGameScreen> {
  late LudoGame _game = widget.game;
  final _random = math.Random();
  bool _rolling = false;
  List<LudoMove> _moves = const [];

  String _nameOf(LudoColor c) => widget.names[c] ?? c.label;

  Future<void> _roll() async {
    if (_rolling || _game.lastDice != null || _game.isDecided) return;
    setState(() => _rolling = true);
    GameSoundPlayer.instance.play(GameSound.dice);
    // Long enough for the die to tumble; the animation is the feedback that a
    // roll happened at all.
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    final result = _game.roll(_random.nextInt(6) + 1);
    setState(() {
      _game = result.game;
      _moves = result.moves;
      _rolling = false;
    });
    // A roll with nothing playable hands the turn on by itself — the engine has
    // already done that — so there is nothing to tap and nothing to explain.
    if (result.moves.length == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _play(result.moves.first);
    }
  }

  void _play(LudoMove move) {
    if (_game.isDecided) return;
    setState(() {
      _game = _game.applyMove(move);
      _moves = const [];
    });
    if (move.captures.isNotEmpty) {
      GameSoundPlayer.instance.play(GameSound.capture);
    } else if (move.reachesHome) {
      GameSoundPlayer.instance.play(GameSound.home);
    }
    if (_game.isDecided) GameSoundPlayer.instance.play(GameSound.win);
  }

  Future<void> _confirmQuit() async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this game?'),
        content: const Text(
          'The board is not saved anywhere, so this game cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('End game'),
          ),
        ],
      ),
    );
    if (ok == true) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final turn = _game.currentPlayer;
    final decided = _game.isDecided;
    return PopScope(
      // The board only exists in memory, so a stray back gesture would destroy
      // a game four people are in the middle of.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pass and play'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmQuit,
          ),
          actions: [
            IconButton(
              tooltip: "Collection",
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const LudoCollectionSheet(),
              ),
              icon: const Icon(Icons.palette_outlined),
            ),
            const GameSoundButton(),
          ],
        ),
        body: Column(
          children: [
            _TurnBar(
              colour: turn,
              name: _nameOf(turn),
              decided: decided,
              winner: decided && _game.winners.isNotEmpty
                  ? _nameOf(_game.winners.first)
                  : null,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                // Six seats need the hexagon; anything smaller is the cross.
                // Both take the same game and the same move list, because the
                // rules are identical and only the drawing differs.
                child: _game.spec.seats == 6
                    ? LudoHexBoard(
                        game: _game,
                        moves: _moves,
                        onMove: _play,
                      )
                    : LudoBoard(
                        game: _game,
                        moves: _moves,
                        onMove: _play,
                      ),
              ),
            ),
            if (!decided)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    LudoDice(
                      value: _game.lastDice,
                      rolling: _rolling,
                      enabled: !_rolling && _game.lastDice == null,
                      onTap: _roll,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _game.lastDice == null
                            ? 'Tap the dice to roll.'
                            : _moves.isEmpty
                            ? 'No move with that roll — passing on.'
                            : 'Choose a token to move.',
                        style: AppType.secondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Whose turn it is — the only thing that matters when the phone is being
/// handed round, so it gets the whole width and the player's own colour.
class _TurnBar extends StatelessWidget {
  const _TurnBar({
    required this.colour,
    required this.name,
    required this.decided,
    this.winner,
  });

  final LudoColor colour;
  final String name;
  final bool decided;
  final String? winner;

  @override
  Widget build(BuildContext context) {
    final c = decided ? kPakGreen : ludoColorOf(colour);
    return Container(
      width: double.infinity,
      color: c.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              decided ? '${winner ?? name} won 🎉' : 'Pass to $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sectionTitle,
            ),
          ),
        ],
      ),
    );
  }
}
