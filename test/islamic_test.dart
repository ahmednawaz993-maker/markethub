import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Quran asset is the important one here. A truncated or mis-registered
// asset would surface as an empty reader rather than a crash, and scripture
// that silently loses verses is the worst failure this app could have — so the
// bundled file is loaded for real and counted, not mocked.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bundled Quran', () {
    test('loads from the asset and is structurally complete', () async {
      final surahs = await QuranLibrary.load();
      expect(surahs.length, 114, reason: 'every surah must be present');
      expect(
        surahs.fold<int>(0, (n, s) => n + s.verses.length),
        6236,
        reason: 'the Quran has 6,236 ayahs',
      );
      for (final s in surahs) {
        expect(s.name.trim(), isNotEmpty, reason: 'surah ${s.number} name');
        expect(s.arabicName.trim(), isNotEmpty);
        for (final v in s.verses) {
          expect(v.arabic.trim(), isNotEmpty, reason: '${s.number}:${v.number}');
          expect(v.urdu.trim(), isNotEmpty, reason: '${s.number}:${v.number}');
        }
      }
    });

    test('surah numbering is 1..114 in order, ayahs 1..n', () async {
      final surahs = await QuranLibrary.load();
      for (var i = 0; i < surahs.length; i++) {
        expect(surahs[i].number, i + 1);
        for (var j = 0; j < surahs[i].verses.length; j++) {
          expect(surahs[i].verses[j].number, j + 1);
        }
      }
    });

    // Al-Fatiha and the last two surahs are short enough to state exactly, and
    // wrong ayah counts here would mean the fetch silently paginated badly.
    test('known surah lengths are exact', () async {
      final surahs = await QuranLibrary.load();
      expect(surahs[0].verses.length, 7, reason: 'Al-Fatiha');
      expect(surahs[1].verses.length, 286, reason: 'Al-Baqarah');
      expect(surahs[16].verses.length, 111, reason: 'Al-Isra');
      expect(surahs[112].verses.length, 5, reason: 'Al-Falaq');
      expect(surahs[113].verses.length, 6, reason: 'An-Nas');
    });
  });

  group('reader layout', () {
    QuranSurah fatSurah() => QuranSurah(
      number: 2,
      arabicName: 'البقرة',
      name: 'Al-Baqarah',
      meaning: 'The Cow',
      revelation: 'madinah',
      verses: [
        for (var i = 1; i <= 3; i++)
          (
            number: i,
            // A genuinely long ayah with full diacritics, which is what
            // stresses the right-to-left line breaking.
            arabic:
                'ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ '
                'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُقِيمُونَ ٱلصَّلَوٰةَ',
            urdu:
                'یہ کتاب ہے جس میں کوئی شک نہیں پرہیزگاروں کو راہ دکھانے والی '
                'ہے جو غیب پر ایمان لاتے ہیں اور نماز قائم کرتے ہیں',
          ),
      ],
    );

    for (final width in [320.0, 360.0, 411.0, 768.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('ayahs do not overflow at ${width.toInt()}px, x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(home: QuranReaderScreen(surah: fatSurah())),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    // At-Tawbah is the one surah that does not begin with the Bismillah.
    testWidgets('surah 9 does not show a Bismillah', (tester) async {
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tawbah = QuranSurah(
        number: 9,
        arabicName: 'التوبة',
        name: 'At-Tawbah',
        meaning: 'The Repentance',
        revelation: 'madinah',
        verses: [(number: 1, arabic: 'بَرَآءَةٌ', urdu: 'بیزاری ہے')],
      );
      await tester.pumpWidget(
        MaterialApp(home: QuranReaderScreen(surah: tawbah)),
      );
      await tester.pump();
      expect(find.textContaining('بِسْمِ'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('prayer screen layout', () {
    for (final width in [320.0, 411.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('renders without overflow at ${width.toInt()}px, x$scale', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1400),
                textScaler: TextScaler.linear(scale),
              ),
              child: const MaterialApp(home: PrayerTimesScreen()),
            ),
          );
          await tester.pump(); // resolve the prefs future
          await tester.pump();
          expect(tester.takeException(), isNull);

          // The screen runs a periodic timer for the countdown; unmount it so
          // the test does not fail on a pending timer.
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  });
}
