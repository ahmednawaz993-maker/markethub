part of '../main.dart';

// Namaz timings and the Quran.
//
// Both are built to work with no signal at all: prayer times are computed on
// the device from the sun's position, and the Quran ships inside the app rather
// than being fetched. Someone opening this on a weak connection in a village is
// the person it is for.

const String _kPrefPrayerCity = 'prayer_city';
const String _kPrefAsrSchool = 'prayer_asr_school';
const String _kPrefLastRead = 'quran_last_read';

PrayerLocation _cityByName(String? name) => kPakistanPrayerCities.firstWhere(
  (c) => c.name == name,
  orElse: () => kPakistanPrayerCities.first,
);

String _hhmm(DateTime d) {
  final h24 = d.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${h24 < 12 ? 'AM' : 'PM'}';
}

/// The hub tile pair, shown in the Menu.
class IslamicSectionTiles extends StatelessWidget {
  const IslamicSectionTiles({super.key});

  @override
  Widget build(BuildContext context) => _MenuGroup(
    title: 'Namaz & Quran',
    items: [
      _MenuItem(
        icon: Icons.access_time_filled,
        label: 'Prayer Timings',
        subtitle: 'Namaz times for your city, and the next azan',
        builder: () => const PrayerTimesScreen(),
      ),
      _MenuItem(
        icon: Icons.menu_book,
        label: 'Quran — Urdu Translation',
        subtitle: 'All 114 surahs, works offline',
        builder: () => const QuranSurahListScreen(),
      ),
    ],
  );
}

/// Games. Separate from the marketplace on purpose — it is a reason to open
/// the app on a day nobody is buying anything.
class GamesSectionTiles extends StatelessWidget {
  const GamesSectionTiles({super.key});

