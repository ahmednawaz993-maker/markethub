part of '../main.dart';

// Inviting people to a game.
//
// TWO WAYS IN, deliberately, because they cover different people:
//
//  * A LINK. Works for anyone, on any network — WhatsApp, Facebook, SMS, a
//    group chat. In Pakistan a WhatsApp group is how a game actually gets
//    filled, and a link needs no account, no permission dialog and no platform
//    to approve it.
//  * PEOPLE YOU FOLLOW. The app already has a follow graph, so "friends"
//    existed before any social login did. Tapping one sends them a
//    notification with the same link.
//
// Note on Facebook friends specifically: even with Facebook Login, Meta only
// returns friends who ALSO use this app and granted user_friends — the full
// friend list has been unavailable to every app since 2014. So a link that
// anyone can open is not a workaround, it is the better mechanism.

/// Opens an invite link: joins the room if there is a seat, then plays.
class LudoInviteScreen extends StatefulWidget {
  const LudoInviteScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<LudoInviteScreen> createState() => _LudoInviteScreenState();
}

class _LudoInviteScreenState extends State<LudoInviteScreen> {
  String? _error;
  bool _working = true;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() {
        _working = false;
        _error =
            'Sign in to join this game. Your invite still works once you have '
            'signed in — open the link again.';
      });
      return;
    }
    try {
      final snap = await _ludoCol().doc(widget.roomId).get();
      if (!snap.exists) {
        setState(() {
          _working = false;
          _error = 'That game has finished or was removed.';
        });
        return;
      }
      final room = LudoRoom.fromDoc(snap);
      // Already seated — a player reopening their own invite, which happens a
      // lot when a link gets forwarded back into the same group chat.
      if (room.colorOf(user.uid) == null) {
        var name = user.email?.split('@').first ?? 'Player';
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final n = (doc.data()?['name'] ?? '').toString().trim();
          if (n.isNotEmpty) name = n;
        } catch (_) {}
        final taken = await joinLudoRoom(widget.roomId, name);
        if (taken == null) {
          setState(() {
            _working = false;
            _error = room.isFull
                ? 'That game is already full.'
                : 'That game has already started.';
          });
          return;
        }
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LudoGameScreen(roomId: widget.roomId)),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Could not open that game: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ludo invite')),
    body: _working
        ? const Center(child: CircularProgressIndicator())
        : EmptyStateWidget(
            icon: Icons.casino_outlined,
            title: 'Cannot join',
            subtitle: _error ?? 'Something went wrong.',
            actionLabel: 'Browse games',
            onAction: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LudoLobbyScreen()),
            ),
          ),
  );
}

/// Notifies a followed player that they have been invited.
Future<void> inviteFriendToLudo({
  required String friendUid,
  required String roomId,
  required String fromName,
  required LudoMode mode,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(friendUid)
      .collection('notifications')
      .add({
        'title': '$fromName invited you to play Ludo',
        'body':
            'A ${mode.label} game is waiting. Tap to join before the seats '
            'fill up.',
        'type': 'ludo',
        'roomId': roomId,
        'link': ludoInviteUrl(roomId),
        'read': false,
        'createdAt': Timestamp.now(),
      });
}

/// The invite sheet: share a link, or tap someone you follow.
class LudoInviteSheet extends StatefulWidget {
  const LudoInviteSheet({super.key, required this.room});

  final LudoRoom room;

  @override
  State<LudoInviteSheet> createState() => _LudoInviteSheetState();
}

class _LudoInviteSheetState extends State<LudoInviteSheet> {
  final Set<String> _invited = {};
  String _myName = 'A friend';
  List<FacebookFriend> _fbFriends = const [];
  bool _fbLoading = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadFacebookFriends();
  }

  /// Only runs for a player who signed in with Facebook this session — the
  /// access token is held in memory and never persisted, so there is nothing
  /// to look friends up with otherwise.
  Future<void> _loadFacebookFriends() async {
    if (facebookAccessToken == null) return;
    setState(() => _fbLoading = true);
    final friends = await facebookFriendsOnPakBazar();
    if (mounted) {
      setState(() {
        _fbFriends = friends;
        _fbLoading = false;
      });
    }
  }

  Future<void> _loadName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final n = (doc.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty && mounted) setState(() => _myName = n);
    } catch (_) {}
  }

  String get _link => ludoInviteUrl(widget.room.id);

  /// Marks optimistically and rolls back on failure, so a tap always responds
  /// but never lies about having sent something.
  Future<void> _invite(String uid) async {
    setState(() => _invited.add(uid));
    try {
      await inviteFriendToLudo(
        friendUid: uid,
        roomId: widget.room.id,
        fromName: _myName,
        mode: widget.room.game.mode,
      );
    } catch (_) {
      if (mounted) setState(() => _invited.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite players', style: AppType.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${widget.room.seats.length} of 4 seats taken · '
                  '${widget.room.game.mode.label}',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share invite'),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text:
                            '$_myName is starting a '
                            '${widget.room.game.mode.label} Ludo game on '
                            'PakBazar. Join me:\n$_link',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite link copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          if (facebookAccessToken != null) ...[
            const Divider(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('Facebook friends here', style: AppType.label),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_fbLoading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_fbFriends.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                // Said plainly, because the alternative is a player concluding
                // the feature is broken. Facebook only ever discloses friends
                // who use this same app — it has not returned a full friend
                // list to anyone since 2014.
                child: Text(
                  'None of your Facebook friends are on PakBazar yet. Facebook '
                  'only shows friends who already use this app, so share the '
                  'link above to reach the rest.',
                  style: AppType.secondary,
                ),
              )
            else
              for (final f in _fbFriends)
                _InviteRow(
                  name: f.name,
                  avatarColor: FacebookSignInButton.brandBlue,
                  playing: widget.room.seats.containsValue(f.uid),
                  sent: _invited.contains(f.uid),
                  onInvite: () => _invite(f.uid),
                ),
          ],
          const Divider(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('People you follow', style: AppType.label),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('following')
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Text(
                      'You are not following anyone yet. Share the link above '
                      'instead — it works in WhatsApp, Facebook or anywhere '
                      'else, and whoever opens it lands straight in this game.',
                      style: AppType.secondary,
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final fid = docs[i].id;
                    final name =
                        (d['name'] ?? d['sellerName'] ?? 'Player').toString();
                    return _InviteRow(
                      name: name,
                      avatarColor: kPakGreen,
                      playing: widget.room.seats.containsValue(fid),
                      sent: _invited.contains(fid),
                      onInvite: () => _invite(fid),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One invitable person: avatar, name, and a button that becomes a state.
///
/// Shared by both lists so a Facebook friend and a followed seller look and
/// behave identically — the source of the name should not change the row.
class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.name,
    required this.avatarColor,
    required this.playing,
    required this.sent,
    required this.onInvite,
  });

  final String name;
  final Color avatarColor;
  final bool playing;
  final bool sent;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: CircleAvatar(
      radius: 16,
      backgroundColor: avatarColor.withValues(alpha: 0.12),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700),
      ),
    ),
    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: playing
        ? Text('Playing', style: AppType.caption)
        : TextButton(
            onPressed: sent ? null : onInvite,
            child: Text(sent ? 'Invited' : 'Invite'),
          ),
  );
}
