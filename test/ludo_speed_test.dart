// How long a turn takes.
//
// Players called the game slow, and it was: measured against production, a roll
// cost 1634ms through the Firestore-trigger doorbell before a single pixel
// moved, then another ~890ms of animation on top. This file guards the half
// that lives in the client, because animation budgets creep back one
// "just a bit smoother" at a time and nobody notices until it is slow again.
//
// The numbers are ceilings, not targets. They exist so a future change has to
// argue with a failing test rather than quietly spend a player's time.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('the die is quick', () {
    test('a face change reads as a tumble, not a slideshow', () {
      expect(kLudoDiceTumbleFrame.inMilliseconds, lessThanOrEqualTo(80));
      expect(
        kLudoDiceTumbleFrame.inMilliseconds,
        greaterThanOrEqualTo(40),
        reason: 'faster than this is a blur, not a die',
      );
    });

    test('about six faces go by in a typical wait', () {
      // The measured warm round trip is roughly 400ms. The tumble should fill
      // it with movement rather than a frozen die.
      final faces = 400 ~/ kLudoDiceTumbleFrame.inMilliseconds;
      expect(faces, greaterThanOrEqualTo(5));
      expect(faces, lessThanOrEqualTo(9));
    });

    test('the settle is short, because the answer is already known', () {
      // Every millisecond here is spent after the number has arrived.
      expect(kLudoDiceSettle.inMilliseconds, lessThanOrEqualTo(150));
    });
  });

  group('the whole turn fits in a budget', () {
    test('a six walks in well under half a second', () {
      // The longest possible move: six squares, one at a time.
      final walk = LudoBoard.perStepDuration * 6;
      expect(
        walk.inMilliseconds,
        lessThanOrEqualTo(400),
        reason: 'a six taking ${walk.inMilliseconds}ms is the complaint',
      );
    });

    test('a step is still visible, not a teleport', () {
      expect(LudoBoard.perStepDuration.inMilliseconds, greaterThanOrEqualTo(35));
    });

    test('die plus the longest move stays under a second', () {
      // What a player actually experiences after the server answers: the die
      // lands, then the token walks.
      final total = kLudoDiceSettle + LudoBoard.perStepDuration * 6;
      expect(
        total.inMilliseconds,
        lessThanOrEqualTo(600),
        reason: 'post-answer animation is ${total.inMilliseconds}ms',
      );
    });

    test('a capture hop does not outlast the walk it replaces', () {
      expect(
        LudoBoard.hopDuration.inMilliseconds,
        lessThanOrEqualTo(LudoBoard.perStepDuration.inMilliseconds * 6),
      );
    });
  });

  group('sound keeps pace with the board', () {
    test('a footstep tick matches the step it belongs to', () {
      // A tick slower than the token arrives after it and reads as an echo.
      const player = GameSoundPlayer.walkStepDefault;
      expect(
        player.inMilliseconds,
        LudoBoard.perStepDuration.inMilliseconds,
        reason: 'sound and board have drifted apart',
      );
    });
  });
}