  @override
  Widget build(BuildContext context) => _MenuGroup(
    title: 'Games',
    items: [
      _MenuItem(
        icon: Icons.casino,
        label: 'Ludo',
        subtitle: 'Play with friends, with chat at the table',
        builder: () => const LudoLobbyScreen(),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Prayer timings
// ---------------------------------------------------------------------------

class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  PrayerLocation _city = kPakistanPrayerCities.first;
  AsrSchool _asr = AsrSchool.hanafi;
  bool _loaded = false;
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _restore();
    // The countdown is the reason people open this screen; a minute is fine.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final city = _cityByName(p.getString(_kPrefPrayerCity));
      final asr = AsrSchool.values.firstWhere(
        (s) => s.name == p.getString(_kPrefAsrSchool),
        orElse: () => AsrSchool.hanafi,
      );
      if (!mounted) return;
      setState(() {
        _city = city;
        _asr = asr;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefPrayerCity, _city.name);
      await p.setString(_kPrefAsrSchool, _asr.name);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prayer Timings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final today = computePrayerTimes(
      date: _now,
      location: _city,
      asr: _asr,
    );
    final next = today.nextAfter(_now);
    final tomorrowFajr = computePrayerTimes(
      date: _now.add(const Duration(days: 1)),
      location: _city,
      asr: _asr,
    ).fajr;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Timings'),
        actions: [
          IconButton(
            tooltip: 'Change city',
            icon: const Icon(Icons.location_city),
            onPressed: _pickCity,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        children: [
          _nextCard(next, tomorrowFajr),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in today.schedule) _row(p, next?.key == p.key),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _asrCard(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Times are calculated for ${_city.name} using the University of '
            'Islamic Sciences, Karachi method (Fajr and Isha at 18°), the '
            'convention used across Pakistan. Your local masjid may differ by '
            'a minute or two — follow your masjid for jamaat.',
            style: AppType.caption,
          ),
        ],
      ),
    );
  }

  Widget _nextCard(
    ({String key, String name, String urdu, DateTime at})? next,
    DateTime tomorrowFajr,
  ) {
    final label = next?.name ?? 'Fajr';
    final urdu = next?.urdu ?? 'فجر';
    final at = next?.at ?? tomorrowFajr;
    final left = at.difference(_now);
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPakGreen, kPakGreenLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mosque, color: Colors.white70, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  next == null ? 'Next prayer · tomorrow' : 'Next prayer',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Text(
                _city.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '$label  $urdu',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _hhmm(at),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            h > 0 ? 'in $h h $m min' : 'in $m min',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ({String key, String name, String urdu, DateTime at}) p,
    bool isNext,
  ) {
    final passed = p.at.isBefore(_now);
    final isSunrise = p.key == 'sunrise';
    return Container(
      decoration: BoxDecoration(
        color: isNext ? kPakGreen.withValues(alpha: 0.08) : null,
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            isSunrise ? Icons.wb_twilight : Icons.circle,
            size: isSunrise ? 18 : 9,
            color: isNext
                ? kPakGreen
                : (passed ? AppColors.textMuted : AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md),
          // Name and Urdu share one flexible span: as separate widgets the
          // Urdu and the time were pushed off a 320px screen by 84px at large
          // text, because only the name could shrink.
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: p.name,
                    style: TextStyle(
                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                      color: isSunrise ? AppColors.textSecondary : null,
                    ),
                  ),
                  const TextSpan(text: '   '),
                  TextSpan(text: p.urdu, style: AppType.secondary),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _hhmm(p.at),
            style: TextStyle(
              fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
              color: isNext ? kPakGreen : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _asrCard() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Asr calculation', style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The two schools put Asr up to an hour apart. Hanafi is the majority '
          'in Pakistan.',
          style: AppType.secondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final s in AsrSchool.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              s == _asr ? Icons.radio_button_checked : Icons.radio_button_off,
              color: s == _asr ? kPakGreen : AppColors.textMuted,
            ),
            title: Text('${s.label}  ·  ${s.urdu}'),
            onTap: () {
              setState(() => _asr = s);
              _save();
            },
          ),
      ],
    ),
  );

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<PrayerLocation>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Choose your city', style: AppType.sectionTitle),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: kPakistanPrayerCities.length,
                itemBuilder: (_, i) {
                  final c = kPakistanPrayerCities[i];
                  return ListTile(
                    dense: true,
                    title: Text(c.name),
                    trailing: c.name == _city.name
                        ? const Icon(Icons.check, color: kPakGreen)
                        : null,
                    onTap: () => Navigator.pop(ctx, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _city = picked);
    await _save();
  }
}

// ---------------------------------------------------------------------------
// Quran
// ---------------------------------------------------------------------------

/// One surah's metadata and verses, as bundled.
class QuranSurah {
  const QuranSurah({
    required this.number,
    required this.arabicName,
    required this.name,
    required this.meaning,
    required this.revelation,
    required this.verses,
  });

  final int number;
  final String arabicName;
  final String name;
  final String meaning;
  final String revelation;
  final List<({int number, String arabic, String urdu})> verses;
}

/// Loads and caches the bundled Quran. Parsed once per app run — the asset is
/// 3 MB, so this is deliberately not re-read per screen.
class QuranLibrary {
  static List<QuranSurah>? _cache;
  static Future<List<QuranSurah>>? _inFlight;

  static Future<List<QuranSurah>> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _read();
  }

  static Future<List<QuranSurah>> _read() async {
    final raw = await rootBundle.loadString('assets/quran/quran_ur.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final surahs = <QuranSurah>[];
    for (final s in (decoded['surahs'] as List)) {
      final m = s as Map<String, dynamic>;
      surahs.add(
        QuranSurah(
          number: m['n'] as int,
          arabicName: m['ar']?.toString() ?? '',
          name: m['en']?.toString() ?? '',
          meaning: m['meaning']?.toString() ?? '',
          revelation: m['place']?.toString() ?? '',
          verses: [
            for (final v in (m['verses'] as List))
              (
                number: (v as Map<String, dynamic>)['n'] as int,
                arabic: v['ar']?.toString() ?? '',
                urdu: v['ur']?.toString() ?? '',
              ),
          ],
        ),
      );
    }
    _cache = surahs;
    _inFlight = null;
    return surahs;
  }
}

class QuranSurahListScreen extends StatefulWidget {
  const QuranSurahListScreen({super.key});

  @override
  State<QuranSurahListScreen> createState() => _QuranSurahListScreenState();
}

class _QuranSurahListScreenState extends State<QuranSurahListScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _lastRead;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((p) {
          if (mounted) setState(() => _lastRead = p.getString(_kPrefLastRead));
        })
        .catchError((_) => null);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(QuranSurah s) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return s.name.toLowerCase().contains(q) ||
        s.meaning.toLowerCase().contains(q) ||
        s.arabicName.contains(_query) ||
        '${s.number}' == _query.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quran — Urdu')),
      body: FutureBuilder<List<QuranSurah>>(
        future: QuranLibrary.load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Could not open the Quran',
              subtitle: 'Please reinstall the app and try again.',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final shown = all.where(_matches).toList();
          final resume = _lastRead;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a surah — name or number',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (resume != null && _query.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: AppCard(
                    onTap: () {
                      final n = int.tryParse(resume);
                      if (n == null) return;
                      _open(all.firstWhere((s) => s.number == n));
                    },
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark, color: kPakGreen),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Continue reading — '
                            '${all.firstWhere((s) => s.number == int.tryParse(resume), orElse: () => all.first).name}',
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.navClearance,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final s = shown[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: kPakGreen.withValues(alpha: 0.12),
                        child: Text(
                          '${s.number}',
                          style: const TextStyle(
                            color: kPakGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${s.meaning} · ${s.verses.length} ayahs · '
                        '${s.revelation == 'makkah' ? 'Makki' : 'Madani'}',
                        style: AppType.caption,
                      ),
                      trailing: Text(
                        s.arabicName,
                        style: const TextStyle(fontSize: 17),
                        textDirection: TextDirection.rtl,
                      ),
                      onTap: () => _open(s),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _open(QuranSurah s) {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kPrefLastRead, '${s.number}'))
        .catchError((_) => false);
    setState(() => _lastRead = '${s.number}');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuranReaderScreen(surah: s)),
    );
  }
}

