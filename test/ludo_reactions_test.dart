// Emoji reactions and gifts.
//
// The parts worth pinning are the ones that decide what a player SEES: whether
// a reaction is still live, whether it reads as a gift or a shout, and the
// rate limit that stops one bored player drowning the table. The Firestore
// write itself needs a live backend, so it is not covered here.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoReaction react({
  required int secondsAgo,
  String emoji = '😂',
  String from = 'Ali',
  String to = '',
}) => LudoReaction.fromMap('id', {
  'userId': 'u1',
  'emoji': emoji,
  'fromName': from,
  'toName': to,
  'at': Timestamp.fromDate(
    DateTime.now().subtract(Duration(seconds: secondsAgo)),
  ),
});

void main() {
  group('a reaction is ephemeral', () {
    test('a fresh one is live', () {
      expect(react(secondsAgo: 0).isLive(DateTime.now()), isTrue);
    });

    test('one older than its life is not', () {
      expect(
        react(secondsAgo: kLudoReactionLife.inSeconds + 2)
            .isLive(DateTime.now()),
        isFalse,
      );
    });

    test('it lasts long enough to read, and not so long it piles up', () {
      expect(kLudoReactionLife.inSeconds, greaterThanOrEqualTo(3));
      expect(kLudoReactionLife.inSeconds, lessThanOrEqualTo(8));
    });
  });

  group('gift vs shout', () {
    test('a reaction with no target is thrown at the table', () {
      expect(react(secondsAgo: 0).isGift, isFalse);
    });

    test('a reaction with a target is a gift', () {
      expect(react(secondsAgo: 0, to: 'Sara').isGift, isTrue);
    });
  });

  group('the palette', () {
    test('is short enough to be faster than typing', () {
      // A grid of sixty emoji is a menu to navigate; the point is one tap.
      expect(kLudoEmojis.length, lessThanOrEqualTo(10));
      expect(kLudoEmojis, isNotEmpty);
    });

    test('has no duplicates', () {
      expect(kLudoEmojis.toSet().length, kLudoEmojis.length);
    });

    test('every gift has an emoji and a label', () {
      for (final g in LudoGift.values) {
        expect(g.emoji, isNotEmpty, reason: g.name);
        expect(g.label, isNotEmpty, reason: g.name);
      }
      expect(
        LudoGift.values.map((g) => g.emoji).toSet().length,
        LudoGift.values.length,
        reason: 'two gifts share an emoji, so they are indistinguishable',
      );
    });
  });

  group('rate limiting', () {
    test('the cooldown is short enough to feel instant, long enough to work',
        () {
      expect(kLudoReactionCooldown.inMilliseconds, greaterThanOrEqualTo(500));
      expect(kLudoReactionCooldown.inMilliseconds, lessThanOrEqualTo(3000));
    });

    test('a reaction cannot outlive several cooldowns worth of spam', () {
      // If the cooldown were longer than the display life, the bar would feel
      // broken: you tap, nothing is on screen, and you cannot tap again.
      expect(kLudoReactionCooldown, lessThan(kLudoReactionLife));
    });
  });

  group('malformed data does not crash the overlay', () {
    test('a document missing every field still parses', () {
      final r = LudoReaction.fromMap('x', const {});
      expect(r.emoji, '');
      expect(r.fromName, '');
      expect(r.isGift, isFalse);
    });
  });
}
