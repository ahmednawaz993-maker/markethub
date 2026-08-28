// Six-player tables online.
//
// The room used to assume four seats everywhere: isFull, the free-colour
// search, the bot filler and the security rule all counted to four. The table's
// size now lives on the room, and the failure this guards against is a room
// that thinks it is full at four when it has six chairs — nobody could join,
// with no error to explain why.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoRoom room({
  Map<String, String> seats = const {'red': 'u1'},
  int? seatCap,
  String status = 'waiting',
}) => LudoRoom.fromMap('r1', {
  'hostId': 'u1',
  'seats': seats,
  'names': {for (final e in seats.entries) e.key: e.key},
  'status': status,
  'seatCap': ?seatCap,
  'updatedAt': Timestamp.now(),
});

void main() {
  group('a table knows its own size', () {
    test('a room with no seatCap is a four-seater', () {
      // Every room created before six-player tables existed.
      expect(room().seatCap, 4);
      expect(room().spec.seats, 4);
    });

    test('a six-seat room says so', () {
      final r = room(seatCap: 6);
      expect(r.seatCap, 6);
      expect(r.spec.seats, 6);
      expect(r.spec.ringLength, 72);
    });
  });

  group('fullness follows the table, not a fixed four', () {
    test('four players fill a four-seater', () {
      final r = room(
        seats: const {'red': 'a', 'green': 'b', 'yellow': 'c', 'blue': 'd'},
      );
      expect(r.isFull, isTrue);
    });

    test('four players do NOT fill a six-seater', () {
      // The bug this exists for: two empty chairs and nobody able to sit down.
      final r = room(
        seats: const {'red': 'a', 'green': 'b', 'yellow': 'c', 'blue': 'd'},
        seatCap: 6,
      );
      expect(r.isFull, isFalse);
    });

    test('six players fill a six-seater', () {
      final r = room(
        seats: const {
          'red': 'a',
          'green': 'b',
          'yellow': 'c',
          'blue': 'd',
          'purple': 'e',
          'orange': 'f',
        },
        seatCap: 6,
      );
      expect(r.isFull, isTrue);
    });
  });

  group('the extra seats are real seats', () {
    test('purple and orange are seatable on a six-player table', () {
      final r = room(
        seats: const {'red': 'a', 'purple': 'e', 'orange': 'f'},
        seatCap: 6,
      );
      expect(r.colorOf('e'), LudoColor.purple);
      expect(r.colorOf('f'), LudoColor.orange);
      expect(r.seatedColors, [
        LudoColor.red,
        LudoColor.purple,
        LudoColor.orange,
      ]);
    });

    test('a four-player table offers only the classic four colours', () {
      expect(room().spec.colours, isNot(contains(LudoColor.purple)));
      expect(room(seatCap: 6).spec.colours, contains(LudoColor.purple));
    });
  });

  group('the two boards agree with the engine', () {
    test('a six-seat room plays on the 72-ring', () {
      // The room's spec and the game's spec must be the same board, or the
      // client would draw one geometry and compute moves on another.
      final r = room(seatCap: 6);
      final game = LudoGame.newGame(LudoBoardSpec.six.colours);
      expect(r.spec.ringLength, game.spec.ringLength);
      expect(r.spec.home, game.spec.home);
      expect(r.spec.startCellOf(LudoColor.green),
          game.spec.startCellOf(LudoColor.green));
    });

    test('a four-seat room still plays on the 52-ring', () {
      final r = room();
      final game = LudoGame.newGame(LudoBoardSpec.four.colours);
      expect(r.spec.ringLength, 52);
      expect(r.spec.ringLength, game.spec.ringLength);
      expect(r.spec.startCellOf(LudoColor.green), 13);
    });
  });
}
