part of '../main.dart';

// Ludo coins on the client.
//
// PLAY MONEY. PakBazar holds real funds — a wallet balance, escrow on live
// orders, withdrawals to real bank accounts — so the single most important
// thing about this screen is that nobody ever confuses the two numbers. That
// drives every decision here:
//
//  * Coins appear in the Ludo section and NOWHERE ELSE. Not on the wallet
//    screen, not in the profile, not next to a price.
//  * They are never written with a currency symbol and never called a balance.
//  * The claim sheet says plainly that they are not real money and cannot be
//    withdrawn, because a user should not have to infer that.
//
// The client cannot change a balance. It reads the profile and writes a request
// document; a Cloud Function decides what anything is worth. firestore.rules
// makes the profile read-only, so this is enforced rather than trusted.

/// Coins a player starts with. Must match STARTING_COINS in game_economy.js —
/// this is only used so a brand new profile shows the right number before the
/// server has written one.
const int kStartingCoins = 500;

/// Wins needed to earn a chest. Mirrors WINS_PER_CHEST in game_economy.js.
const int kWinsPerChest = 3;

/// A player's game profile.
class GameProfile {
  const GameProfile({
    this.coins = kStartingCoins,
    this.streak = 0,
    this.chests = 0,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.lastDailyAt,
  });

  final int coins;
  final int streak;
  final int chests;
  final int gamesPlayed;
  final int gamesWon;
  final DateTime? lastDailyAt;

  /// Tolerant of whatever is actually in the document.
  ///
  /// A plain `as num?` cast THROWS when the field holds a string, and this
  /// widget sits in the Ludo app bar — so one hand-edited value in the Firebase
  /// console would take down the whole screen rather than showing a wrong
  /// number. Same reasoning as AppGateState._asInt.
  static int _asInt(Object? v, int fallback) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static GameProfile fromMap(Map<String, dynamic>? d) {
    if (d == null) return const GameProfile();
    final ms = d['lastDailyAt'];
    return GameProfile(
      coins: _asInt(d['coins'], kStartingCoins),
      streak: _asInt(d['streak'], 0),
      chests: _asInt(d['chests'], 0),
      gamesPlayed: _asInt(d['gamesPlayed'], 0),
      gamesWon: _asInt(d['gamesWon'], 0),
      lastDailyAt: ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : null,
    );
  }

  /// Wins still needed before the next chest.
  ///
  /// Sitting exactly on a boundary means a chest was just earned, so the next
  /// one is a full run away — never "0 more wins".
  int get winsToNextChest {
    final into = gamesWon % kWinsPerChest;
    return into == 0 ? kWinsPerChest : kWinsPerChest - into;
  }

  /// Whether today's reward is still unclaimed.
  ///
  /// Mirrors resolveDaily in game_economy.js, deliberately: the server decides,
  /// but the button must not invite a tap that will be silently refused. Days
  /// are counted in PAKISTAN time — using the device's local day would let a
  /// traveller, or anyone with a wrong clock, see the wrong state.
  bool get canClaimDaily {
    final last = lastDailyAt;
    if (last == null) return true;
    return pktDayNumber(last) != pktDayNumber(DateTime.now());
  }

  /// The Pakistan calendar day a moment falls on.
  ///
  /// Public and named to match pktDayNumber() in game_economy.js, because the
  /// two must agree: this decides whether the button is offered, that decides
  /// whether the claim is honoured.
  static int pktDayNumber(DateTime t) {
    // PKT is UTC+5 with no daylight saving, which is the only reason a fixed
    // offset is correct here.
    final shifted = t.toUtc().add(const Duration(hours: 5));
    return shifted.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }
}

/// Groups a coin count with commas.
///
/// Deliberately NOT formatPrice(), even though it would produce the same digits
/// today. That function is the money formatter, and the day it gains a "PKR"
/// prefix or a decimal place is the day coins start looking like currency. The
/// separation is the point.
String formatCoins(int coins) {
  final digits = coins.abs().toString();
  final out = StringBuffer(coins < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

DocumentReference<Map<String, dynamic>> _gameProfileRef(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('game')
        .doc('profile');

/// Live game profile for the signed-in player, or null when signed out.
Stream<GameProfile>? gameProfileStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return _gameProfileRef(uid).snapshots().map((d) => GameProfile.fromMap(d.data()));
}

/// Asks the server for something. What it is worth is not ours to decide.
Future<void> _sendGameRequest(String type) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('gameRequests')
      .add({'type': type, 'at': Timestamp.now()});
}

Future<void> claimDailyCoins() => _sendGameRequest('daily');
Future<void> openCoinChest() => _sendGameRequest('chest');

/// The coin count, for the Ludo app bar.
class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins, this.onTap});

  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppRadius.rLg,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF6C445).withValues(alpha: 0.16),
        borderRadius: AppRadius.rLg,
        border: Border.all(color: const Color(0xFFF6C445)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 13)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            // Grouped, but never with a currency symbol — this is not money and
            // must not be able to be read as a price.
            formatCoins(coins),
            style: AppType.label.copyWith(
              fontWeight: FontWeight.w800,
              // Tabular figures so the number does not jitter as it changes.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The rewards sheet: today's coins, and any chests waiting.
class CoinRewardsSheet extends StatelessWidget {
  const CoinRewardsSheet({super.key, required this.profile});

  final GameProfile profile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Ludo coins', style: AppType.sectionTitle),
                const Spacer(),
                CoinPill(coins: profile.coins),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Said outright rather than left to be inferred. Someone holding a
            // real wallet balance in the same app deserves to be told which
            // number is which.
            Text(
              'Coins are for playing Ludo. They are not money, cannot be '
              'bought, and cannot be withdrawn — your PakBazar wallet is '
              'separate and untouched.',
              style: AppType.caption,
            ),
            const Divider(height: AppSpacing.xl),
            _RewardRow(
              icon: Icons.calendar_today_outlined,
              title: profile.canClaimDaily
                  ? 'Daily reward'
                  : 'Come back tomorrow',
              subtitle: profile.streak > 0
                  ? '${profile.streak} day streak — a longer streak pays more.'
                  : 'Play every day and the reward grows.',
              actionLabel: 'Claim',
              enabled: profile.canClaimDaily,
              onPressed: () {
                claimDailyCoins();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _RewardRow(
              icon: Icons.card_giftcard,
              title: profile.chests > 0
                  ? '${profile.chests} chest${profile.chests == 1 ? '' : 's'} ready'
                  : 'No chests yet',
              subtitle: profile.chests > 0
                  ? 'Open it — the contents are decided on the server.'
                  : 'Win ${profile.winsToNextChest} more '
                        'game${profile.winsToNextChest == 1 ? '' : 's'} '
                        'to earn a chest.',
              actionLabel: 'Open',
              enabled: profile.chests > 0,
              onPressed: () {
                openCoinChest();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${profile.gamesWon} won of ${profile.gamesPlayed} played',
              textAlign: TextAlign.center,
              style: AppType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: AppRadius.rMd,
      border: Border.all(color: AppColors.borderSoft),
    ),
    child: Row(
      children: [
        Icon(icon, color: enabled ? kPakGreen : AppColors.textMuted, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.label),
              const SizedBox(height: 2),
              Text(subtitle, style: AppType.caption),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: enabled ? onPressed : null,
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}
