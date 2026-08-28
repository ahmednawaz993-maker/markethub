part of '../main.dart';

// Voice chat for a Ludo table.
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
  rtc.RTCPeerConnection? pc;
  rtc.MediaStream? remoteStream;
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
  rtc.MediaStream? _localStream;
  StreamSubscription<QuerySnapshot>? _presenceSub;
  StreamSubscription<QuerySnapshot>? _signalSub;

  bool _joined = false;
  bool _micMuted = false;
  bool _busy = false;
  String? error;

  bool get joined => _joined;
  bool get micMuted => _micMuted;
  bool get busy => _busy;
  int get connectedCount =>
      peers.values.where((p) => p.state == VoicePeerState.connected).length;

  /// Opens the microphone and announces presence.
  Future<void> join() async {
    if (_joined || _busy) return;
    _busy = true;
    error = null;
    notifyListeners();
    try {
      // Audio only, with the processing that makes a speakerphone game usable:
      // without echo cancellation every player hears themselves back through
      // everyone else.
      _localStream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
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

  Future<rtc.RTCPeerConnection> _newConnection(String uid) async {
    final pc = await rtc.createPeerConnection({
      'iceServers': kVoiceIceServers,
      'sdpSemantics': 'unified-plan',
    });
    final local = _localStream;
    if (local != null) {
      for (final track in local.getAudioTracks()) {
        await pc.addTrack(track, local);
      }
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      unawaited(
        _send(uid, VoiceSignal.candidate, {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        }),
      );
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        peers[uid]?.remoteStream = event.streams.first;
        _applyMute(uid);
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      final peer = peers[uid];
      if (peer == null) return;
      peer.state = switch (s) {
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          VoicePeerState.connected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          VoicePeerState.failed,
        _ => VoicePeerState.connecting,
      };
      notifyListeners();
    };
    return pc;
  }

  Future<void> _dial(String uid) async {
    final peer = peers[uid];
    if (peer == null) return;
    final pc = await _newConnection(uid);
    peer.pc = pc;
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    await _send(uid, VoiceSignal.offer, {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    final from = d['from']?.toString() ?? '';
    final type = d['type']?.toString() ?? '';
    final payload = (d['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    if (from.isEmpty || from == myUid) return;

    var peer = peers[from];
    peer ??= peers[from] = VoicePeer(uid: from, name: 'Player');

    if (type == VoiceSignal.offer.name) {
      final pc = peer.pc ?? await _newConnection(from);
      peer.pc = pc;
      await pc.setRemoteDescription(
        rtc.RTCSessionDescription(payload['sdp'], payload['type']),
      );
      final answer = await pc.createAnswer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(answer);
      await _send(from, VoiceSignal.answer, {
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } else if (type == VoiceSignal.answer.name) {
      await peer.pc?.setRemoteDescription(
        rtc.RTCSessionDescription(payload['sdp'], payload['type']),
      );
    } else if (type == VoiceSignal.candidate.name) {
      await peer.pc?.addCandidate(
        rtc.RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          (payload['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
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
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      t.enabled = !_micMuted;
    }
    notifyListeners();
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
    if (peer == null) return;
    for (final t in peer.remoteStream?.getAudioTracks() ?? const []) {
      t.enabled = !peer.mutedByMe;
    }
  }

  void _dropPeer(String uid) {
    final peer = peers.remove(uid);
    unawaited(peer?.pc?.close().catchError((_) {}));
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
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
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
      return Padding(
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
      );
    },
  );
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
