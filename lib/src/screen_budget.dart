part of '../main.dart';

// Budget Calculator & Rate List.
//
// The calculator is plain arithmetic and works offline; the numbers never
// leave the phone unless the user asks for AI advice. The rate list is
// researched by Gemini (Google Search) every morning (functions/ai_functions.js)
// and cached per city, so opening it is normally instant and free.

const String _kPrefToolsCity = 'tools_city';
const String _kPrefBudget = 'tools_budget';

const String _kAiFunctionsBase =
    'https://us-central1-markethub-80276.cloudfunctions.net';

/// The budget lines, in the order shown. Keys match EXPENSE_KEYS in
/// functions/ai_helper.js — the server ignores anything else.
const List<({String key, String label, IconData icon})> kBudgetExpenseLines = [
  (key: 'rent', label: 'Rent / house', icon: Icons.home_outlined),
  (
    key: 'groceries',
    label: 'Groceries & food',
    icon: Icons.shopping_basket_outlined,
  ),
  (
    key: 'utilities',
    label: 'Bills (bijli, gas, net)',
    icon: Icons.bolt_outlined,
  ),
  (
    key: 'transport',
    label: 'Transport & fuel',
    icon: Icons.directions_bus_outlined,
  ),
  (key: 'education', label: 'School & tuition', icon: Icons.school_outlined),
  (
    key: 'health',
    label: 'Health & medicine',
    icon: Icons.medical_services_outlined,
  ),
  (key: 'loans', label: 'Loan payments', icon: Icons.account_balance_outlined),
  (key: 'committee', label: 'Committee (BC)', icon: Icons.groups_outlined),
  (key: 'other', label: 'Other', icon: Icons.more_horiz),
];

/// Thrown for any failed AI call; [message] is safe to show.
class AiCallException implements Exception {
  final String message;
  const AiCallException(this.message);
  @override
  String toString() => message;
}

