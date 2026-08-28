// Voice chat: the non-web half of a conditional import.
//
// Voice runs in the browser only, using the WebRTC the browser already has.
// The native alternative (flutter_webrtc) linked libjingle_peerconnection into
// the Android build — 11.5 MB compressed on arm64-v8a, roughly a third of the
// app's entire native payload, paid by every user including the ones who only
// buy and sell and will never open Ludo. On the web the same feature costs
// nothing extra.
//
// So on mobile these are no-ops that report themselves unsupported, and the UI
// points players at the website instead. This file must import nothing
// web-specific: it is what Android and iOS actually compile.

/// Whether this platform can run voice chat at all.
const bool voiceRtcSupported = false;

/// Where a player is told to go instead.
const String kVoiceWebUrl = 'https://pakbazar24.com';

/// True when this platform can also send video. Video rides the same peer
/// connection as voice, so it is web-only for the same reason.
const bool voiceVideoSupported = false;

/// The local microphone, and optionally the camera. Never constructed on
/// mobile.
class VoiceMic {
  /// Mutes or unmutes without releasing the device, so unmuting is instant and
  /// does not re-prompt for permission.
  void setEnabled(bool enabled) {}

  /// Turns the camera on or off mid-call. Separate from the microphone: people
  /// join voice far more readily than video, and one should never imply the
  /// other.
  Future<bool> setCamera(bool on) async => false;

  bool get hasCamera => false;

  /// The outgoing camera track, or null when the camera is off.
  Object? get cameraTrack => null;

  void stop() {}
}

/// One peer connection. Never constructed on mobile.
class VoiceConn {
  void Function(Map<String, dynamic> candidate)? onIceCandidate;
  void Function()? onRemoteAudio;
  void Function()? onRemoteVideo;
  void Function(String state)? onStateChange;

  Future<void> addLocalAudio(VoiceMic mic) async {}
  Future<Map<String, dynamic>> createOffer() async => const {};
  Future<Map<String, dynamic>> createAnswer() async => const {};
  Future<void> setLocalDescription(Map<String, dynamic> sdp) async {}
  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {}
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {}

  /// Mutes this peer for me only.
  void setRemoteMuted(bool muted) {}

  /// A platform view id showing this peer's video, or null when there is none.
  String? get videoViewType => null;

  /// True once a remote video track has actually arrived.
  bool get hasVideo => false;

  /// Adds or replaces the outgoing camera track. Returns true when the change
  /// needs a fresh offer.
  Future<bool> setLocalVideo(Object? track, VoiceMic mic) async => false;

  Future<void> close() async {}
}

Future<VoiceMic> voiceOpenMic() =>
    throw UnsupportedError('Voice chat is only available on the website.');

VoiceConn voiceCreateConnection(List<Map<String, dynamic>> iceServers) =>
    throw UnsupportedError('Voice chat is only available on the website.');
