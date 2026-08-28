// Voice chat: the web half of a conditional import.
//
// Uses the browser's own WebRTC through package:web, which is generated from
// the Web IDL — so there is no native library, nothing to link, and no download
// cost. The same feature via flutter_webrtc cost 11.5 MB compressed on
// arm64-v8a and was paid by every Android user whether or not they ever opened
// Ludo.
//
// This file is compiled ONLY for the web. voice_rtc_stub.dart is what Android
// and iOS build, and the two must keep the same public names and signatures —
// a conditional import picks one, and a mismatch is a compile error on the
// platform you were not looking at.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool voiceRtcSupported = true;

const String kVoiceWebUrl = 'https://pakbazar24.com';

/// The local microphone.
class VoiceMic {
  VoiceMic(this.stream);

  final web.MediaStream stream;

  /// Disables the TRACK rather than stopping the stream: stopping would release
  /// the device, and unmuting would then re-prompt for permission in some
  /// browsers. Disabling is instant and silent.
  void setEnabled(bool enabled) {
    final tracks = stream.getAudioTracks().toDart;
    for (final t in tracks) {
      t.enabled = enabled;
    }
  }

  void stop() {
    for (final t in stream.getAudioTracks().toDart) {
      t.stop();
    }
  }
}

/// One peer connection, plus the <audio> element that actually plays it.
class VoiceConn {
  VoiceConn(this._pc) {
    _pc.onicecandidate = ((web.RTCPeerConnectionIceEvent e) {
      final c = e.candidate;
      if (c == null) return;
      onIceCandidate?.call({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    }).toJS;

    _pc.ontrack = ((web.RTCTrackEvent e) {
      final streams = e.streams.toDart;
      if (streams.isEmpty) return;
      _attach(streams.first);
      onRemoteAudio?.call();
    }).toJS;

    _pc.onconnectionstatechange = ((web.Event _) {
      onStateChange?.call(_pc.connectionState);
    }).toJS;
  }

  final web.RTCPeerConnection _pc;

  /// Remote audio needs a real media element to be heard — a track arriving on
  /// a peer connection is silent until something plays it. The element is kept
  /// out of the layout and off the accessibility tree; it exists only to make
  /// sound.
  web.HTMLAudioElement? _audio;

  void Function(Map<String, dynamic> candidate)? onIceCandidate;
  void Function()? onRemoteAudio;
  void Function(String state)? onStateChange;

  void _attach(web.MediaStream stream) {
    final el = _audio ??= (web.document.createElement('audio')
        as web.HTMLAudioElement)
      ..autoplay = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('aria-hidden', 'true')
      ..style.display = 'none';
    el.srcObject = stream;
    if (el.parentNode == null) web.document.body?.appendChild(el);
    // Autoplay can still be refused until the page has had a gesture. Joining
    // voice IS a tap, so this normally succeeds; if it does not there is
    // nothing useful to tell the user beyond the connection state.
    el.play().toDart.catchError((Object _) => null);
  }

  Future<void> addLocalAudio(VoiceMic mic) async {
    for (final t in mic.stream.getAudioTracks().toDart) {
      _pc.addTrack(t, mic.stream);
    }
  }

  Future<Map<String, dynamic>> createOffer() async {
    final d = await _pc.createOffer().toDart;
    return {'sdp': d?.sdp ?? '', 'type': d?.type ?? 'offer'};
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final d = await _pc.createAnswer().toDart;
    return {'sdp': d?.sdp ?? '', 'type': d?.type ?? 'answer'};
  }

  // setLocalDescription and setRemoteDescription take DIFFERENT IDL types —
  // RTCLocalSessionDescriptionInit and RTCSessionDescriptionInit. They carry
  // the same two fields; the distinction exists so a local description may be
  // set with no argument at all, which is the modern rollback form.
  Future<void> setLocalDescription(Map<String, dynamic> sdp) async {
    await _pc
        .setLocalDescription(
          web.RTCLocalSessionDescriptionInit(
            type: (sdp['type'] ?? 'offer').toString(),
            sdp: (sdp['sdp'] ?? '').toString(),
          ),
        )
        .toDart;
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    await _pc
        .setRemoteDescription(
          web.RTCSessionDescriptionInit(
            type: (sdp['type'] ?? 'offer').toString(),
            sdp: (sdp['sdp'] ?? '').toString(),
          ),
        )
        .toDart;
  }

  Future<void> addIceCandidate(Map<String, dynamic> c) async {
    await _pc
        .addIceCandidate(
          web.RTCIceCandidateInit(
            candidate: (c['candidate'] ?? '').toString(),
            sdpMid: c['sdpMid']?.toString(),
            sdpMLineIndex: (c['sdpMLineIndex'] as num?)?.toInt(),
          ),
        )
        .toDart;
  }

  /// Mutes this peer for me only. Muting the ELEMENT rather than the track,
  /// because the track belongs to the sender and disabling it here would be
  /// undone by the next renegotiation.
  void setRemoteMuted(bool muted) => _audio?.muted = muted;

  Future<void> close() async {
    _audio?.srcObject = null;
    _audio?.remove();
    _audio = null;
    _pc.close();
  }
}

Future<VoiceMic> voiceOpenMic() async {
  // Audio only, with the processing that makes a speakerphone game usable:
  // without echo cancellation every player hears themselves back through
  // everyone else.
  final stream = await web.window.navigator.mediaDevices
      .getUserMedia(
        web.MediaStreamConstraints(
          audio: {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          }.jsify()!,
          video: false.toJS,
        ),
      )
      .toDart;
  return VoiceMic(stream);
}

VoiceConn voiceCreateConnection(List<Map<String, dynamic>> iceServers) {
  final config = web.RTCConfiguration(
    iceServers: iceServers
        .map(
          (s) => web.RTCIceServer(
            urls: (s['urls'] as List).map((u) => u.toString()).toList().jsify()!,
          ),
        )
        .toList()
        .toJS,
  );
  return VoiceConn(web.RTCPeerConnection(config));
}