class QuranReaderScreen extends StatelessWidget {
  const QuranReaderScreen({super.key, required this.surah});

  final QuranSurah surah;

  @override
  Widget build(BuildContext context) {
    // Surah 9 (At-Tawbah) is the one surah that does not open with the
    // Bismillah, so the header must not assume it.
    final showsBismillah = surah.number != 9 && surah.number != 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('${surah.number}. ${surah.name}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${surah.meaning} · ${surah.verses.length} ayahs',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        itemCount: surah.verses.length + (showsBismillah ? 1 : 0),
        itemBuilder: (context, i) {
          if (showsBismillah && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 24,
                  height: 2.0,
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }
          final v = surah.verses[i - (showsBismillah ? 1 : 0)];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kPakGreen.withValues(alpha: 0.10),
                        borderRadius: AppRadius.rPill,
                      ),
                      child: Text(
                        '${surah.number}:${v.number}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kPakGreen,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy ayah',
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                '${v.arabic}\n\n${v.urdu}\n\n'
                                '(${surah.name} ${surah.number}:${v.number})',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ayah copied')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Arabic: right-aligned, generous line height. Rendered with
                // the platform's Arabic face — Android and iOS both ship one
                // that handles Uthmani diacritics.
                Text(
                  v.arabic,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    // The largest step on the scale, matching the Bismillah
                    // above. Quranic Arabic carries diacritics that become
                    // unreadable at body size, so this is the one place in the
                    // app that genuinely needs the top of the scale.
                    fontSize: 24,
                    height: 2.1,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  v.urdu,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.9,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(color: AppColors.borderSoft, height: 1),
              ],
            ),
          );
        },
      ),
    );
  }
}
