// Walking out of a game, and board themes.
//
// LEAVING is the part with teeth. A player who quits must stop counting — no
// win reward, no share of the pot, no leaderboard row — or quitting a losing
// position becomes free, and quitting a losing STAKED position becomes
// profitable. Their seat is handed to a computer rather than emptied, because
// three other people are mid-game and collapsing the board would punish the
// wrong players.
//
// The Firestore write needs a backend, so what is pinned here is how a room
// reads afterwards: who is still seated, who is recorded as gone, and that the
// two never disagree.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

LudoRoom room({
  Map<String, String> seats = const {'red': 'u1', 'green': 'u2'},
  List<String> abandoned = const [],
  int stake = 0,
  int pot = 0,
}) => LudoRoom.fromMap('r1', {
  'hostId': 'u1',
  'seats': seats,
  'names': {for (final e in seats.entries) e.key: e.key},
  'status': 'playing',
  'abandonedBy': abandoned,
  'stake': stake,
  'pot': pot,
  'updatedAt': Timestamp.now(),
});

void main() {
  group('a player who left', () {
    test('is recorded as gone', () {
      final r = room(
        seats: const {'red': 'bot:2', 'green': 'u2'},
        abandoned: const ['u1'],
      );
      expect(ludoHasAbandoned(r, 'u1'), isTrue);
      expect(ludoHasAbandoned(r, 'u2'), isFalse);
    });

    test('no longer holds a seat', () {
      // The uid must be gone from seats, or the client would still think it
      // was that player's turn.
      final r = room(
        seats: const {'red': 'bot:2', 'green': 'u2'},
        abandoned: const ['u1'],
      );
      expect(r.colorOf('u1'), isNull);
      expect(r.colorOf('u2'), LudoColor.green);
    });

    test('leaves a computer in their place, not an empty seat', () {
      // An emptied seat would shrink the game under the remaining players and
      // renumber the colours mid-match.
      final r = room(
        seats: const {'red': 'bot:2', 'green': 'u2'},
        abandoned: const ['u1'],
      );
      expect(r.seats.length, 2);
      expect(isLudoBotSeat(r, LudoColor.red), isTrue);
    });

    test('a table nobody left records nobody', () {
      expect(room().abandonedBy, isEmpty);
      expect(ludoHasAbandoned(room(), 'u1'), isFalse);
    });
  });

  group('the stake stays in the pot', () {
    test('a leaver does not take their entry back', () {
      // Refunding would make quitting free, and quitting a losing staked
      // position profitable. The remaining players are still competing for it.
      final r = room(
        seats: const {'red': 'bot:2', 'green': 'u2'},
        abandoned: const ['u1'],
        stake: 500,
        pot: 1000,
      );
      expect(r.pot, 1000, reason: 'the pot must not shrink when someone quits');
      expect(r.stake, 500);
    });
  });

  group('a room with no abandonedBy field still reads', () {
    test('older documents predate the field', () {
      final r = LudoRoom.fromMap('r1', {
        'seats': {'red': 'u1'},
        'status': 'playing',
      });
      expect(r.abandonedBy, isEmpty);
      expect(ludoHasAbandoned(r, 'u1'), isFalse);
    });
  });

  group('board themes', () {
    test('every theme is distinct and named', () {
      final ids = LudoTheme.all.map((t) => t.id).toSet();
      expect(ids.length, LudoTheme.all.length, reason: 'duplicate theme id');
      for (final t in LudoTheme.all) {
        expect(t.label, isNotEmpty);
        expect(t.id, isNotEmpty);
      }
    });

    test('an unknown id falls back to Classic rather than throwing', () {
      // A stored preference from a build that had a theme this one does not.
      expect(LudoTheme.byId('no-such-theme').id, LudoTheme.classic.id);
      expect(LudoTheme.byId(null).id, LudoTheme.classic.id);
    });

    test('each theme declares whether it is dark', () {
      // Supplied rather than inferred: a mid-tone surface is ambiguous, and
      // guessing wrong makes the track vanish into the ground — which has
      // happened on this board once already.
      final dark = LudoTheme.all.where((t) => t.dark).length;
      expect(dark, greaterThan(0), reason: 'no dark board offered');
      expect(dark, lessThan(LudoTheme.all.length), reason: 'no light board');
    });

    test('a theme never recolours the seats', () {
      // Red, green, yellow and blue are how a player finds their own tokens.
      // A theme that changed them would make the board prettier and the game
      // unreadable, so the palette carries no seat colours at all.
      for (final t in LudoTheme.all) {
        for (final c in LudoColor.values) {
          expect(t.surface, isNot(ludoColorOf(c)));
        }
      }
    });

    test('the board and its edges are never the same colour', () {
      // Identical surface and line means invisible tiles.
      for (final t in LudoTheme.all) {
        expect(t.surface, isNot(t.line), reason: t.label);
      }
    });
  });
}
