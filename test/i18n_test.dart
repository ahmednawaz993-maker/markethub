import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Translation lookup fails silently by nature: a missing key renders as
// something that looks like a label until a human reads it. These pin the
// fallback chain and the table's integrity.

void main() {
  tearDown(() => appLocale.value = kEnglish);

  group('tr', () {
    test('returns English by default', () {
      appLocale.value = kEnglish;
      expect(tr('nav.home'), 'Home');
    });

    test('returns Urdu when the locale is Urdu', () {
      appLocale.value = kUrdu;
      expect(tr('nav.home'), 'ہوم');
      expect(tr('nav.home'), isNot('Home'));
    });

    // The whole point of the fallback parameter: an unregistered key must not
    // put a dotted identifier on screen.
    test('an unknown key renders the English fallback, not the key', () {
      appLocale.value = kUrdu;
      expect(tr('does.not.exist', 'Readable English'), 'Readable English');
      expect(tr('does.not.exist', 'Readable English'), isNot(contains('.')));
    });

    test('an unknown key with no fallback returns the key', () {
      expect(tr('does.not.exist'), 'does.not.exist');
    });

    test('isUrdu tracks the locale', () {
      appLocale.value = kEnglish;
      expect(isUrdu, isFalse);
      appLocale.value = kUrdu;
      expect(isUrdu, isTrue);
    });
  });

  group('string table', () {
    test('every key has both an English and an Urdu entry', () {
      // A key with only an English entry silently shows English to Urdu
      // users, which is the exact half-translated state this work addresses.
      appLocale.value = kUrdu;
      for (final key in translationKeys) {
        final urdu = tr(key);
        appLocale.value = kEnglish;
        final english = tr(key);
        appLocale.value = kUrdu;

        expect(urdu.trim(), isNotEmpty, reason: '$key has an empty Urdu entry');
        expect(
          english.trim(),
          isNotEmpty,
          reason: '$key has an empty English entry',
        );
        expect(
          urdu,
          isNot(key),
          reason: '$key resolved to the raw key in Urdu',
        );
      }
    });

    test('Urdu entries are not just copies of the English', () {
      // Catches a key added with the English text pasted into the 'ur' slot.
      appLocale.value = kUrdu;
      final untranslated = <String>[];
      for (final key in translationKeys) {
        final urdu = tr(key);
        appLocale.value = kEnglish;
        final english = tr(key);
        appLocale.value = kUrdu;
        // Brand and product names legitimately stay Latin.
        if (urdu == english && english != 'WhatsApp') untranslated.add(key);
      }
      expect(untranslated, isEmpty, reason: 'untranslated keys: $untranslated');
    });
  });
}
