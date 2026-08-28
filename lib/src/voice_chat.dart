part of '../main.dart';

// Voice chat for a Ludo table.
//
// WEB ONLY. The browser already has WebRTC, so voice costs nothing extra
// there. The native alternative linked libjingle_peerconnection into the
// Android build: 11.5 MB compressed on arm64-v8a, about a third of the app's
// whole native payload, paid by every user including the ones who only buy and
// sell and will never open Ludo. On mobile the RTC calls resolve to a stub and
// the UI points players at the website; the game itself is unaffected.
//
// PEER TO PEER, no media server. Four players is three connections each — a
// mesh that small is exactly what WebRTC is for, and it means no Agora or
// LiveKit bill and no audio passing through any server we run. Firestore is
// used only for signalling: offers, answers and ICE candidates, which are a few
// hundred bytes each and are deleted the moment they are consumed.
//
// WHAT THIS DOES NOT DO, stated plainly rather than discovered later:
//
//  * NO TURN RELAY. The ICE servers below are public STUN only. STUN gets a
//    peer through most home and mobile NATs; it does not get through a
//    symmetric NAT, which some carrier-grade networks use. Those players will
//    connect to everyone they can and silently fail to connect to the rest.
//    Fixing that needs a TURN server, which costs money because it relays the
//    audio itself. The UI says "could not connect" rather than pretending.
//  * NO RECORDING and no server-side moderation, because the audio never
//    reaches a server we control. Moderation is therefore local: anyone can be
//    muted by anyone, instantly.
//
// VIDEO IS A SEPARATE OPT-IN. Joining voice never turns a camera on: people
// will talk from anywhere, and be on camera in far fewer places. The two
// controls are independent, video rides the same peer connection as voice, and
// the outgoing stream is deliberately small (320x240 at 15fps) because in a
// four-player mesh every camera is sent three times over what is usually a
// mobile connection.
//
// OFF BY DEFAULT, like game sound. A marketplace app that opens a microphone
// without being asked is uninstalled, and rightly. Nothing here runs until a
// player taps to join, and the game is completely playable without it.

/// Public STUN. Free, and enough for most players — see the TURN note above.
const List<Map<String, dynamic>> kVoiceIceServers = [
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
];

/// Which side of a pair creates the offer.
///
/// Both peers see each other appear at the same moment, so without a rule both
/// would send an offer and the negotiation would collide ("glare"). Comparing
/// the two uids gives every pair the same answer on both devices without any
/// extra round trip. Deterministic and pure, which is why it is testable.
bool voiceShouldInitiate(String myUid, String theirUid) =>
    myUid.compareTo(theirUid) < 0;

/// A signalling message on the wire.
enum VoiceSignal { offer, answer, candidate }

/// Connection state of one remote player, as far as this device is concerned.
enum VoicePeerState { connecting, connected, failed }

CollectionReference<Map<String, dynamic>> _voiceCol(String roomId) =>
    FirebaseFirestore.instance
        .collection(_kLudoRooms)
        .doc(roomId)
        .collection('voice');

CollectionReference<Map<String, dynamic>> _signalCol(String roomId) =>
    FirebaseFirestore.instance
        .collection(_kLudoRooms)
        .doc(roomId)
        .collection('voiceSignals');

/// One remote participant.
class VoicePeer {
  VoicePeer({required this.uid, required this.name});

  final String uid;
  final String name;
  VoiceConn? conn;
  VoicePeerState state = VoicePeerState.connecting;

  /// Muted by ME, locally. The only moderation available when audio never
  /// touches a server — and the fastest, since it needs nobody's agreement.
  bool mutedByMe = false;
}

/// Runs one player's side of a table's voice chat.
///
/// A ChangeNotifier rather than a widget so the connection survives a rebuild:
/// tearing down peer connections every time the board repaints would make voice
/// unusable.
class VoiceSession extends ChangeNotifier {
  VoiceSession({required this.roomId, required this.myUid, required this.myName});

