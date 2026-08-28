// Voice chat.
//
// The peer connections themselves need real microphones and a real network, so
// what is pinned here is the piece that is pure and would be silently wrong:
// which side of a pair dials. Both peers see each other appear at the same
// instant, and if both decide to send an offer the negotiation collides and the
// call fails to establish — intermittently, and differently on each device,
// which is close to undebuggable in the field.
//
// The rest of the file covers the small stated facts that other code depends
// on: that STUN is configured, that TURN deliberately is not, and that the
// signal names are stable (they go on the wire between two app versions).
//
// One test here exists purely to guard a SIZE decision. Voice is web-only
// because the native WebRTC library cost 11.5 MB compressed on arm64-v8a —
// about a third of the app's whole native payload — and every Android user paid
// it, including the ones who only buy and sell. Re-adding that dependency would
// silently undo the decision, so the pubspec is asserted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';
// Imported directly, not through main.dart: this asserts what the MOBILE half
// of the conditional import says, which is the half Android compiles.
import 'package:markethub/voice_rtc_stub.dart';

void main() {
  group('exactly one side of a pair dials', () {
    test('the two peers never agree to both offer', () {
      expect(voiceShouldInitiate('aaa', 'bbb'), isTrue);
      expect(voiceShouldInitiate('bbb', 'aaa'), isFalse);
    });

    test('it is antisymmetric for every pair, so nobody collides', () {
      // The property that matters: for any two distinct uids, exactly one of
      // the two calls returns true.
      const uids = [
        'A1b2C3',
        'zzz',
        '000000000000000000000000000',
        'firebase-uid-9f8e7d',
        'Zebra',
        'aaaaaa',
      ];
      for (final a in uids) {
        for (final b in uids) {
          if (a == b) continue;
          final mine = voiceShouldInitiate(a, b);
          final theirs = voiceShouldInitiate(b, a);
          expect(
            mine != theirs,
            isTrue,
            reason: 'both or neither would dial for ($a, $b)',
          );
        }
      }
    });

    test('a peer never dials itself', () {
      // Would mean an offer sent to your own uid.
      expect(voiceShouldInitiate('same', 'same'), isFalse);
    });

    test('the decision is case sensitive but still total', () {
      // Firebase uids are mixed case; whatever the ordering, it must be
      // consistent rather than "correct".
      expect(
        voiceShouldInitiate('Alice', 'alice') !=
            voiceShouldInitiate('alice', 'Alice'),
        isTrue,
      );
    });
  });

  group('ICE configuration', () {
    test('STUN servers are configured', () {
      expect(kVoiceIceServers, isNotEmpty);
      final urls = kVoiceIceServers
          .expand((s) => (s['urls'] as List).cast<String>())
          .toList();
      expect(urls, isNotEmpty);
      expect(urls.every((u) => u.startsWith('stun:')), isTrue);
    });

    test('more than one STUN server, so one being down is not fatal', () {
      final urls = kVoiceIceServers
          .expand((s) => (s['urls'] as List).cast<String>())
          .toList();
      expect(urls.length, greaterThanOrEqualTo(2));
    });

    test('no TURN server is configured, and that is deliberate', () {
      // If a TURN entry is ever added, it will carry credentials — and this
      // test failing is the prompt to check they are not hardcoded in a client
      // binary, where anyone can read them and relay their own traffic.
      final urls = kVoiceIceServers
          .expand((s) => (s['urls'] as List).cast<String>())
          .toList();
      expect(
        urls.any((u) => u.startsWith('turn:')),
        isFalse,
        reason: 'adding TURN is a cost and a credentials decision',
      );
      for (final s in kVoiceIceServers) {
        expect(s.containsKey('credential'), isFalse);
        expect(s.containsKey('username'), isFalse);
      }
    });
  });

  group('the wire format is stable', () {
    test('signal names are the exact strings sent between devices', () {
      // These go into Firestore documents that a DIFFERENT app version reads.
      // Renaming the enum would break calls between an updated player and one
      // who has not updated yet.
      expect(VoiceSignal.offer.name, 'offer');
      expect(VoiceSignal.answer.name, 'answer');
      expect(VoiceSignal.candidate.name, 'candidate');
      expect(VoiceSignal.values.length, 3);
    });
  });

  group('voice stays off the Android download', () {
    test('no native WebRTC dependency is declared', () {
      // The browser already has WebRTC; linking a native copy put 11.5 MB into
      // every Android install for a feature most users never open.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('flutter_webrtc'),
        isFalse,
        reason: 'flutter_webrtc is back — that is 11.5 MB on every install',
      );
    });

    test('the app does not ask Android for microphone permission', () {
      // A marketplace app requesting RECORD_AUDIO has to justify it on the Play
      // data-safety form, and there is nothing on mobile that would use it.
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('RECORD_AUDIO'), isFalse);
    });

    test('the mobile stub reports itself unsupported', () {
      // Under the test VM the stub is what compiles, so this is the mobile
      // branch: join() must refuse rather than reach for a microphone.
      expect(voiceRtcSupported, isFalse);
    });
  });

  group('peer state', () {
    test('covers connecting, connected and failed', () {
      // 'failed' has to exist as a first-class state: with STUN only, some
      // players genuinely cannot connect, and the UI must say so rather than
      // spin forever.
      expect(VoicePeerState.values, hasLength(3));
      expect(VoicePeerState.values, contains(VoicePeerState.failed));
    });

    test('a new peer starts connecting and unmuted', () {
      final p = VoicePeer(uid: 'u1', name: 'Ali');
      expect(p.state, VoicePeerState.connecting);
      expect(p.mutedByMe, isFalse);
      expect(p.conn, isNull);
    });
  });
}
