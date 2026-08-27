part of '../main.dart';

// The dice face.
//
// The NUMBER is not decided here — the server rolls it (see functions/ludo_logic
// and the ludoRoll callable) and this only reveals it. So the tumble is honest
// theatre: it shows faces changing while the caller waits for the network, then
// settles on whatever came back. It never invents a value, not even for a frame
// after the real one is known.

/// A dice face drawn as pips, so it reads at any size and needs no asset.
class LudoDieFace extends StatelessWidget {
  const LudoDieFace({
    super.key,
    required this.value,
    this.size = 52,
    this.color,
  });

  /// 1..6, or null before the first roll.
  final int? value;
  final double size;
  final Color? color;

  /// Pip layout per face, in a 3x3 grid indexed 0..8.
  static const Map<int, List<int>> _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final on = _pips[value] ?? const <int>[];
    final ink = color ?? AppColors.textPrimary;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: AppShadow.card,
      ),
      child: value == null
          ? Center(
              child: Text(
                '–',
                style: TextStyle(
                  fontSize: size * 0.4,
                  color: AppColors.textMuted,
                ),
              ),
            )
          : GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 9; i++)
                  Center(
                    child: on.contains(i)
                        ? Container(
                            width: size * 0.14,
                            height: size * 0.14,
                            decoration: BoxDecoration(
                              color: ink,
                              shape: BoxShape.circle,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
    );
  }
}

/// A die that tumbles while [rolling] is true and settles on [value].
///
/// The caller sets [rolling] for as long as it is waiting on the server, so the
/// animation length matches the actual wait instead of a guessed duration — on
/// a slow connection the die keeps turning rather than freezing on a stale face.
class LudoDice extends StatefulWidget {
  const LudoDice({
    super.key,
    required this.value,
    required this.rolling,
    this.size = 56,
    this.onTap,
    this.enabled = false,
  });

  final int? value;
  final bool rolling;
  final double size;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<LudoDice> createState() => _LudoDiceState();
}

class _LudoDiceState extends State<LudoDice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  final _rng = math.Random();
  Timer? _shuffle;
  int _face = 1;

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _start();
  }

  @override
  void didUpdateWidget(LudoDice old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !old.rolling) _start();
    if (!widget.rolling && old.rolling) _stop();
  }

  void _start() {
    _c.repeat();
    // Faces change on their own timer rather than off the animation value, so
    // the tumble does not visibly sync with the spin and look mechanical.
    _shuffle = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() => _face = 1 + _rng.nextInt(6));
    });
  }

  void _stop() {
    _shuffle?.cancel();
    _shuffle = null;
    _c.stop();
    // A short settle so the final face arrives with a bounce rather than a cut.
    _c.duration = const Duration(milliseconds: 260);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _shuffle?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled && !widget.rolling ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Spin while rolling; on settling, a single overshoot-and-return.
          final t = _c.value;
          final angle = widget.rolling
              ? t * 2 * math.pi
              : math.sin(t * math.pi) * 0.18;
          final scale = widget.rolling
              ? 1.0
              : 1 + math.sin(t * math.pi) * 0.10;
          return Opacity(
            opacity: widget.enabled || widget.rolling ? 1 : 0.55,
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: LudoDieFace(
                  value: widget.rolling ? _face : widget.value,
                  size: widget.size,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
