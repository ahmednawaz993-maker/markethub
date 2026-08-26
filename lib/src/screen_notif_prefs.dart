part of '../main.dart';

// New-listing notification preferences. Stored as a `notifPrefs` map on the
// user's own profile doc (owner-editable; the Cloud Function reads it before
// subscribing the user's devices).
//
// New listings are announced to every user via a single FCM topic broadcast,
// so this screen is an OPT-OUT: leaving the switch on means you hear about
// every ad posted on PakBazar. Saving here retriggers syncNewListingTopicOnPrefs
// in functions/index.js, which subscribes or unsubscribes every device you own.

class NotificationPrefs {
  bool newListing; // master on/off for new-listing alerts
  bool push; // legacy: false = in-app inbox only, no push
  String mode; // legacy: 'all' | 'daily' | 'weekly' | 'off'

  // Interest filters from the retired interest-matched alerts. Nothing reads
  // them today (every user hears about every listing), but they are still
  // loaded and saved verbatim so the data survives for a future "only notify
  // me about these categories" feature.
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

  @override
  void initState() {
    super.initState();
    _load();
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

  /// The single switch is authoritative. Turning alerts ON also clears the
  /// legacy `push: false` / `mode: 'daily'` flags, which the server still
  /// honours as opt-outs -- without this, a user who set one of them long ago
  /// could never get new-listing alerts back from this screen.
  void _setEnabled(bool on) {
    setState(() {
      _prefs.newListing = on;
      if (on) {
        _prefs.push = true;
        _prefs.mode = 'all';
      }
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        children: [
          SurfacePanel(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New-listing notifications'),
                  subtitle: const Text(
                    'Get an alert whenever a new ad is posted on PakBazar.',
                  ),
                  value: _prefs.newListing,
                  activeThumbColor: kPakGreen,
                  onChanged: _saving ? null : _setEnabled,
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
                Text(
                  'You will be notified about every approved, in-stock ad, not '
                  'just ones matching your interests. Turn this off any time to '
                  'stop new-listing alerts on all your devices. Chat, order and '
                  'offer notifications are not affected.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