  final String roomId;
  final String myUid;
  final String myName;

  final Map<String, VoicePeer> peers = {};
  VoiceMic? _mic;
  StreamSubscription<QuerySnapshot>? _presenceSub;
  StreamSubscription<QuerySnapshot>? _signalSub;

  bool _joined = false;
  bool _micMuted = false;
  bool _cameraOn = false;
  bool _busy = false;
  String? error;

  bool get joined => _joined;
  bool get micMuted => _micMuted;
  bool get cameraOn => _cameraOn;
  bool get videoSupported => voiceVideoSupported;
  bool get busy => _busy;
  int get connectedCount =>
      peers.values.where((p) => p.state == VoicePeerState.connected).length;

  /// Opens the microphone and announces presence.
  Future<void> join() async {
    if (_joined || _busy) return;
    if (!voiceRtcSupported) {
      // Not an error the player caused, so it reads as a signpost rather than
      // a failure.
      error = 'Voice chat works on the PakBazar website. Open this game at '
          'pakbazar24.com to talk — keeping it off the app saves every user a '
          '11 MB download.';
      notifyListeners();
      return;
    }
    _busy = true;
    error = null;
    notifyListeners();
    try {
      _mic = await voiceOpenMic();
      await _voiceCol(roomId).doc(myUid).set({
        'uid': myUid,
        'name': myName,
        'joinedAt': Timestamp.now(),
      });
      _listen();
      _joined = true;
    } catch (e) {
      // Permission refused, no microphone, or a browser that will not grant it
      // outside a user gesture. None of these should break the game.
      error = _friendlyMicError(e);
      await _teardown();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _friendlyMicError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('notallowed') || s.contains('permission')) {
      return 'Microphone permission was refused. Allow it in your settings to '
          'talk — you can still play without it.';
    }
    if (s.contains('notfound') || s.contains('devicenotfound')) {
      return 'No microphone found on this device.';
    }
    return 'Could not start voice chat. You can still play without it.';
  }

