part of '../main.dart';

// Sound effects for the game screens.
//
// Three things decide the design here, and all three come from the audience:
// most of these players are on budget Android phones, often in shared spaces,
// and often on metered data.
//
//  * Assets are bundled and tiny (168 KB for all five), so nothing downloads.
//  * Sound is OFF until the player turns it on. An app that starts making
//    noise in a room full of people gets uninstalled, not muted.
//  * A failure to play is swallowed. No cue is worth an error dialog, and
//    audio focus on Android is genuinely unreliable — another app holding it
//    must not break the game.

enum GameSound {
  dice('ludo_dice.wav'),
  move('ludo_move.wav'),
  capture('ludo_capture.wav'),
  home('ludo_home.wav'),
  win('ludo_win.wav');

  const GameSound(this.asset);
  final String asset;

  String get path => 'sounds/$asset';
}

const String _kPrefGameSound = 'game_sound_on';

/// Whether cues play. Off by default; a [ValueNotifier] so the toggle in the
/// game screen updates without threading state through the board.
final ValueNotifier<bool> gameSoundOn = ValueNotifier<bool>(false);

Future<void> loadGameSoundPref() async {
  try {
    final p = await SharedPreferences.getInstance();
    gameSoundOn.value = p.getBool(_kPrefGameSound) ?? false;
  } catch (_) {
    // Leave it off — the safe default is silence.
  }
}

Future<void> setGameSoundOn(bool on) async {
  gameSoundOn.value = on;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPrefGameSound, on);
  } catch (_) {}
}

/// Plays short game cues.
///
/// Holds a small pool of players rather than one: a token walking six squares
/// fires six ticks in half a second, and a single player would cut each one off
/// to start the next, producing one click instead of six.
class GameSoundPlayer {
  GameSoundPlayer._();
  static final GameSoundPlayer instance = GameSoundPlayer._();

  static const int _poolSize = 4;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _ready = false;

  Future<void> _ensure() async {
    if (_ready) return;
    _ready = true;
    for (var i = 0; i < _poolSize; i++) {
      final p = AudioPlayer();
      // Cues must duck under nothing and interrupt nothing — this is a game,
      // not a phone call.
      await p.setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
    }
  }

  /// Fire and forget. Never awaited by the UI: a cue that arrives late is
  /// harmless, a frame dropped waiting for one is not.
  void play(GameSound sound) {
    if (!gameSoundOn.value) return;
    unawaited(_play(sound));
  }

  Future<void> _play(GameSound sound) async {
    try {
      await _ensure();
      final p = _pool[_next % _pool.length];
      _next++;
      await p.stop();
      await p.play(AssetSource(sound.path), volume: 0.7);
    } catch (_) {
      // Audio focus, a missing codec, a device with no output — none of it is
      // worth interrupting a game for.
    }
  }

  /// Walks a token: one tick per square, spaced to match the board animation
  /// so the sound lands with each step rather than as a burst.
  /// Must match _perStep in ludo_board.dart: a tick that lags the token reads
  /// as an echo rather than a footstep.
  static const Duration walkStepDefault = Duration(milliseconds: 55);

  void walk(int squares, {Duration perStep = walkStepDefault}) {
    if (!gameSoundOn.value || squares <= 0) return;
    for (var i = 0; i < squares && i < 6; i++) {
      Future.delayed(perStep * i, () => play(GameSound.move));
    }
  }

  Future<void> dispose() async {
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    _ready = false;
  }
}

/// The speaker toggle shown in the game's app bar.
class GameSoundButton extends StatelessWidget {
  const GameSoundButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: gameSoundOn,
    builder: (context, on, _) => IconButton(
      tooltip: on ? 'Sound on' : 'Sound off',
      icon: Icon(on ? Icons.volume_up : Icons.volume_off),
      onPressed: () {
        setGameSoundOn(!on);
        // Play one cue on the way ON so the player hears what they enabled.
        if (!on) GameSoundPlayer.instance.play(GameSound.move);
      },
    ),
  );
}
