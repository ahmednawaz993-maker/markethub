part of '../main.dart';

// Weekly Ludo standings.
//
// PER WEEK, not all-time. An all-time board stops being a competition almost
// immediately: whoever started first is permanently ahead, and everybody who
// joins later is looking at a list they can never enter. A week is short enough
// that a good run this evening puts you on it.
//
// Written only by the server. Every row here is a side effect of a finished
// game, so there is nothing a client could legitimately post.

/// Stakes a table can be opened at. Must match STAKE_TIERS in game_economy.js.
const List<int> kLudoStakeTiers = [0, 100, 500, 2000, 10000];

/// One row of the weekly table.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.name,
    required this.coinsWon,
    required this.wins,
    required this.games,
  });

  final String userId;
  final String name;
  final int coinsWon;
  final int wins;
  final int games;

  static LeaderboardEntry fromMap(String id, Map<String, dynamic>? d) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return LeaderboardEntry(
      userId: (d?['userId'] ?? id).toString(),
      name: (d?['name'] ?? 'Player').toString(),
      coinsWon: asInt(d?['coinsWon']),
      wins: asInt(d?['wins']),
      games: asInt(d?['games']),
    );
  }
}

/// The Pakistan week a moment falls in, as "YYYY-Www".
///
/// Mirrors weekIdOf in game_economy.js, and must agree with it: the server
/// writes rows under its week id and this reads them back under ours. A week
/// runs Monday to Sunday in PKT — Sunday night is when people play, and a UTC
/// week would roll over at 5am Monday and cut it off.
String ludoWeekId(DateTime when) {
  int pktDay(int ms) =>
      (ms + const Duration(hours: 5).inMilliseconds) ~/
      Duration.millisecondsPerDay;
  int mod7(int n) => ((n % 7) + 7) % 7;

  final day = pktDay(when.millisecondsSinceEpoch);
  // Epoch day 0 was a Thursday, so a Monday is any day where day % 7 == 4.
  final monday = day - mod7(day - 4);

  int weekNumber(int mondayDay, int year) {
    final jan1 =
        DateTime.utc(year).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    return ((mondayDay - (jan1 + mod7(4 - jan1))) ~/ 7) + 1;
  }

  final y = DateTime.fromMillisecondsSinceEpoch(
    monday * Duration.millisecondsPerDay,
    isUtc: true,
  ).year;
  final n = weekNumber(monday, y);
  // A Monday before its own year's first Monday belongs to the previous year.
  return n >= 1
      ? '$y-W${n.toString().padLeft(2, '0')}'
      : '${y - 1}-W${weekNumber(monday, y - 1).toString().padLeft(2, '0')}';
}

/// This week's top players.
class LudoLeaderboardScreen extends StatelessWidget {
  const LudoLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final week = ludoWeekId(DateTime.now());
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('This week')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('leaderboards')
            .doc(week)
            .collection('players')
            .orderBy('coinsWon', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyStateWidget(
              icon: Icons.leaderboard_outlined,
              title: 'Could not load the table',
              subtitle: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = [
            for (final d in snap.data!.docs)
              LeaderboardEntry.fromMap(d.id, d.data() as Map<String, dynamic>?),
          ];
          if (rows.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.leaderboard_outlined,
              title: 'Nobody has played yet this week',
              subtitle:
                  'The table resets every Monday. Win a game and you are on it.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final isMe = r.userId == me;
              return Container(
                // Your own row is tinted, because the first thing anybody looks
                // for on a leaderboard is themselves.
                color: isMe ? kPakGreen.withValues(alpha: 0.07) : null,
                child: ListTile(
                  leading: _Rank(place: i + 1),
                  title: Text(
                    isMe ? '${r.name} (you)' : r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(
                      fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${r.wins} won of ${r.games} played',
                    style: AppType.caption,
                  ),
                  trailing: CoinPill(coins: r.coinsWon),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A place number, with medals for the top three.
class _Rank extends StatelessWidget {
  const _Rank({required this.place});
  final int place;

  @override
  Widget build(BuildContext context) {
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    final medal = medals[place];
    return SizedBox(
      width: 34,
      child: medal != null
          ? Text(medal, style: const TextStyle(fontSize: 20))
          : Text(
              '$place',
              textAlign: TextAlign.center,
              style: AppType.label.copyWith(
                color: AppColors.textMuted,
                // Tabular so the column of numbers stays aligned.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}
