part of '../main.dart';

// ---------------------------------------------------------------------------
// Invite Friends + Lucky Draw entry screen.
//
// Users spread the app link (native share sheet) to enter the 14 Aug 2026
// lucky draw — 5 winners × PKR 100,000. Each share bumps the user's
// participation count in luckyDrawEntries/{uid}; sharing with 5+ friends lists
// them as a "lucky person". Entry needs a registered (non-anonymous) account so
// winners can be contacted. All entry points that reach this screen are gated
// by luckyDrawActive(), so they vanish automatically on/after the draw date.
// ---------------------------------------------------------------------------

/// The message put in front of friends when the app link is shared.
String luckyDrawShareMessage() =>
    '🎉 Join PakBazar & win big!\n\n'
    'PakBazar is giving away PKR 100,000 each to 5 lucky winners on '
    '14 August 2026. Install the app, register, and share with your friends & '
    'businesses — the more you share, the more chances to win!\n\n'
    'Download now: $kAppShareLink';

/// Records one share against the current user's lucky-draw entry. Best-effort:
/// pulls the user's name/phone/email from their profile so the admin can
/// contact winners. `isWinner` is only ever set (to false) on first create —
/// never touched on later shares — so an admin-marked winner isn't overwritten
/// and the owner never self-sets the winner flag (enforced in firestore.rules).
Future<void> recordLuckyDrawShare() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('luckyDrawEntries').doc(uid);
    final existing = await ref.get();
    final u = (await db.collection('users').doc(uid).get()).data() ?? {};
    final data = <String, dynamic>{
      'uid': uid,
      'name': (u['name'] ?? u['displayName'] ?? '').toString(),
      'phone': (u['phone'] ?? '').toString(),
      'email': (u['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '')
          .toString(),
      'shareCount': FieldValue.increment(1),
      'lastSharedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['joinedAt'] = FieldValue.serverTimestamp();
      data['isWinner'] = false;
    }
    await ref.set(data, SetOptions(merge: true));
  } catch (_) {}
}

class InviteFriendsScreen extends StatelessWidget {
  const InviteFriendsScreen({super.key});

  static const int _targetShares = 5;

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: luckyDrawShareMessage(),
          subject: 'Join PakBazar & win PKR 100,000',
        ),
      );
      await recordLuckyDrawShare();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open share. Please try again.'),
        ),
      );
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: kAppShareLink));
    messenger.showSnackBar(
      const SnackBar(content: Text('Invite link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      appBar: AppBar(title: const Text('Invite & Win')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(),
          const SizedBox(height: 16),
          _howItWorks(),
          const SizedBox(height: 16),
          if (isGuest) _registerPrompt(context) else _entryStatus(user.uid),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.share),
            label: const Text('Share PakBazar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPakGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.link),
            label: const Text('Copy invite link'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No purchase necessary. Draw held on 14 August 2026; 5 winners are '
            'awarded PKR 100,000 each and contacted on their registered phone '
            'number. PakBazar\'s decision is final.',
            style: const TextStyle(
              fontSize: 11,
            ).copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _heroCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [kPakGreen, kPakGreenLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: kPakGreen.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      children: [
        const Text('🎉', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 6),
        const Text(
          'Win PKR 100,000',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '5 WINNERS · 14 AUGUST 2026',
            style: TextStyle(
              color: kPakGreenDeep,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'The more you share, the more chances to win!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    ),
  );

  Widget _howItWorks() => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'How to enter',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        SizedBox(height: 10),
        _Step(
          n: '1',
          icon: Icons.person_add_alt_1,
          text: 'Install PakBazar and register with your phone number.',
        ),
        _Step(
          n: '2',
          icon: Icons.share,
          text: 'Share the app with at least 5 friends or businesses.',
        ),
        _Step(
          n: '3',
          icon: Icons.emoji_events,
          text: 'Get listed as a lucky person — winners drawn on 14 Aug 2026.',
        ),
      ],
    ),
  );

  Widget _registerPrompt(BuildContext context) => SurfacePanel(
    child: Column(
      children: [
        const Icon(Icons.lock_person, color: kPakGreen, size: 30),
        const SizedBox(height: 8),
        const Text(
          'Register to enter the draw',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'You can share the app now, but you must register with your phone '
          'number to be eligible to win.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
          ).copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          ),
          child: const Text('Register / Sign in'),
        ),
      ],
    ),
  );

  Widget _entryStatus(String uid) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('luckyDrawEntries')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          final shares = (data?['shareCount'] as num?)?.toInt() ?? 0;
          final isWinner = data?['isWinner'] == true;
          final listed = shares >= _targetShares;
          final progress = (shares / _targetShares).clamp(0.0, 1.0);
          return SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      listed ? Icons.emoji_events : Icons.card_giftcard,
                      color: listed ? kGold : kPakGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isWinner
                            ? '🏆 You are a winner! We\'ll contact you.'
                            : listed
                            ? '🎯 You\'re listed in the lucky people!'
                            : shares > 0
                            ? 'You\'re entered — keep sharing!'
                            : 'Share to enter the lucky draw',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(
                      listed ? kGold : kPakGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Shared with $shares of $_targetShares',
                  style: const TextStyle(
                    fontSize: 12,
                  ).copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        },
      );
}

class _Step extends StatelessWidget {
  final String n;
  final IconData icon;
  final String text;
  const _Step({required this.n, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: kPakGreen,
          child: Text(
            n,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: kPakGreen),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
