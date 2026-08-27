import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Seat bookkeeping decides who is allowed to move, and firestore.rules trusts
// the same mapping. A bug here is not a display glitch — it is one player able
// to play another's turn.

void main() {
  Map<String, dynamic> raw({
    Map<String, String> seats = const {'red': 'u1', 'green': 'u2'},
    String status = 'playing',
  }) => {
    'hostId': 'u1',
    'seats': seats,
    'names': {'red': 'Ahmed', 'green': 'Bilal'},
    'status': status,
    'state': LudoGame.newGame(const [
      LudoColor.red,
      LudoColor.green,
    ]).toJson(),
  };

  test('a seated player maps to their colour, others to null', () {
    final r = LudoRoom.fromMap('r1', raw());
    expect(r.colorOf('u1'), LudoColor.red);
    expect(r.colorOf('u2'), LudoColor.green);
    expect(r.colorOf('someone-else'), isNull, reason: 'spectators cannot move');
  });

  test('seated colours come back in board order, not insertion order', () {
    final r = LudoRoom.fromMap(
      'r1',
      raw(seats: const {'yellow': 'u3', 'red': 'u1'}),
    );
    expect(r.seatedColors, [LudoColor.red, LudoColor.yellow]);
  });

  test('a room is full at four and not before', () {
    expect(LudoRoom.fromMap('r', raw()).isFull, isFalse);
    expect(
      LudoRoom.fromMap(
        'r',
        raw(seats: const {'red': 'a', 'green': 'b', 'yellow': 'c', 'blue': 'd'}),
      ).isFull,
      isTrue,
    );
  });

  test('an unknown status falls back to waiting rather than throwing', () {
    expect(
      LudoRoom.fromMap('r', raw(status: 'nonsense')).status,
      LudoRoomStatus.waiting,
    );
  });

  // A room document written by an older build, or mid-creation, must not crash
  // the lobby for everyone else.
  test('a malformed document degrades instead of throwing', () {
    final r = LudoRoom.fromMap('r', const {});
    expect(r.seats, isEmpty);
    expect(r.colorOf('u1'), isNull);
    expect(r.game.players, isNotEmpty);
  });
}
