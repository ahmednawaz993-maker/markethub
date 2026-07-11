part of '../main.dart';

// New-listing notification preferences. Stored as a `notifPrefs` map on the
// user's own profile doc (owner-editable; the Cloud Function reads it before
// sending). Opt-in by design: interest matches only fire when the user turns
// new-listing notifications on and saves at least one interest.

class NotificationPrefs {
  bool newListing; // master on/off for new-listing alerts
  bool push; // false = in-app inbox only, no push
  String mode; // 'all' | 'daily' | 'weekly' | 'off'
  List<String> categories;
  List<String> cities;
  List<String> keywords;
  int priceMin;
  int priceMax;

  NotificationPrefs({
    this.newListing = true,
    this.push = true,
    this.mode = 'all',
    this.categories = const [],
    this.cities = const [],
    this.keywords = const [],
    this.priceMin = 0,
    this.priceMax = 0,
  });

  static List<String> _strList(Object? v) => v is List
      ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
      : <String>[];

  factory NotificationPrefs.fromMap(Map<String, dynamic>? m) {
    m ??= const {};
    const validModes = {'all', 'daily', 'weekly', 'off'};
    final mode = m['mode']?.toString() ?? 'all';
    return NotificationPrefs(
      newListing: m['newListing'] != false,
      push: m['push'] != false,
      mode: validModes.contains(mode) ? mode : 'all',
      categories: _strList(m['categories']),
      cities: _strList(m['cities']),
      keywords: _strList(m['keywords']),
      priceMin: (m['priceMin'] as num?)?.toInt() ?? 0,
      priceMax: (m['priceMax'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'newListing': newListing,
    'push': push,
    'mode': mode,
    'categories': categories,
    'cities': cities,
    'keywords': keywords,
    'priceMin': priceMin,
    'priceMax': priceMax,
  };
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  NotificationPrefs _prefs = NotificationPrefs();
  bool _loading = true;
  bool _saving = false;
  final _keywordsController = TextEditingController();
  final _citiesController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordsController.dispose();
    _citiesController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final p = NotificationPrefs.fromMap(
        doc.data()?['notifPrefs'] as Map<String, dynamic>?,
      );
      _keywordsController.text = p.keywords.join(', ');
      _citiesController.text = p.cities.join(', ');
      _minController.text = p.priceMin > 0 ? '${p.priceMin}' : '';
      _maxController.text = p.priceMax > 0 ? '${p.priceMax}' : '';
      if (mounted) {
        setState(() {
          _prefs = p;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _splitCsv(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    _prefs
      ..keywords = _splitCsv(_keywordsController.text)
      ..cities = _splitCsv(_citiesController.text)
      ..priceMin = int.tryParse(_minController.text.trim()) ?? 0
      ..priceMax = int.tryParse(_maxController.text.trim()) ?? 0;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notifPrefs': _prefs.toMap(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final enabled = _prefs.newListing;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('New-listing notifications'),
            subtitle: const Text(
              'Get alerted about new ads that match your interests.',
            ),
            value: _prefs.newListing,
            activeThumbColor: kPakGreen,
            onChanged: _saving
                ? null
                : (v) => setState(() => _prefs.newListing = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Push notifications'),
            subtitle: const Text('Off keeps them in the in-app inbox only.'),
            value: _prefs.push,
            activeThumbColor: kPakGreen,
            onChanged: (!enabled || _saving)
                ? null
                : (v) => setState(() => _prefs.push = v),
          ),
          const Divider(height: 24),
          const Text(
            'How often',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          RadioGroup<String>(
            groupValue: _prefs.mode,
            onChanged: (v) {
              if (!enabled || _saving || v == null) return;
              setState(() => _prefs.mode = v);
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'all',
                  activeColor: kPakGreen,
                  title: Text('All matching listings'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'daily',
                  activeColor: kPakGreen,
                  title: Text('Daily digest'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'weekly',
                  activeColor: kPakGreen,
                  title: Text('Weekly digest'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'off',
                  activeColor: kPakGreen,
                  title: Text('Off'),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          const Text(
            'Categories you follow',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in appCategories)
                FilterChip(
                  label: Text(c.title),
                  selected: _prefs.categories.contains(c.title),
                  selectedColor: kPakGreen.withValues(alpha: 0.18),
                  onSelected: (!enabled || _saving)
                      ? null
                      : (sel) => setState(() {
                          if (sel) {
                            _prefs.categories = [..._prefs.categories, c.title];
                          } else {
                            _prefs.categories = _prefs.categories
                                .where((x) => x != c.title)
                                .toList();
                          }
                        }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _citiesController,
            enabled: enabled && !_saving,
            decoration: const InputDecoration(
              labelText: 'Cities you follow (comma separated)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keywordsController,
            enabled: enabled && !_saving,
            decoration: const InputDecoration(
              labelText: 'Keywords (comma separated)',
              hintText: 'e.g. iphone, honda, sofa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minController,
                  enabled: enabled && !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min price (Rs)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxController,
                  enabled: enabled && !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max price (Rs)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save preferences'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'We only notify you about approved, in-stock listings that match '
            'what you follow — never every listing.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