  void _listen() {
    // Who else is here.
    _presenceSub = _voiceCol(roomId).snapshots().listen((snap) {
      final present = <String>{};
      for (final d in snap.docs) {
        final uid = d.data()['uid']?.toString() ?? d.id;
        if (uid == myUid) continue;
        present.add(uid);
        if (!peers.containsKey(uid)) {
          final name = d.data()['name']?.toString() ?? 'Player';
          peers[uid] = VoicePeer(uid: uid, name: name);
          // Only one side dials, or the two offers collide.
          if (voiceShouldInitiate(myUid, uid)) {
            unawaited(_dial(uid));
          }
        }
      }
      // Anyone who left.
      for (final uid in peers.keys.toList()) {
        if (!present.contains(uid)) _dropPeer(uid);
      }
      notifyListeners();
    });

    // Messages addressed to me.
    _signalSub = _signalCol(roomId)
        .where('to', isEqualTo: myUid)
        .snapshots()
        .listen((snap) async {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final d = change.doc.data();
            if (d == null) continue;
            try {
              await _handleSignal(d);
            } catch (_) {
              // A malformed or out-of-order signal must not kill the session.
            }
            // Consumed: delete it so the collection cannot grow without bound
            // and so a reconnect does not replay stale negotiation.
            unawaited(change.doc.reference.delete().catchError((_) {}));
          }
        });
  }

  Future<VoiceConn> _newConnection(String uid) async {
    final conn = voiceCreateConnection(kVoiceIceServers);
    final mic = _mic;
    if (mic != null) await conn.addLocalAudio(mic);

    conn.onIceCandidate = (c) => unawaited(
      _send(uid, VoiceSignal.candidate, c),
    );
    conn.onRemoteAudio = () {
      // Apply any mute the player had already set before this peer connected.
      _applyMute(uid);
      notifyListeners();
    };
    conn.onRemoteVideo = notifyListeners;
    conn.onStateChange = (state) {
      final peer = peers[uid];
      if (peer == null) return;
      // The browser's own connectionState strings, mapped onto the three
      // states the UI distinguishes.
      peer.state = switch (state) {
        'connected' => VoicePeerState.connected,
        'failed' || 'closed' || 'disconnected' => VoicePeerState.failed,
        _ => VoicePeerState.connecting,
      };
      notifyListeners();
    };
    return conn;
  }

  Future<void> _dial(String uid) async {
    final peer = peers[uid];
    if (peer == null) return;
    final conn = await _newConnection(uid);
    peer.conn = conn;
    final offer = await conn.createOffer();
    await conn.setLocalDescription(offer);
    await _send(uid, VoiceSignal.offer, offer);
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    final from = d['from']?.toString() ?? '';
    final type = d['type']?.toString() ?? '';
    final payload = (d['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    if (from.isEmpty || from == myUid) return;

    var peer = peers[from];
    peer ??= peers[from] = VoicePeer(uid: from, name: 'Player');

    if (type == VoiceSignal.offer.name) {
      final conn = peer.conn ?? await _newConnection(from);
      peer.conn = conn;
      await conn.setRemoteDescription(payload);
      final answer = await conn.createAnswer();
      await conn.setLocalDescription(answer);
      await _send(from, VoiceSignal.answer, answer);
    } else if (type == VoiceSignal.answer.name) {
      await peer.conn?.setRemoteDescription(payload);
    } else if (type == VoiceSignal.candidate.name) {
      await peer.conn?.addIceCandidate(payload);
    }
  }

  Future<void> _send(String to, VoiceSignal type, Map<String, dynamic> p) =>
      _signalCol(roomId).add({
        'from': myUid,
        'to': to,
        'type': type.name,
        'payload': p,
        'at': Timestamp.now(),
      });

  /// Mutes my own microphone. The track is disabled rather than the stream
  /// stopped, so unmuting is instant and does not re-prompt for permission.
  void toggleMic() {
    _micMuted = !_micMuted;
    _mic?.setEnabled(!_micMuted);
    notifyListeners();
  }

  /// Turns my camera on or off.
  ///
  /// Adding a video track to an existing call needs a fresh offer, because a
  /// new track means a new m-line in the SDP. Replacing or removing one does
  /// not — there is already a sender for it — so this only redials when it has
  /// to, and never interrupts the audio.
  Future<void> toggleCamera() async {
    final mic = _mic;
    if (mic == null || !voiceVideoSupported) return;
    _busy = true;
    notifyListeners();
    try {
      final on = await mic.setCamera(!_cameraOn);
      _cameraOn = on;
      final track = on ? mic.cameraTrack : null;
      for (final entry in peers.entries) {
        final conn = entry.value.conn;
        if (conn == null) continue;
        final needsOffer = await conn.setLocalVideo(track, mic);
        // Only the dialling side may renegotiate, for the same reason only one
        // side opens the call: two simultaneous offers collide.
        if (needsOffer && voiceShouldInitiate(myUid, entry.key)) {
          final offer = await conn.createOffer();
          await conn.setLocalDescription(offer);
          await _send(entry.key, VoiceSignal.offer, offer);
        }
      }
    } catch (_) {
      // A camera that will not open must not end the call.
      _cameraOn = false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Mutes one other player, for me only.
  void toggleMutePeer(String uid) {
    final peer = peers[uid];
    if (peer == null) return;
    peer.mutedByMe = !peer.mutedByMe;
    _applyMute(uid);
    notifyListeners();
  }

  void _applyMute(String uid) {
    final peer = peers[uid];
    peer?.conn?.setRemoteMuted(peer.mutedByMe);
  }

  void _dropPeer(String uid) {
    final peer = peers.remove(uid);
    unawaited(peer?.conn?.close().catchError((_) {}));
  }

  Future<void> leave() async {
    await _teardown();
    _joined = false;
    notifyListeners();
  }

  Future<void> _teardown() async {
    await _presenceSub?.cancel();
    await _signalSub?.cancel();
    _presenceSub = null;
    _signalSub = null;
    for (final uid in peers.keys.toList()) {
      _dropPeer(uid);
    }
    _mic?.stop();
    _mic = null;
    _cameraOn = false;
    // Best-effort: leave no ghost in the room list if the app is closing.
    await _voiceCol(roomId).doc(myUid).delete().catchError((_) {});
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}

/// The microphone control and participant list for the game screen.
class VoiceChatBar extends StatelessWidget {
  const VoiceChatBar({super.key, required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (!session.joined) {
        // On mobile there is no microphone path at all, so the control says
        // where voice lives instead of offering a button that cannot work.
        if (!voiceRtcSupported) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.headset_mic_outlined,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Voice chat is on pakbazar24.com — the app stays smaller '
                    'without it.',
                    style: AppType.caption,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: session.busy ? null : session.join,
                icon: session.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic_none, size: 18),
                label: Text(session.busy ? 'Connecting…' : 'Join voice chat'),
              ),
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    session.error!,
                    style: AppType.caption.copyWith(color: AppColors.error),
                  ),
                ),
            ],
          ),
        );
      }
      final withVideo = [
        for (final p in session.peers.values)
          if (p.conn?.hasVideo == true && !p.mutedByMe) p,
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Faces only appear when somebody actually turns a camera on, so a
          // voice-only table loses no board space to empty tiles.
          if (withVideo.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: withVideo.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) =>
                    _VideoTile(peer: withVideo[i]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
            IconButton(
              tooltip: session.micMuted ? 'Unmute me' : 'Mute me',
              onPressed: session.toggleMic,
              icon: Icon(
                session.micMuted ? Icons.mic_off : Icons.mic,
                color: session.micMuted ? AppColors.error : kPakGreen,
              ),
            ),
            if (session.videoSupported)
              IconButton(
                tooltip: session.cameraOn ? 'Turn camera off' : 'Turn camera on',
                onPressed: session.busy ? null : session.toggleCamera,
                icon: Icon(
                  session.cameraOn ? Icons.videocam : Icons.videocam_off,
                  color: session.cameraOn ? kPakGreen : AppColors.textMuted,
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in session.peers.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: _PeerChip(
                          peer: p,
                          onTap: () => session.toggleMutePeer(p.uid),
                        ),
                      ),
                    if (session.peers.isEmpty)
                      Text('Waiting for others…', style: AppType.caption),
                  ],
                ),
              ),
            ),
            TextButton(onPressed: session.leave, child: const Text('Leave')),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// One player's camera, with their name over it.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.peer});

  final VoicePeer peer;

  @override
  Widget build(BuildContext context) {
    final type = peer.conn?.videoViewType;
    if (type == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: AppRadius.rMd,
      child: SizedBox(
        width: 112,
        height: 84,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.surfaceVariant,
              // The <video> element itself, handed to Flutter as a platform
              // view — a canvas-rendered app cannot draw a DOM video any other
              // way.
              child: HtmlElementView(viewType: type),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                color: Colors.black.withValues(alpha: 0.45),
                child: Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerChip extends StatelessWidget {
  const _PeerChip({required this.peer, required this.onTap});

  final VoicePeer peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color colour, IconData icon, String label) = switch (peer.state) {
      VoicePeerState.connected => peer.mutedByMe
          ? (AppColors.textMuted, Icons.volume_off, 'muted')
          : (kPakGreen, Icons.volume_up, ''),
      VoicePeerState.connecting => (AppColors.textMuted, Icons.more_horiz, '…'),
      // Almost always a NAT that STUN alone cannot traverse. Said as a fact
      // about the connection rather than blaming the other player.
      VoicePeerState.failed => (AppColors.error, Icons.link_off, 'no link'),
    };
    return InkWell(
      onTap: peer.state == VoicePeerState.connected ? onTap : null,
      borderRadius: AppRadius.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: AppRadius.rLg,
          border: Border.all(color: colour.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                label.isEmpty ? peer.name : '${peer.name} · $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
