import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
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

  group('the turn countdown', () {
    // The client's countdown MUST NOT run faster than the server acts, or a
    // player watches it hit zero and nothing happens — worse than no timer.
    test('matches the server deadline exactly', () {
      expect(
        kLudoTurnSeconds,
        45,
        reason: 'must equal LUDO_TURN_SECONDS in functions/index.js',
      );
    });

    LudoRoom roomUpdated(Duration ago, {String status = 'playing'}) =>
        LudoRoom.fromMap('r', {
          'seats': {'red': 'u1', 'green': 'u2'},
          'status': status,
          'state': LudoGame.newGame(const [
            LudoColor.red,
            LudoColor.green,
          ]).toJson(),
          'updatedAt': Timestamp.fromDate(DateTime.now().subtract(ago)),
        });

    test('counts down and stops at zero rather than going negative', () {
      expect(
        ludoSecondsLeft(roomUpdated(const Duration(seconds: 5))),
        closeTo(40, 1),
      );
      expect(ludoSecondsLeft(roomUpdated(const Duration(minutes: 5))), 0);
    });

    test('is silent when there is nothing to count', () {
      expect(
        ludoSecondsLeft(roomUpdated(Duration.zero, status: 'waiting')),
        isNull,
        reason: 'nobody is on the clock before the game starts',
      );
      // A room mid-write, before updatedAt lands: no clock to show yet.
      final noStamp = LudoRoom.fromMap('r', {
        'status': 'playing',
        'seats': {'red': 'u1', 'green': 'u2'},
        'state': LudoGame.newGame(const [
          LudoColor.red,
          LudoColor.green,
        ]).toJson(),
      });
      expect(ludoSecondsLeft(noStamp), isNull);
    });
  });

  group('the version gate', () {
    final original = appBuildNumber;
    tearDown(() => appBuildNumber = original);

    // Builds before kLudoMinBuild roll on the device, and the rules now reject
    // a client-written dice — so on those builds the dice is silently dead and
    // the server quietly plays the turn instead. They are told to update.
    test('an old build is asked to update', () {
      appBuildNumber = kLudoMinBuild - 1;
      expect(ludoNeedsUpdate(), isTrue);
    });

    test('the current build plays', () {
      appBuildNumber = kLudoMinBuild;
      expect(ludoNeedsUpdate(), isFalse);
      appBuildNumber = kLudoMinBuild + 10;
      expect(ludoNeedsUpdate(), isFalse);
    });

    // 0 means "not reported yet" on a cold start. Treating it as ancient would
    // lock every player out of Ludo for the first moments of every launch.
    test('an unknown build is never treated as too old', () {
      appBuildNumber = 0;
      expect(ludoNeedsUpdate(), isFalse);
    });
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
