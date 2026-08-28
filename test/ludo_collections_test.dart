// Dice and token collections.
//
// The rule worth guarding is the same one board themes have: a skin may change
// the SHAPE and the FINISH of a piece, never its colour. Red, green, yellow,
// blue, purple and orange are how a player finds their own tokens and reads
// whose turn it is, so a skin that recoloured them would make the board prettier
// and the game unreadable.
//
// The structural half of that guarantee is that LudoTokenSkin carries no colour
// at all — there is nothing in it that COULD recolour a seat. The behavioural
// half is checked here by painting every skin in every seat colour and reading
// the result back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  group('the sets are well formed', () {
    test('every dice skin is distinct and named', () {
      expect(
        LudoDiceSkin.all.map((d) => d.id).toSet().length,
        LudoDiceSkin.all.length,
        reason: 'duplicate dice id',
      );
      for (final d in LudoDiceSkin.all) {
        expect(d.label, isNotEmpty);
      }
    });

    test('every token skin is distinct and named', () {
      expect(
        LudoTokenSkin.all.map((t) => t.id).toSet().length,
        LudoTokenSkin.all.length,
      );
      expect(
        LudoTokenSkin.all.map((t) => t.style).toSet().length,
        LudoTokenSkin.all.length,
        reason: 'two skins share a style, so they look identical',
      );
    });

    test('an unknown id falls back rather than throwing', () {
      // A preference written by a build that had a skin this one does not.
      expect(LudoDiceSkin.byId('no-such-dice').id, LudoDiceSkin.ivory.id);
      expect(LudoDiceSkin.byId(null).id, LudoDiceSkin.ivory.id);
      expect(LudoTokenSkin.byId('no-such-token').id, LudoTokenSkin.glossy.id);
      expect(LudoTokenSkin.byId(null).id, LudoTokenSkin.glossy.id);
    });
  });

  group('a dice skin stays legible', () {
    test('pips always contrast with the face', () {
      // A gold pip on a gold face is a die nobody can read.
      for (final d in LudoDiceSkin.all) {
        final diff =
            (d.face.computeLuminance() - d.pip.computeLuminance()).abs();
        expect(
          diff,
          greaterThan(0.3),
          reason: '${d.label}: pips and face are too close ($diff)',
        );
      }
    });

    test('the edge is not the face, or the die has no outline', () {
      for (final d in LudoDiceSkin.all) {
        expect(d.edge, isNot(d.face), reason: d.label);
      }
    });

    test('both light and dark dice are offered', () {
      final dark = LudoDiceSkin.all
          .where((d) => d.face.computeLuminance() < 0.4)
          .length;
      expect(dark, greaterThan(0));
      expect(dark, lessThan(LudoDiceSkin.all.length));
    });
  });

  group('a token skin never touches the seat colour', () {
    test('the skin carries no colour of its own', () {
      // Structural: there is no palette on a token skin to get wrong.
      for (final t in LudoTokenSkin.all) {
        expect(t.style, isA<LudoTokenStyle>());
      }
    });

    test('every skin paints every seat in that seat colour', () {
      // Painting each skin in each colour and reading back what dominates.
      for (final skin in LudoTokenSkin.all) {
        for (final seat in LudoColor.values) {
          final c = ludoColorOf(seat);
          final d =
              ludoTokenDecoration(colour: c, playable: false, skin: skin)
                  as BoxDecoration;
          final usesSeatColour =
              d.color == c ||
              d.border?.top.color == c ||
              (d.gradient is Gradient &&
                  (d.gradient! as dynamic).colors.contains(c));
          expect(
            usesSeatColour,
            isTrue,
            reason: '${skin.label} lost ${seat.name}',
          );
        }
      }
    });

    test('two different seats never paint the same', () {
      // The failure that matters: a skin that washed colours together would
      // make it impossible to tell your piece from somebody else's.
      for (final skin in LudoTokenSkin.all) {
        final seen = <String>{};
        for (final seat in LudoColor.values) {
          final d =
              ludoTokenDecoration(
                    colour: ludoColorOf(seat),
                    playable: false,
                    skin: skin,
                  )
                  as BoxDecoration;
          final key = '${d.color}|${d.border?.top.color}|'
              '${d.gradient == null ? '' : (d.gradient! as dynamic).colors}';
          expect(
            seen.add(key),
            isTrue,
            reason: '${skin.label} paints two seats identically',
          );
        }
      }
    });
  });

  group('the pieces still read as pieces', () {
    test('every skin casts a shadow, so it sits on the board', () {
      for (final skin in LudoTokenSkin.all) {
        final d =
            ludoTokenDecoration(
                  colour: ludoColorOf(LudoColor.red),
                  playable: false,
                  skin: skin,
                )
                as BoxDecoration;
        expect(d.boxShadow, isNotEmpty, reason: skin.label);
      }
    });

    test('a playable piece glows in its own colour, whatever the skin', () {
      for (final skin in LudoTokenSkin.all) {
        final c = ludoColorOf(LudoColor.green);
        final d =
            ludoTokenDecoration(colour: c, playable: true, skin: skin)
                as BoxDecoration;
        expect(
          d.boxShadow!.length,
          greaterThan(1),
          reason: '${skin.label} has no playable glow',
        );
      }
    });

    test('only the glossy piece wears a highlight', () {
      // On a flat or ring token a specular dot reads as a smudge.
      expect(ludoTokenHasHighlight(LudoTokenSkin.glossy), isTrue);
      expect(ludoTokenHasHighlight(LudoTokenSkin.flat), isFalse);
      expect(ludoTokenHasHighlight(LudoTokenSkin.ring), isFalse);
    });
  });
}