/// Calls an AI callable over raw HTTPS — the same approach as ludoRollDirect,
/// which avoids the cloud_functions SDK's dart2js Int64 decoding trap.
Future<Map<String, dynamic>> callAiFunction(
  String name,
  Map<String, dynamic> data, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final token = await user?.getIdToken();
  if (token == null) throw const AiCallException('Please sign in first.');
  final http.Response res;
  try {
    res = await http
        .post(
          Uri.parse('$_kAiFunctionsBase/$name'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);
  } on TimeoutException {
    throw const AiCallException('This is taking too long. Please try again.');
  } catch (_) {
    throw const AiCallException('No connection. Check your internet.');
  }
  Map<String, dynamic>? body;
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {}
  if (res.statusCode == 200 && body?['result'] is Map) {
    return Map<String, dynamic>.from(body!['result'] as Map);
  }
  final err = body?['error'];
  final msg = err is Map ? err['message']?.toString() : null;
  throw AiCallException(
    (msg == null || msg.isEmpty || msg == 'INTERNAL')
        ? 'Something went wrong. Please try again.'
        : msg,
  );
}

/// Totals for the calculator — pure so it can be unit-tested.
class BudgetSummary {
  final int income;
  final int spent;
  final int familySize;
  const BudgetSummary(this.income, this.spent, this.familySize);

  int get left => income - spent;
  double get spentShare => income <= 0 ? 0 : spent / income;
  int get perPerson => familySize <= 0 ? spent : (spent / familySize).round();

  /// Share of income saved, 0–100, or null with no income entered.
  int? get savingsPercent =>
      income <= 0 ? null : ((left / income) * 100).round().clamp(-999, 100);
}

int parseRupees(String s) =>
    int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

class BudgetToolsScreen extends StatefulWidget {
  /// 0 = calculator, 1 = rate list.
  final int initialTab;
  const BudgetToolsScreen({super.key, this.initialTab = 0});

  @override
  State<BudgetToolsScreen> createState() => _BudgetToolsScreenState();
}

class _BudgetToolsScreenState extends State<BudgetToolsScreen> {
  String _city = kPakistanPrayerCities.first.name;

  @override
  void initState() {
    super.initState();
    _restoreCity();
  }

  Future<void> _restoreCity() async {
    try {
      final p = await SharedPreferences.getInstance();
      // Fall back to the prayer-times city: somebody who set it there has
      // already told us where they live.
      final name =
          p.getString(_kPrefToolsCity) ?? p.getString(_kPrefPrayerCity);
      if (name != null && mounted) {
        setState(() => _city = _cityByName(name).name);
      }
    } catch (_) {}
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
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
                  final c = kPakistanPrayerCities[i].name;
                  return ListTile(
                    dense: true,
                    title: Text(c),
                    trailing: c == _city
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
    if (picked == null || picked == _city) return;
    setState(() => _city = picked);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefToolsCity, picked);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Budget & Rates'),
          actions: [
            TextButton.icon(
              onPressed: _pickCity,
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: Text(_city),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.calculate_outlined),
                text: 'Budget Calculator',
              ),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Rate List'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BudgetCalculatorTab(city: _city),
            // Keyed by city so switching cities starts a fresh fetch.
            _RateListTab(key: ValueKey(_city), city: _city),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget calculator
// ---------------------------------------------------------------------------

class _BudgetCalculatorTab extends StatefulWidget {
  final String city;
  const _BudgetCalculatorTab({required this.city});

  @override
  State<_BudgetCalculatorTab> createState() => _BudgetCalculatorTabState();
}

class _BudgetCalculatorTabState extends State<_BudgetCalculatorTab>
    with AutomaticKeepAliveClientMixin {
  final _income = TextEditingController();
  final Map<String, TextEditingController> _lines = {
    for (final l in kBudgetExpenseLines) l.key: TextEditingController(),
  };
  int _family = 4;
  bool _urdu = false;
  bool _asking = false;
  Map<String, dynamic>? _advice;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _income.dispose();
    for (final c in _lines.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPrefBudget);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _income.text = (m['income'] ?? '').toString();
        _family = (m['family'] as num?)?.toInt() ?? 4;
        _urdu = m['urdu'] == true;
        final e = (m['expenses'] as Map?) ?? const {};
        for (final l in kBudgetExpenseLines) {
          _lines[l.key]!.text = (e[l.key] ?? '').toString();
        }
      });
    } catch (_) {}
  }

  /// Kept on this device only.
  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kPrefBudget,
        jsonEncode({
          'income': _income.text,
          'family': _family,
          'urdu': _urdu,
          'expenses': {for (final e in _lines.entries) e.key: e.value.text},
        }),
      );
    } catch (_) {}
  }

  BudgetSummary get _summary => BudgetSummary(
    parseRupees(_income.text),
    _lines.values.fold(0, (s, c) => s + parseRupees(c.text)),
    _family,
  );

  void _changed() {
    setState(() {});
    _save();
  }

  Future<void> _askAi() async {
    FocusScope.of(context).unfocus();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _error = 'Sign in to get AI advice on your budget.');
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final advice = await callAiFunction('aiBudgetAdvice', {
        'city': widget.city,
        'familySize': _family,
        'income': parseRupees(_income.text),
        'expenses': {
          for (final e in _lines.entries) e.key: parseRupees(e.value.text),
        },
        'lang': _urdu ? 'ur' : 'en',
      });
      if (mounted) setState(() => _advice = advice);
    } on AiCallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Widget _moneyField(TextEditingController c, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            prefixText: '$currencySymbol ',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.navClearance,
      ),
      children: [
        _summaryCard(s),
        const SizedBox(height: AppSpacing.lg),
        Text('Monthly income', style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        _moneyField(_income, 'Total household income', Icons.payments_outlined),
        Row(
          children: [
            Expanded(child: Text('Family members', style: AppType.body)),
            IconButton(
              tooltip: 'Fewer',
              onPressed: _family > 1
                  ? () {
                      _family--;
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_family', style: AppType.cardTitle),
            IconButton(
              tooltip: 'More',
              onPressed: _family < 30
                  ? () {
                      _family++;
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Monthly expenses', style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        for (final l in kBudgetExpenseLines)
          _moneyField(_lines[l.key]!, l.label, l.icon),
        const SizedBox(height: AppSpacing.md),
        _aiCard(),
      ],
    );
  }

  Widget _summaryCard(BudgetSummary s) {
    final over = s.left < 0;
    final pct = s.savingsPercent;
    return Container(
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
          Text(
            over ? 'Over budget by' : 'Left this month',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            formatPrice('${s.left.abs()}'),
            style: TextStyle(
              color: over ? const Color(0xFFFFD7D7) : Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadius.rSm,
            child: LinearProgressIndicator(
              value: s.spentShare.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white24,
              color: over ? const Color(0xFFFF8A80) : Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _stat('Income', formatPrice('${s.income}')),
              _stat('Spent', formatPrice('${s.spent}')),
              _stat('Per person', formatPrice('${s.perPerson}')),
              if (pct != null) _stat('Saving', '$pct%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _aiCard() {
    final advice = _advice;
    final tips = (advice?['tips'] as List?)?.cast<Object?>() ?? const [];
    final warnings =
        (advice?['warnings'] as List?)?.cast<Object?>() ?? const [];
    final target = (advice?['savingsTarget'] as num?)?.toInt() ?? 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: kPakGreen, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('AI budget advice', style: AppType.cardTitle),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('EN')),
                  ButtonSegment(value: true, label: Text('اردو')),
                ],
                selected: {_urdu},
                onSelectionChanged: (v) {
                  _urdu = v.first;
                  _changed();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Get tips on where to save, based on your numbers and today\'s '
            'prices in ${widget.city}.',
            style: AppType.secondary,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _asking ? null : _askAi,
              icon: _asking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_asking ? 'Reviewing your budget…' : 'Get AI advice'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: AppColors.error)),
          ],
          if (advice != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Directionality(
              textDirection: _urdu ? TextDirection.rtl : TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    advice['summary']?.toString() ?? '',
                    style: AppType.body,
                  ),
                  if (target > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '${_urdu ? 'ماہانہ بچت کا ہدف' : 'Suggested monthly saving'}: '
                      '${formatPrice('$target')}',
                      style: AppType.cardTitle.copyWith(color: kPakGreen),
                    ),
                  ],
                  for (final w in warnings)
                    _bullet(
                      w.toString(),
                      Icons.warning_amber,
                      AppColors.warning,
                    ),
                  for (final t in tips)
                    _bullet(
                      t.toString(),
                      Icons.check_circle_outline,
                      kPakGreen,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'AI suggestions — use your own judgement.',
              style: AppType.caption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bullet(String text, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppType.body)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Rate list
// ---------------------------------------------------------------------------

class _RateListTab extends StatefulWidget {
  final String city;
  const _RateListTab({super.key, required this.city});

  @override
  State<_RateListTab> createState() => _RateListTabState();
}

class _RateListTabState extends State<_RateListTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _list;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // A city nobody has opened today is researched live, which can take a
      // minute or two of web searching.
      final list = await callAiFunction('aiRateList', {
        'city': widget.city,
      }, timeout: const Duration(minutes: 4));
      if (mounted) setState(() => _list = list);
    } on AiCallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (FirebaseAuth.instance.currentUser == null) {
      return _message(Icons.lock_outline, 'Sign in to see today\'s rates.');
    }
    if (_loading && _list == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Checking today\'s prices in ${widget.city}…',
                style: AppType.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'If nobody has opened ${widget.city} today, AI searches the '
                'web for fresh prices. This can take a minute.',
                style: AppType.secondary,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final list = _list;
    if (list == null) {
      return _message(
        Icons.cloud_off,
        _error ?? 'Could not load rates.',
        retry: true,
      );
    }
    final updated = DateTime.fromMillisecondsSinceEpoch(
      (list['updatedAt'] as num?)?.toInt() ?? 0,
    );
    final cats = ((list['categories'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final q = _query.trim().toLowerCase();
    final sources = ((list['sources'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: kPakGreen),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Updated ${_ago(updated)} · researched by AI from the web',
                  style: AppType.caption,
                ),
              ),
            ],
          ),
          if ((list['summary']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Text(list['summary'].toString(), style: AppType.body),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search atta, petrol, cement…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final c in cats) ..._category(c, q),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Prices are AI estimates from news, official notifications and '
            'price sites, and vary by shop and area. Always confirm before '
            'you buy.',
            style: AppType.caption,
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Sources', style: AppType.label),
            for (final s in sources)
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(s['url'].toString()),
                  mode: LaunchMode.externalApplication,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    (s['title']?.toString().isNotEmpty ?? false)
                        ? s['title'].toString()
                        : Uri.parse(s['url'].toString()).host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(
                      color: AppColors.info,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _category(Map c, String q) {
    final items = ((c['items'] as List?) ?? const [])
        .whereType<Map>()
        .where(
          (i) => q.isEmpty || i['name'].toString().toLowerCase().contains(q),
        )
        .toList();
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.sm,
        ),
        child: Text(c['label']?.toString() ?? '', style: AppType.sectionTitle),
      ),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _itemRow(items[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _itemRow(Map i) {
    final low = (i['low'] as num?)?.toInt() ?? 0;
    final high = (i['high'] as num?)?.toInt() ?? low;
    final unit = i['unit']?.toString() ?? '';
    final note = i['note']?.toString() ?? '';
    final price = low == high
        ? formatPrice('$low')
        : '${formatPrice('$low')} – ${formatPrice('$high').replaceFirst('$currencySymbol ', '')}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i['name']?.toString() ?? '', style: AppType.body),
                if (unit.isNotEmpty) Text(unit, style: AppType.caption),
                if (note.isNotEmpty) Text(note, style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(price, style: AppType.price.copyWith(fontSize: 15)),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  Widget _message(IconData icon, String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(text, style: AppType.body, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
