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

  // THE DEADLOCK REGRESSION.
  //
  // The pending dice used to live only in the game screen's own memory. The
  // server parks it on the shared state, so losing the local copy — a rebuild,
  // backgrounding the app, reopening the game — left the player with no tokens
  // to tap AND a server that refused a new roll because one was already
  // pending. Neither move nor roll worked, permanently, for everyone.
  //
  // The fix is that the roll survives a round trip through the document, so a
  // rebuild recovers it. That is exactly what this asserts.
  group('a pending roll survives a rebuild', () {
    test('the dice round-trips through the room document', () {
      var game = LudoGame.newGame(const [LudoColor.red, LudoColor.green]);
      final rolled = game.roll(6);
      expect(rolled.game.lastDice, 6, reason: 'the roll is parked on the state');

      final doc = {
        'hostId': 'u1',
        'seats': {'red': 'u1', 'green': 'u2'},
        'names': {'red': 'A', 'green': 'B'},
        'status': 'playing',
        'state': rolled.game.toJson(),
      };
      // Re-read it the way a fresh build of the screen would.
      final room = LudoRoom.fromMap('r1', doc);
      expect(room.game.lastDice, 6);
      expect(
        room.game.legalMoves(room.game.lastDice!),
        isNotEmpty,
        reason: 'the board must still offer the move after a rebuild',
      );
    });

    test('playing the move clears the dice so the turn can end', () {
      var game = LudoGame.newGame(const [LudoColor.red, LudoColor.green]);
      final rolled = game.roll(6);
      final after = rolled.game.applyMove(rolled.moves.first);
      expect(after.lastDice, isNull);
      final room = LudoRoom.fromMap('r1', {
        'seats': {'red': 'u1'},
        'status': 'playing',
        'state': after.toJson(),
      });
      expect(
        room.game.lastDice,
        isNull,
        reason: 'a cleared dice is what lets the next roll be requested',
      );
    });
  });
}
