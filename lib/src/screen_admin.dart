part of '../main.dart';

// Admin panel and its tabs.

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Refresh permissions each time the panel opens so a staff member's tabs
    // reflect the latest grants (and aren't empty due to a cold-start race
    // where the panel is opened before the startup load finishes).
    return FutureBuilder<void>(
      future: loadStaffPermissions().then((_) => syncSupportPushToken()),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin Panel')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _buildPanel(context);
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    // Each entry: (permission code | '__super' for super-admin-only, title, tab).
    // Staff see only the tabs they've been granted; the super admin sees all.
    const entries = <(String, String, Widget)>[
      ('__super', 'Overview', _AdminOverviewTab()),
      ('__super', 'Staff', _AdminStaffTab()),
      ('activity', 'Activity', _AdminActivityTab()),
      ('approvals', 'Approvals', _AdminApprovalsTab()),
      ('verifyId', 'Verify ID', _AdminVerificationsTab()),
      ('businessVerify', 'Business', _AdminBusinessTab()),
      ('payments', 'Payments', _AdminPaymentsTab()),
      ('payments', 'Payout a/c', _AdminPayoutAccountsTab()),
      ('escrow', 'Escrow', _AdminEscrowTab()),
      ('featured', 'Featured', _AdminFeaturedTab()),
      ('feedback', 'Feedback', _AdminFeedbackTab()),
      ('support', 'Customer Care', _AdminSupportTab()),
      ('users', 'Users', _AdminUsersTab()),
      ('reports', 'Reports', _AdminReportsTab()),
      ('topups', 'Top-ups', _AdminTopupsTab()),
      ('paymentAccount', 'Payment a/c', _AdminPaymentTab()),
      ('withdrawals', 'Withdrawals', _AdminWithdrawalsTab()),
      ('promotions', 'Promotions', _AdminPromotionsTab()),
      ('orders', 'Orders', _AdminOrdersTab()),
      ('offers', 'Offers', _AdminOffersTab()),
      ('purchases', 'Purchases', _AdminPurchasesTab()),
      ('listings', 'Listings', _AdminListingsTab()),
      ('chats', 'Chats', _AdminChatsTab()),
      ('appeals', 'Appeals', _AdminAppealsTab()),
      ('deletions', 'Deletions', _AdminDeletionsTab()),
      ('__super', 'Lucky Draw', _AdminLuckyDrawTab()),
    ];
    final visible = entries.where((e) {
      return e.$1 == '__super' ? isSuperAdmin() : hasAdminPerm(e.$1);
    }).toList();

    if (visible.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'No access',
          subtitle: 'You have no admin permissions assigned.',
        ),
      );
    }

    return DefaultTabController(
      length: visible.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isSuperAdmin() ? 'Admin Panel' : 'Staff Panel'),
          actions: const [AdminLiveUsersPill()],
          bottom: TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: [
              for (final e in visible)
                e.$1 == 'support' ? _SupportTabLabel(e.$2) : Tab(text: e.$2),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(children: [for (final e in visible) e.$3]),
            // Invisible: pops a snackbar on new user support messages.
            const SupportAlertWatcher(),
          ],
        ),
      ),
    );
  }
}

Future<void> _openListingById(BuildContext context, String id) async {
  final doc = await FirebaseFirestore.instance
      .collection('listings')
      .doc(id)
      .get();
  if (!context.mounted) return;
  if (!doc.exists) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('That ad no longer exists.')));
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AdDetailsScreen(listing: Listing.fromDoc(doc)),
    ),
  );
}

class _Metric {
  final String value;
  final String label;
  const _Metric(this.value, this.label);
}

/// Platform-wide activity monitor. A read-only, filterable feed over the
/// server-written `financialAuditLog` (orders, offers, payments, refunds,
/// cancellations, returns, payouts, disputes) so admins can see everything
/// that happens between buyers and sellers and step in via the Orders/Escrow
/// tabs when there's a misunderstanding.
class _AdminActivityTab extends StatefulWidget {
  const _AdminActivityTab();

  @override
  State<_AdminActivityTab> createState() => _AdminActivityTabState();
}

class _AdminActivityTabState extends State<_AdminActivityTab> {
  String _filter = 'All';

  static const List<String> _filters = [
    'All',
    'Orders',
    'Offers',
    'Payments',
    'Refunds',
    'Cancellations',
    'Payouts',
    'Disputes',
  ];

  bool _matches(String action, String entityType) {
    final a = action.toLowerCase();
    final e = entityType.toLowerCase();
    switch (_filter) {
      case 'Orders':
        return e == 'order' || a.contains('order');
      case 'Offers':
        return e == 'offer' || a.contains('offer');
      case 'Payments':
        return a.contains('payment') ||
            a.contains('escrow') ||
            a.contains('held') ||
            a.contains('release') ||
            a.contains('confirm');
      case 'Refunds':
        return a.contains('refund');
      case 'Cancellations':
        return a.contains('cancel') || a.contains('return');
      case 'Payouts':
        return e == 'withdrawal' ||
            a.contains('payout') ||
            a.contains('withdrawal');
      case 'Disputes':
        return e == 'dispute' || a.contains('dispute');
      case 'All':
      default:
        return true;
    }
  }

  static String _humanAction(String a) => a.isEmpty
      ? 'Activity'
      : a
            .split('_')
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');

  static (IconData, Color) _visual(String action) {
    final a = action.toLowerCase();
    if (a.contains('dispute')) return (Icons.gavel, AppColors.warning);
    if (a.contains('refund') ||
        a.contains('reject') ||
        a.contains('hold') ||
        a.contains('cancel') ||
        a.contains('return')) {
      return (Icons.undo, AppColors.error);
    }
    if (a.contains('paid') ||
        a.contains('release') ||
        a.contains('confirm') ||
        a.contains('held') ||
        a.contains('payout')) {
      return (Icons.check_circle, AppColors.success);
    }
    if (a.contains('offer')) return (Icons.local_offer, AppColors.info);
    if (a.contains('order')) {
      return (Icons.shopping_bag, const Color(0xFF3949AB));
    }
    if (a.contains('withdrawal')) {
      return (Icons.account_balance_wallet, const Color(0xFF00897B));
    }
    return (Icons.history, AppColors.textMuted);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('financialAuditLog')
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.where((d) {
                final m = d.data() as Map<String, dynamic>;
                return _matches(
                  m['action']?.toString() ?? '',
                  m['entityType']?.toString() ?? '',
                );
              }).toList();
              if (docs.isEmpty) {
                return EmptyState(
                  icon: Icons.timeline,
                  title: 'No activity',
                  subtitle: _filter == 'All'
                      ? 'Platform activity will appear here as it happens.'
                      : 'No $_filter activity in the recent feed.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data() as Map<String, dynamic>;
                  return _activityCard(context, m);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _activityCard(BuildContext context, Map<String, dynamic> m) {
    final action = m['action']?.toString() ?? '';
    final entityType = m['entityType']?.toString() ?? '';
    final entityId = m['entityId']?.toString() ?? '';
    final prev = m['previousStatus']?.toString() ?? '';
    final next = m['newStatus']?.toString() ?? '';
    final actorRole = m['actorRole']?.toString() ?? '';
    final amount = (m['amount'] as num?)?.toDouble() ?? 0;
    final reason = m['reason']?.toString() ?? '';
    final meta = (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final listingId = meta['listingId']?.toString() ?? '';
    final (icon, color) = _visual(action);

    final shortId = entityId.length > 8 ? entityId.substring(0, 8) : entityId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showDetail(context, m),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _humanAction(action),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (amount > 0)
                          Text(
                            formatPrice(amount.toStringAsFixed(0)),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$entityType · #$shortId'
                      '${actorRole.isNotEmpty ? ' · by $actorRole' : ''}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (prev.isNotEmpty || next.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          prev.isNotEmpty ? '$prev → $next' : 'set to $next',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          reason,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          timeAgo(m['createdAt'] as Timestamp?),
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        if (listingId.isNotEmpty) ...[
                          const Spacer(),
                          InkWell(
                            onTap: () => _openListingById(context, listingId),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.open_in_new,
                                  size: 14,
                                  color: AppColors.link,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Open ad',
                                  style: TextStyle(
                                    color: AppColors.link,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> m) {
    final meta = (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    String row(String k, Object? v) =>
        (v == null || '$v'.isEmpty) ? '' : '$k: $v\n';
    final buf = StringBuffer()
      ..write(row('Action', m['action']))
      ..write(row('Type', m['entityType']))
      ..write(row('Entity', m['entityId']))
      ..write(row('Actor', m['actorId']))
      ..write(row('Actor role', m['actorRole']))
      ..write(row('From', m['previousStatus']))
      ..write(row('To', m['newStatus']))
      ..write(
        row(
          'Amount',
          (m['amount'] as num?) == null
              ? ''
              : formatPrice((m['amount'] as num).toStringAsFixed(0)),
        ),
      )
      ..write(row('Reason', m['reason']));
    for (final e in meta.entries) {
      buf.write(row(e.key, e.value));
    }
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Activity detail'),
        content: SingleChildScrollView(child: Text(buf.toString().trimRight())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Manual payments awaiting confirmation: the buyer transferred to the platform
/// receiving account and submitted proof. The admin checks the bank/wallet,
/// then confirms (order -> escrow) or rejects (order back to payable). The
/// money movement happens server-side in onPaymentAction.
class _AdminPaymentsTab extends StatelessWidget {
  const _AdminPaymentsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'awaiting_confirmation')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.payments,
            title: 'No payments to confirm',
            subtitle: 'Buyer payments awaiting your confirmation appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final amount = (d['amount'] as num?)?.toDouble() ?? 0;
            final from = (d['proofFrom']?.toString() ?? '').trim();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPrice(amount.toStringAsFixed(0)),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      d['listingTitle']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      d['buyerEmail']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      'Reference: ${d['proofRef'] ?? ''}'
                      '${from.isEmpty ? '' : '\nPaid from: $from'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _PaymentConfirmActions(paymentId: docs[i].id),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PaymentConfirmActions extends StatefulWidget {
  const _PaymentConfirmActions({required this.paymentId});

  final String paymentId;

  @override
  State<_PaymentConfirmActions> createState() => _PaymentConfirmActionsState();
}

class _PaymentConfirmActionsState extends State<_PaymentConfirmActions> {
  bool busy = false;

  Future<void> _act(String type) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await FirebaseFirestore.instance.collection('paymentActions').add({
        'paymentId': widget.paymentId,
        'type': type,
        'by': FirebaseAuth.instance.currentUser?.uid ?? '',
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: busy ? null : () => _act('reject'),
          child: const Text('Reject'),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: busy ? null : () => _act('confirm'),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm payment'),
        ),
      ],
    );
  }
}

/// Featuring control centre: a master on/off switch for the whole featuring
/// system (config/featuring), plus lists of currently featured ads and
/// businesses that can each be turned off directly.
class _AdminFeaturedTab extends StatelessWidget {
  const _AdminFeaturedTab();

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: StreamBuilder<DocumentSnapshot>(
            stream: fs.collection('config').doc('featuring').snapshots(),
            builder: (context, snap) {
              final enabled =
                  (snap.data?.data() as Map<String, dynamic>?)?['enabled'] !=
                  false;
              return SwitchListTile(
                title: const Text(
                  'Featuring system',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  enabled
                      ? 'ON — featured ads & businesses show on the home screen'
                      : 'OFF — featured sections are hidden on the home screen',
                ),
                value: enabled,
                activeThumbColor: kPakGreen,
                onChanged: (v) {
                  fs.collection('config').doc('featuring').set({
                    'enabled': v,
                  }, SetOptions(merge: true));
                  featuringEnabled.value = v;
                },
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            'Featured ads',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: fs
              .collection('listings')
              .where('isFeatured', isEqualTo: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No featured ads.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final l = Listing.fromDoc(doc);
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.star, color: kGold),
                    title: Text(
                      l.title.isEmpty ? '(untitled)' : l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${formatPrice(l.price)} · ${l.sellerName}'),
                    trailing: TextButton(
                      onPressed: () =>
                          doc.reference.update({'isFeatured': false}),
                      child: const Text('Turn off'),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            'Featured businesses',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: fs
              .collection('users')
              .where('featuredBusiness', isEqualTo: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No featured businesses.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name = (d['businessName']?.toString() ?? '').isNotEmpty
                    ? d['businessName'].toString()
                    : (d['email']?.toString() ?? 'Business');
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.storefront, color: kGold),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          doc.reference.update({'featuredBusiness': false}),
                      child: const Text('Turn off'),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

/// Funds currently held in escrow (paid orders awaiting release). The admin
/// releases the payout to the seller's wallet or refunds the buyer; the actual
/// money movement happens server-side in the onEscrowAction Cloud Function.
class _AdminEscrowTab extends StatelessWidget {
  const _AdminEscrowTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('status', isEqualTo: 'in_escrow')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.lock_clock,
            title: 'No funds in escrow',
            subtitle: 'Paid orders awaiting release appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) => _PayoutReviewCard(
            orderId: docs[i].id,
            data: docs[i].data() as Map<String, dynamic>,
          ),
        );
      },
    );
  }
}

/// Full payout-verification card for one held order (spec section 5). Shows the
/// server-authoritative money breakdown, the live pre-release checklist, and the
/// admin actions (release / hold / reject / refund). Every action is written to
/// `escrowActions` and applied server-side by onEscrowAction — the client never
/// moves money. Release requires an explicit confirmation dialog.
class _PayoutReviewCard extends StatefulWidget {
  const _PayoutReviewCard({required this.orderId, required this.data});

  final String orderId;
  final Map<String, dynamic> data;

  @override
  State<_PayoutReviewCard> createState() => _PayoutReviewCardState();
}

class _PayoutReviewCardState extends State<_PayoutReviewCard> {
  bool busy = false;

  // ---- live pre-release checks -------------------------------------------
  bool? _disputeOpen; // null while loading
  bool? _accountVerified;

  @override
  void initState() {
    super.initState();
    _loadChecks();
  }

  Future<void> _loadChecks() async {
    final fs = FirebaseFirestore.instance;
    final orderId = widget.orderId;
    final sellerId = widget.data['sellerId']?.toString() ?? '';
    try {
      final disp = await fs
          .collection('disputes')
          .where('orderId', isEqualTo: orderId)
          .get();
      final open = disp.docs.any(
        (d) => (d.data()['status']?.toString() ?? 'open') == 'open',
      );
      bool verified = false;
      if (sellerId.isNotEmpty) {
        final v = await fs
            .collection('users')
            .doc(sellerId)
            .collection('payoutAccounts')
            .where('verificationStatus', isEqualTo: 'verified')
            .limit(1)
            .get();
        verified = v.docs.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _disputeOpen = open;
        _accountVerified = verified;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _disputeOpen = false;
        _accountVerified = false;
      });
    }
  }

  double get _amount => (widget.data['amount'] as num?)?.toDouble() ?? 0;
  double get _delivery => (widget.data['deliveryFee'] as num?)?.toDouble() ?? 0;
  double get _subtotal =>
      (widget.data['itemSubtotal'] as num?)?.toDouble() ??
      (_amount - _delivery);
  double get _commission =>
      (widget.data['platformCommissionAmount'] as num?)?.toDouble() ??
      (widget.data['commission'] as num?)?.toDouble() ??
      (_subtotal * commissionRate);
  double get _refundedAmount =>
      (widget.data['refundAmount'] as num?)?.toDouble() ?? 0;
  double get _payable =>
      (widget.data['sellerPayableAmount'] as num?)?.toDouble() ??
      (_amount - _commission - _refundedAmount);
  bool get _buyerConfirmed => widget.data['buyerConfirmed'] == true;

  bool get _canRelease =>
      !busy &&
      _buyerConfirmed &&
      _disputeOpen == false &&
      _accountVerified == true &&
      _payable > 0;

  Future<void> _queue(
    String type, {
    Map<String, dynamic> extra = const {},
  }) async {
    if (busy) return;
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('escrowActions').add({
        'orderId': widget.orderId,
        'type': type,
        'by': FirebaseAuth.instance.currentUser?.uid ?? '',
        'status': 'pending',
        'createdAt': Timestamp.now(),
        ...extra,
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Payout $type queued — applying…')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirmRelease() async {
    final txn = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Release payout to seller?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PakBazar will pay ${formatPrice(_payable.toStringAsFixed(0))} '
              'to the seller (commission '
              '${formatPrice(_commission.toStringAsFixed(0))} retained). '
              'This cannot be undone.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: txn,
              decoration: const InputDecoration(
                labelText: 'Transaction reference (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _queue(
        'release',
        extra: {
          if (txn.text.trim().isNotEmpty)
            'transactionReference': txn.text.trim(),
        },
      );
    }
    txn.dispose();
  }

  Future<void> _reasonAction(String type, String title) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _queue(type, extra: {'reason': reason.text.trim()});
    }
    reason.dispose();
  }

  Future<void> _refundBuyer() async {
    final amt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Refund buyer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave blank for a FULL refund of '
              '${formatPrice(_amount.toStringAsFixed(0))}, or enter a partial '
              'amount.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amt,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Partial amount (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final partial = double.tryParse(
        amt.text.replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      await _queue(
        'refund',
        extra: {if (partial != null && partial > 0) 'refundAmount': partial},
      );
    }
    amt.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d['listingTitle']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Order ${widget.orderId}',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              'Buyer: ${d['buyerName'] ?? ''}   ·   Seller: ${d['sellerName'] ?? ''}',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const Divider(height: 16),
            _row('Item subtotal', _subtotal),
            _row('Delivery fee', _delivery),
            _row('Platform commission', -_commission),
            if (_refundedAmount > 0) _row('Refunded', -_refundedAmount),
            _row('Seller payable', _payable, bold: true),
            const SizedBox(height: 8),
            // Pre-release checklist.
            _check('Buyer confirmed delivery', _buyerConfirmed),
            _check(
              'No open dispute',
              _disputeOpen == false,
              loading: _disputeOpen == null,
            ),
            _check(
              'Seller has a verified payout account',
              _accountVerified == true,
              loading: _accountVerified == null,
            ),
            _check('Seller payable is greater than zero', _payable > 0),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: busy ? null : _refundBuyer,
                  child: const Text('Refund'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _reasonAction('reject', 'Reject payout'),
                  child: const Text('Reject'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _reasonAction('hold', 'Hold payout'),
                  child: const Text('Hold'),
                ),
                ElevatedButton(
                  onPressed: _canRelease ? _confirmRelease : null,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Release to seller'),
                ),
              ],
            ),
            if (!_canRelease && !busy)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Release is enabled only when every check above passes.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, double v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          k,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          formatPrice(v.toStringAsFixed(0)),
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: bold ? kPakGreen : null,
          ),
        ),
      ],
    ),
  );

  Widget _check(String label, bool ok, {bool loading = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 15,
            color: ok ? AppColors.success : AppColors.error,
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: loading
                  ? AppColors.textMuted
                  : (ok ? AppColors.success : AppColors.error),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Edits the platform's receiving account (bank / JazzCash / EasyPaisa) shown
/// to users on the wallet top-up sheet. Stored at config/paymentAccount.
class _AdminPaymentTab extends StatelessWidget {
  const _AdminPaymentTab();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(14),
      child: _PaymentAccountEditor(),
    );
  }
}

class _PaymentAccountEditor extends StatefulWidget {
  const _PaymentAccountEditor();

  @override
  State<_PaymentAccountEditor> createState() => _PaymentAccountEditorState();
}

class _PaymentAccountEditorState extends State<_PaymentAccountEditor> {
  final bankName = TextEditingController();
  final accountTitle = TextEditingController();
  final accountNumber = TextEditingController();
  final iban = TextEditingController();
  final jazzCash = TextEditingController();
  final easyPaisa = TextEditingController();
  final note = TextEditingController();
  bool loaded = false;
  bool saving = false;

  DocumentReference get _ref =>
      FirebaseFirestore.instance.collection('config').doc('paymentAccount');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await _ref.get();
    final d = doc.data() as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      bankName.text = d?['bankName']?.toString() ?? '';
      accountTitle.text = d?['accountTitle']?.toString() ?? '';
      accountNumber.text = d?['accountNumber']?.toString() ?? '';
      iban.text = d?['iban']?.toString() ?? '';
      jazzCash.text = d?['jazzCash']?.toString() ?? '';
      easyPaisa.text = d?['easyPaisa']?.toString() ?? '';
      note.text = d?['note']?.toString() ?? '';
      loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await _ref.set({
        'bankName': bankName.text.trim(),
        'accountTitle': accountTitle.text.trim(),
        'accountNumber': accountNumber.text.trim(),
        'iban': iban.text.trim(),
        'jazzCash': jazzCash.text.trim(),
        'easyPaisa': easyPaisa.text.trim(),
        'note': note.text.trim(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receiving account saved')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    bankName.dispose();
    accountTitle.dispose();
    accountNumber.dispose();
    iban.dispose();
    jazzCash.dispose();
    easyPaisa.dispose();
    note.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {TextInputType? kb}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        enabled: loaded,
        keyboardType: kb,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Receiving account',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Shown to users on the wallet top-up sheet so they know where to '
          'send payment. Leave a field blank to hide it.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _field(bankName, 'Bank name'),
        _field(accountTitle, 'Account title'),
        _field(accountNumber, 'Account number', kb: TextInputType.number),
        _field(iban, 'IBAN (optional)'),
        _field(jazzCash, 'JazzCash number', kb: TextInputType.phone),
        _field(easyPaisa, 'EasyPaisa number', kb: TextInputType.phone),
        _field(note, 'Note / instructions (optional)'),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(saving ? 'Saving…' : 'Save receiving account'),
          ),
        ),
      ],
    );
  }
}

/// Seller withdrawal requests awaiting payout. The admin sends money to the
/// seller's account off-platform, then marks it paid (or rejects -> refunds
/// the reserved amount to the seller's wallet via onWithdrawalAction).
class _AdminWithdrawalsTab extends StatelessWidget {
  const _AdminWithdrawalsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: 'processing')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.account_balance,
            title: 'No withdrawals pending',
            subtitle: 'Seller payout requests appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final amount = (d['amount'] as num?)?.toDouble() ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPrice(amount.toStringAsFixed(0)),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      d['userEmail']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      'Pay to: ${d['payoutBank'] ?? ''}\n'
                      'Title: ${d['payoutTitle'] ?? ''}\n'
                      'Number: ${d['payoutNumber'] ?? ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _WithdrawalActions(withdrawalId: docs[i].id),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Mark paid / reject buttons for one withdrawal. Stateful so both disable
/// while the instruction is written (the Cloud Function also guards on status,
/// so it stays idempotent).
class _WithdrawalActions extends StatefulWidget {
  const _WithdrawalActions({required this.withdrawalId});

  final String withdrawalId;

  @override
  State<_WithdrawalActions> createState() => _WithdrawalActionsState();
}

class _WithdrawalActionsState extends State<_WithdrawalActions> {
  bool busy = false;

  Future<void> _act(String type) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await FirebaseFirestore.instance.collection('withdrawalActions').add({
        'withdrawalId': widget.withdrawalId,
        'type': type,
        'by': FirebaseAuth.instance.currentUser?.uid ?? '',
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: busy ? null : () => _act('rejected'),
          child: const Text('Reject'),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: busy ? null : () => _act('paid'),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mark paid'),
        ),
      ],
    );
  }
}

/// Support requests and suggestions sent from the Help & Feedback sheet.
class _AdminFeedbackTab extends StatelessWidget {
  const _AdminFeedbackTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.feedback_outlined,
            title: 'No messages yet',
            subtitle: 'Help requests and suggestions appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final type = d['type']?.toString() ?? 'Help';
            final email = d['email']?.toString() ?? '';
            final msg = d['message']?.toString() ?? '';
            final resolved = (d['status']?.toString() ?? 'open') == 'resolved';
            final isSuggestion = type == 'Suggestion';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSuggestion
                              ? Icons.lightbulb_outline
                              : Icons.help_outline,
                          size: 18,
                          color: isSuggestion ? kGold : kPakGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (resolved)
                          const Text(
                            'Resolved',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    if (email.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          email,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(msg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (email.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'mailto:$email?subject='
                                '${Uri.encodeComponent('Re: PakBazar $type')}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.reply, size: 18),
                            label: const Text('Reply'),
                          ),
                        if (!resolved)
                          TextButton(
                            onPressed: () => docs[i].reference.update({
                              'status': 'resolved',
                            }),
                            child: const Text('Mark resolved'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Admin face-match review: compare the selfie to the CNIC and approve/reject.
class _AdminVerificationsTab extends StatelessWidget {
  const _AdminVerificationsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _VerificationToggle(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('verifications')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final am = a.data() as Map;
                  final bm = b.data() as Map;
                  final ap = am['status'] == 'pending' ? 0 : 1;
                  final bp = bm['status'] == 'pending' ? 0 : 1;
                  if (ap != bp) return ap - bp;
                  final at =
                      (am['submittedAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final bt =
                      (bm['submittedAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  return bt.compareTo(at);
                });
              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.verified_user,
                  title: 'No verification requests',
                  subtitle: 'Selfie + CNIC submissions appear here for review.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final status = d['status']?.toString() ?? 'pending';
                  final pending = status == 'pending';
                  final uid = d['userId']?.toString() ?? docs[i].id;
                  final selfie = d['selfieUrl']?.toString() ?? '';
                  final cnic = d['cnicUrl']?.toString() ?? '';
                  final address = d['address']?.toString() ?? '';
                  final proof = d['addressProofUrl']?.toString() ?? '';
                  Widget img(String url) => Expanded(
                    child: GestureDetector(
                      onTap: url.isEmpty
                          ? null
                          : () {
                              final gallery = [
                                selfie,
                                cnic,
                              ].where((u) => u.isNotEmpty).toList();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenGallery(
                                    images: gallery,
                                    initialIndex: gallery.indexOf(url),
                                  ),
                                ),
                              );
                            },
                      child: Container(
                        height: 110,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          image: url.isEmpty
                              ? null
                              : DecorationImage(
                                  image: NetworkImage(url),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                    ),
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['email']?.toString() ?? uid,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Status: $status',
                            style: TextStyle(
                              color: pending
                                  ? Colors.orange
                                  : (status == 'approved'
                                        ? Colors.green
                                        : Colors.red),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [img(selfie), img(cnic)]),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Selfie  ·  CNIC  (tap to enlarge)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.home_outlined,
                                size: 16,
                                color: kPakGreen,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  address.isEmpty
                                      ? '(no address provided)'
                                      : address,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          if (proof.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FullScreenGallery(images: [proof]),
                                ),
                              ),
                              child: Container(
                                height: 90,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: NetworkImage(proof),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Address proof (tap to enlarge)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                          if (pending)
                            _VerificationActions(
                              uid: uid,
                              ref: docs[i].reference,
                              address: address,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Admin switch for whether ID/face verification is required platform-wide.
/// Writes config/verification {required: bool}; the app gates posting/buying/
/// chatting on it (see verificationRequired / firestore.rules isVerifiedUser).
class _VerificationToggle extends StatelessWidget {
  const _VerificationToggle();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('config')
        .doc('verification');
    return StreamBuilder<DocumentSnapshot>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final on =
            (snap.data?.data() as Map<String, dynamic>?)?['required'] == true;
        return Card(
          margin: const EdgeInsets.all(12),
          color: on ? null : const Color(0xFFFFF3CD),
          child: SwitchListTile(
            secondary: Icon(
              on ? Icons.verified_user : Icons.lock_open,
              color: on ? kPakGreen : Colors.orange,
            ),
            title: const Text('Require ID & face verification'),
            subtitle: Text(
              on
                  ? 'ON — users must verify before posting, buying, offers or chat.'
                  : 'OFF — anyone can post, buy, make offers and chat without verifying.',
            ),
            value: on,
            onChanged: (v) => ref.set({'required': v}, SetOptions(merge: true)),
          ),
        );
      },
    );
  }
}

/// Approve / reject buttons for a pending verification. Stateful so both
/// buttons disable while the decision is being written — avoids a double-tap
/// applying the change twice and sending duplicate notifications.
class _VerificationActions extends StatefulWidget {
  const _VerificationActions({
    required this.uid,
    required this.ref,
    this.address = '',
  });

  final String uid;
  final DocumentReference ref;
  final String address;

  @override
  State<_VerificationActions> createState() => _VerificationActionsState();
}

class _VerificationActionsState extends State<_VerificationActions> {
  bool busy = false;

  Future<void> _decide(bool approve) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final users = FirebaseFirestore.instance.collection('users');
      await users.doc(widget.uid).set({
        'idVerified': approve,
        'addressVerified': approve,
        // Store the approved address on the profile (visible to admins).
        if (approve && widget.address.isNotEmpty) 'address': widget.address,
      }, SetOptions(merge: true));
      await users
          .doc(widget.uid)
          .collection('notifications')
          .add(
            approve
                ? {
                    'title': 'Identity & address verified ✓',
                    'body':
                        'You can now post ads, buy, make offers and chat on '
                        'PakBazar.',
                    'type': 'verification',
                    'read': false,
                    'createdAt': Timestamp.now(),
                  }
                : {
                    'title': 'Verification needs another try',
                    'body':
                        'Please re-upload a clear selfie and CNIC photo, then '
                        'resubmit.',
                    'type': 'verification',
                    'read': false,
                    'createdAt': Timestamp.now(),
                  },
          );
      await widget.ref.update({
        'status': approve ? 'approved' : 'rejected',
        'reviewedAt': Timestamp.now(),
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: busy ? null : () => _decide(false),
          child: const Text('Reject'),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: busy ? null : () => _decide(true),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve'),
        ),
      ],
    );
  }
}

/// Platform-wide inspection dashboard: live counts and money across the app.
/// Live snapshot at the top of the Overview: how many users are online right
/// now, plus whether Customer Care itself is staffed/online.
class _LiveUsersCard extends StatelessWidget {
  const _LiveUsersCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            OnlineUsersCount(
              builder: (context, onlineCount) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: kOnlineGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$onlineCount',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: kPakGreen,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Users online now',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Customer Care',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                PresenceStatusLine(
                  kSupportPresenceId,
                  onlinePrefix: 'Support is',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOverviewTab extends StatelessWidget {
  const _AdminOverviewTab();

  Widget _section(
    String title,
    Stream<QuerySnapshot> stream,
    List<_Metric> Function(List<QueryDocumentSnapshot>) compute,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final metrics = snapshot.hasData ? compute(snapshot.data!.docs) : null;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                if (metrics == null)
                  const Center(child: CircularProgressIndicator())
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: metrics
                        .map(
                          (m) => SizedBox(
                            width: 100,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.value,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: kPakGreen,
                                  ),
                                ),
                                Text(
                                  m.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A 6-month trend card: buckets each doc's [valueOf] into the month of its
  /// completedAt/createdAt and draws a bar per month.
  Widget _trendCard(
    String title,
    Stream<QuerySnapshot> stream,
    double Function(Map<String, dynamic>) valueOf, {
    bool money = false,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final months = [
          for (int i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
        ];
        final buckets = {for (final m in months) '${m.year}-${m.month}': 0.0};
        if (snapshot.hasData) {
          for (final d in snapshot.data!.docs) {
            final m = d.data() as Map<String, dynamic>;
            final v = valueOf(m);
            if (v == 0) continue;
            final ts = (m['completedAt'] ?? m['createdAt']) as Timestamp?;
            if (ts == null) continue;
            final dt = ts.toDate();
            final key = '${dt.year}-${dt.month}';
            if (buckets.containsKey(key)) buckets[key] = buckets[key]! + v;
          }
        }
        final maxV = buckets.values.fold<double>(0, (a, b) => b > a ? b : a);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final mth in months)
                    _MonthBar(
                      label: monthShortLabel(mth),
                      value: buckets['${mth.year}-${mth.month}'] ?? 0,
                      max: maxV,
                      money: money,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _VerificationToggle(),
        const _LiveUsersCard(),
        _section('Users', fs.collection('users').snapshots(), (docs) {
          int business = 0;
          num float = 0;
          for (final d in docs) {
            final m = d.data() as Map;
            if (m['isBusiness'] == true) business++;
            float += (m['walletBalance'] as num?) ?? 0;
          }
          return [
            _Metric('${docs.length}', 'Total users'),
            _Metric('$business', 'Businesses'),
            _Metric(formatPrice('${float.toInt()}'), 'Wallet float'),
          ];
        }),
        _section('Listings', fs.collection('listings').snapshots(), (docs) {
          int featured = 0, sold = 0;
          for (final d in docs) {
            final m = d.data() as Map;
            if (m['isFeatured'] == true) featured++;
            if (m['isSold'] == true) sold++;
          }
          return [
            _Metric('${docs.length}', 'Total ads'),
            _Metric('$featured', 'Featured'),
            _Metric('$sold', 'Sold'),
          ];
        }),
        // Platform owner's revenue: the 2% commission on every released escrow
        // deal accrues to you (it's the gap between what the buyer paid and the
        // seller payout). With PayFast wired, it settles into your merchant
        // account automatically; here it's the running total you've earned.
        _section(
          'Escrow & your earnings',
          fs.collection('orders').snapshots(),
          (docs) {
            int inEscrow = 0, settled = 0;
            num held = 0, gmv = 0, earnings = 0;
            for (final d in docs) {
              final m = d.data() as Map;
              final amt = (m['amount'] as num?) ?? 0;
              switch (m['status']) {
                case 'in_escrow':
                  inEscrow++;
                  held += amt;
                case 'released' || 'completed': // 'completed' = legacy orders
                  settled++;
                  gmv += amt;
                  earnings +=
                      (m['commission'] as num?) ?? (amt * commissionRate);
              }
            }
            return [
              _Metric('$settled', 'Deals done'),
              _Metric(formatPrice('${gmv.toInt()}'), 'GMV'),
              _Metric(formatPrice('${earnings.toInt()}'), 'Your earnings (2%)'),
              _Metric('$inEscrow', 'In escrow'),
              _Metric(formatPrice('${held.toInt()}'), 'Held now'),
            ];
          },
        ),
        _section(
          'Negotiation & purchases',
          fs.collection('offers').snapshots(),
          (docs) {
            return [_Metric('${docs.length}', 'Total offers')];
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(
            'Trends — last 6 months',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        _trendCard(
          'GMV (sales value)',
          fs.collection('orders').snapshots(),
          (m) => (m['status'] == 'released' || m['status'] == 'completed')
              ? (((m['amount'] as num?)?.toDouble()) ?? 0.0)
              : 0.0,
          money: true,
        ),
        _trendCard(
          'Your earnings (2% commission)',
          fs.collection('orders').snapshots(),
          (m) {
            if (m['status'] != 'released' && m['status'] != 'completed') {
              return 0.0;
            }
            final amt = ((m['amount'] as num?)?.toDouble()) ?? 0.0;
            return ((m['commission'] as num?)?.toDouble()) ??
                amt * commissionRate;
          },
          money: true,
        ),
        _trendCard('New users', fs.collection('users').snapshots(), (m) => 1.0),
        _trendCard(
          'New ads',
          fs.collection('listings').snapshots(),
          (m) => 1.0,
        ),
        _trendCard(
          'Orders placed',
          fs.collection('orders').snapshots(),
          (m) => 1.0,
        ),
      ],
    );
  }
}

/// Admin → send a free-text instruction (type 'admin') or a rule-violation
/// warning (type 'warning') to a user; it lands in their notifications feed.
Future<void> _sendUserNotice(
  BuildContext context,
  String uid,
  String name, {
  required bool warning,
}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(warning ? 'Issue a warning to $name' : 'Message $name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: warning
              ? 'Describe the rule violation and what they must do…'
              : 'Type your instruction or message…',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(warning ? 'Send warning' : 'Send'),
        ),
      ],
    ),
  );
  final text = controller.text.trim();
  controller.dispose();
  if (ok != true) return;
  if (text.isEmpty) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .add({
        'title': warning
            ? '⚠️ Warning from PakBazar'
            : '📢 Message from PakBazar admin',
        'body': text,
        'type': warning ? 'warning' : 'admin',
        'read': false,
        'createdAt': Timestamp.now(),
      });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          warning ? 'Warning sent to $name' : 'Message sent to $name',
        ),
      ),
    );
  }
}

/// Admin → suspend (block) or reinstate (unblock) a user platform-wide. Sets
/// the `blocked` flag on their profile (enforced by Firestore rules + AuthGate)
/// and notifies them of the decision.
Future<void> _toggleUserBlock(
  BuildContext context,
  DocumentReference ref,
  String name,
  bool currentlyBlocked,
) async {
  final block = !currentlyBlocked;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(block ? 'Block $name?' : 'Unblock $name?'),
      content: block
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'They will be signed out and cannot post, buy, make offers '
                  'or chat until unblocked.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Reason (shown to the user)…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            )
          : const Text('They will regain full access to the platform.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: block ? Colors.red : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(block ? 'Block' : 'Unblock'),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  controller.dispose();
  if (ok != true) return;
  await ref.update({
    'blocked': block,
    'blockedAt': block ? Timestamp.now() : FieldValue.delete(),
  });
  await ref.collection('notifications').add({
    'title': block
        ? '⛔ Your account has been suspended'
        : '✅ Your account has been restored',
    'body': block
        ? (reason.isEmpty
              ? 'An administrator has suspended your account for violating '
                    'PakBazar rules.'
              : 'Suspended for: $reason')
        : 'Your account has been reinstated. Welcome back!',
    'type': block ? 'warning' : 'admin',
    'read': false,
    'createdAt': Timestamp.now(),
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          block ? '$name has been blocked' : '$name has been unblocked',
        ),
      ),
    );
  }
}

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final isBusiness = d['isBusiness'] == true;
            final blocked = d['blocked'] == true;
            final name =
                isBusiness && (d['businessName']?.toString() ?? '').isNotEmpty
                ? d['businessName'].toString()
                : (d['email']?.toString() ?? '(guest)');
            final balance = (d['walletBalance'] as num?)?.toInt() ?? 0;
            final city = d['city']?.toString() ?? '';
            final lat = (d['lat'] as num?)?.toDouble();
            final lng = (d['lng'] as num?)?.toDouble();
            final hasGeo = lat != null && lng != null;
            return Card(
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: (blocked ? Colors.red : kPakGreen)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    blocked
                        ? Icons.block
                        : (isBusiness ? Icons.storefront : Icons.person),
                    color: blocked ? Colors.red : kPakGreen,
                  ),
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'Wallet ${formatPrice('$balance')}'
                  '${city.isNotEmpty ? ' · 📍 $city' : ''}'
                  '${hasGeo ? ' · 🛰️ GPS' : ''}'
                  '${isBusiness ? ' · Business' : ''}'
                  '${d['featuredBusiness'] == true ? ' · ★Featured' : ''}'
                  '${blocked ? ' · ⛔ BLOCKED' : ''}',
                  style: blocked ? const TextStyle(color: Colors.red) : null,
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'map':
                        launchUrl(
                          Uri.parse(
                            'https://www.google.com/maps/search/?api=1'
                            '&query=$lat,$lng',
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                        break;
                      case 'message':
                        _sendUserNotice(
                          context,
                          docs[i].id,
                          name,
                          warning: false,
                        );
                        break;
                      case 'warn':
                        _sendUserNotice(
                          context,
                          docs[i].id,
                          name,
                          warning: true,
                        );
                        break;
                      case 'block':
                        _toggleUserBlock(
                          context,
                          docs[i].reference,
                          name,
                          blocked,
                        );
                        break;
                      case 'feature':
                        docs[i].reference.update(
                          d['featuredBusiness'] == true
                              ? {'featuredBusiness': false}
                              : {
                                  'featuredBusiness': true,
                                  'featuredBusinessUntil': Timestamp.fromDate(
                                    DateTime.now().add(
                                      const Duration(days: 90),
                                    ),
                                  ),
                                },
                        );
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (hasGeo)
                      const PopupMenuItem(
                        value: 'map',
                        child: Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              size: 20,
                              color: kPakGreen,
                            ),
                            SizedBox(width: 10),
                            Text('View on map'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'message',
                      child: Row(
                        children: [
                          Icon(
                            Icons.campaign_outlined,
                            size: 20,
                            color: kPakGreen,
                          ),
                          SizedBox(width: 10),
                          Text('Send message'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'warn',
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: Colors.red,
                          ),
                          SizedBox(width: 10),
                          Text('Issue warning'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(
                            blocked ? Icons.lock_open : Icons.block,
                            size: 20,
                            color: blocked ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Text(blocked ? 'Unblock user' : 'Block user'),
                        ],
                      ),
                    ),
                    if (isBusiness)
                      PopupMenuItem(
                        value: 'feature',
                        child: Row(
                          children: [
                            const Icon(Icons.star, size: 20, color: kGold),
                            const SizedBox(width: 10),
                            Text(
                              d['featuredBusiness'] == true
                                  ? 'Unfeature business'
                                  : 'Feature business',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerProfileScreen(
                      sellerId: docs[i].id,
                      sellerName: name,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminOffersTab extends StatelessWidget {
  const _AdminOffersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('offers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(icon: Icons.local_offer, title: 'No offers');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final offer = (d['offerAmount'] as num?)?.toInt() ?? 0;
            final asking = (d['askingPrice'] as num?)?.toInt() ?? 0;
            return Card(
              child: ListTile(
                dense: true,
                title: Text(
                  d['listingTitle']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Offer ${formatPrice('$offer')} (asking ${formatPrice('$asking')})\n'
                  '${d['buyerName'] ?? ''} → ${d['sellerName'] ?? ''} · ${d['status'] ?? ''}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminPurchasesTab extends StatelessWidget {
  const _AdminPurchasesTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('purchases').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.shopping_bag,
            title: 'No purchases',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final amount = (d['amount'] as num?)?.toInt() ?? 0;
            final status = d['status']?.toString() ?? '';
            return Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text(
                  '${d['type'] ?? 'purchase'} · ${formatPrice('$amount')}',
                ),
                subtitle: Text(
                  '${d['userId'] ?? ''}\n${timeAgo(d['createdAt'] as Timestamp?)}',
                ),
                isThreeLine: true,
                trailing: Text(
                  status,
                  style: TextStyle(
                    color: status == 'completed'
                        ? Colors.green
                        : (status == 'insufficient' || status == 'error'
                              ? Colors.red
                              : Colors.orange),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminReportsTab extends StatelessWidget {
  const _AdminReportsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('reports').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.verified_user,
            title: 'No reports',
            subtitle: 'Reported ads will appear here for review.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final listingId = d['listingId']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['listingTitle']?.toString() ?? '(untitled ad)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reason: ${d['reason'] ?? '—'}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    Text(
                      timeAgo(d['createdAt'] as Timestamp?),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _openListingById(context, listingId),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => docs[i].reference.delete(),
                          child: const Text('Dismiss'),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () async {
                            if (listingId.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('listings')
                                  .doc(listingId)
                                  .delete();
                            }
                            await docs[i].reference.delete();
                          },
                          child: const Text('Delete ad'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminPromotionsTab extends StatelessWidget {
  const _AdminPromotionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('promotions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final am = a.data() as Map;
            final bm = b.data() as Map;
            final ap = am['status'] == 'pending' ? 0 : 1;
            final bp = bm['status'] == 'pending' ? 0 : 1;
            if (ap != bp) return ap - bp;
            final at =
                (am['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt =
                (bm['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.campaign,
            title: 'No promotion orders',
            subtitle: 'Seller promotion requests appear here for approval.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending';
            final pending = status == 'pending';
            final listingId = d['listingId']?.toString() ?? '';
            final days = (d['days'] as num?)?.toInt() ?? 7;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['listingTitle']?.toString() ?? '(untitled ad)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('${d['package']} · ${formatPrice('${d['price']}')}'),
                    Text(
                      'Seller: ${d['sellerName'] ?? ''}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        color: pending
                            ? Colors.orange
                            : (status == 'active' ? Colors.green : Colors.red),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _openListingById(context, listingId),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => docs[i].reference.update({
                              'status': 'rejected',
                            }),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () async {
                              final until = Timestamp.fromDate(
                                DateTime.now().add(Duration(days: days)),
                              );
                              if (d['type'] == 'business') {
                                final bizUid = d['userId']?.toString() ?? '';
                                if (bizUid.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(bizUid)
                                      .set({
                                        'featuredBusiness': true,
                                        'featuredBusinessUntil': until,
                                      }, SetOptions(merge: true));
                                }
                              } else if (d['type'] == 'banner') {
                                await FirebaseFirestore.instance
                                    .collection('banners')
                                    .add({
                                      'imageUrl': d['imageUrl'] ?? '',
                                      'title': d['bannerTitle'] ?? '',
                                      'subtitle': d['bannerSubtitle'] ?? '',
                                      'sellerId': d['sellerId'] ?? '',
                                      'category': '',
                                      'order': 99,
                                      'active': true,
                                      'createdAt': Timestamp.now(),
                                      'expiresAt': until,
                                    });
                              } else if (listingId.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('listings')
                                    .doc(listingId)
                                    .update({
                                      'isFeatured': true,
                                      'featuredUntil': until,
                                    });
                              }
                              await docs[i].reference.update({
                                'status': 'active',
                                'approvedAt': Timestamp.now(),
                              });
                            },
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminTopupsTab extends StatelessWidget {
  const _AdminTopupsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('walletTopups').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final am = a.data() as Map;
            final bm = b.data() as Map;
            final ap = am['status'] == 'pending' ? 0 : 1;
            final bp = bm['status'] == 'pending' ? 0 : 1;
            if (ap != bp) return ap - bp;
            final at =
                (am['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt =
                (bm['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.account_balance_wallet,
            title: 'No top-up requests',
            subtitle: 'Wallet top-up requests appear here for approval.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending';
            final pending = status == 'pending';
            final amount = (d['amount'] as num?)?.toInt() ?? 0;
            final userId = d['userId']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPrice('$amount'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${d['userEmail'] ?? userId}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        color: pending
                            ? Colors.orange
                            : (status == 'approved'
                                  ? Colors.green
                                  : Colors.red),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => docs[i].reference.update({
                              'status': 'rejected',
                            }),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () async {
                              if (userId.isEmpty || amount <= 0) return;
                              final fs = FirebaseFirestore.instance;
                              final topupRef = docs[i].reference;
                              final userRef = fs
                                  .collection('users')
                                  .doc(userId);
                              // Atomic + idempotent: only credit if still
                              // pending, so a double-tap can't double-credit.
                              await fs.runTransaction((tx) async {
                                final topupSnap = await tx.get(topupRef);
                                final tData =
                                    topupSnap.data() as Map<String, dynamic>?;
                                if (tData == null ||
                                    tData['status'] != 'pending') {
                                  return;
                                }
                                final userSnap = await tx.get(userRef);
                                final current =
                                    (userSnap.data()?['walletBalance'] as num?)
                                        ?.toInt() ??
                                    0;
                                tx.set(userRef, {
                                  'walletBalance': current + amount,
                                }, SetOptions(merge: true));
                                tx.set(
                                  userRef
                                      .collection('walletTransactions')
                                      .doc(),
                                  {
                                    'type': 'credit',
                                    'amount': amount,
                                    'purpose': 'topup',
                                    'createdAt': Timestamp.now(),
                                  },
                                );
                                tx.update(topupRef, {
                                  'status': 'approved',
                                  'approvedAt': Timestamp.now(),
                                });
                              });
                            },
                            child: const Text('Approve & credit'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminOrdersTab extends StatelessWidget {
  const _AdminOrdersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        double revenue = 0;
        int completed = 0;
        for (final d in docs) {
          final m = d.data() as Map;
          // A finished deal is 'released' (escrow) or 'completed' (legacy/COD).
          if (m['status'] == 'released' || m['status'] == 'completed') {
            final amt = (m['amount'] as num?)?.toDouble() ?? 0;
            revenue +=
                (m['commission'] as num?)?.toDouble() ?? amt * commissionRate;
            completed++;
          }
        }
        return Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              color: kPakGreen,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('${docs.length}', 'Orders'),
                    _stat('$completed', 'Completed'),
                    _stat(
                      formatPrice(revenue.toStringAsFixed(0)),
                      'Commission',
                    ),
                  ],
                ),
              ),
            ),
            const _MasterOrdersPanel(),
            const _PendingCancellationsPanel(),
            const _PendingReturnsPanel(),
            const _PendingRefundsPanel(),
            Expanded(
              child: docs.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long,
                      title: 'No orders yet',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              d['listingTitle']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${d['buyerName']} → ${d['sellerName']}\n'
                              '${formatPrice('${d['amount']}')} · '
                              'fee ${formatPrice('${d['commission']}')} · '
                              '${d['status']}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              tooltip: 'Delete order',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete this order?'),
                                    content: Text(
                                      d['listingTitle']?.toString() ?? '',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await docs[i].reference.delete();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

/// Phase 8: admin view of multi-seller (master) orders. Each master groups the
/// per-seller sub-orders created from one cart checkout. Shows the buyer, order
/// number, combined total, package count, aggregate delivery progress and
/// payment state; expanding lists each package (seller, amount, status). The
/// individual sub-orders still appear in the flat list below for per-order
/// actions — this panel is the grouped, read-oriented overview. Collapses to
/// nothing when there are no master orders.
class _MasterOrdersPanel extends StatelessWidget {
  const _MasterOrdersPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('masterOrders')
          .orderBy('createdAt', descending: true)
          .limit(25)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs
            .where((d) => !MasterOrder.fromDoc(d).isFailed)
            .toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 18,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Multi-seller orders (${docs.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final d in docs) _MasterOrderTile(master: d),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MasterOrderTile extends StatelessWidget {
  final QueryDocumentSnapshot master;
  const _MasterOrderTile({required this.master});

  @override
  Widget build(BuildContext context) {
    final mo = MasterOrder.fromDoc(master);
    final number = mo.orderNumber.isEmpty ? master.id : mo.orderNumber;
    final packages = mo.packageCount;

    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        '$number · $packages package${packages == 1 ? '' : 's'}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${mo.buyerName} · ${formatPrice(mo.itemsTotal.toStringAsFixed(0))} · '
        '${mo.paymentLabel}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        mo.allDelivered ? 'All delivered' : '${mo.deliveredCount}/$packages',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: mo.allDelivered ? kPakGreen : Colors.deepPurple,
        ),
      ),
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('masterOrderId', isEqualTo: master.id)
              .snapshots(),
          builder: (context, s) {
            if (!s.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              );
            }
            final subs = s.data!.docs;
            if (subs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  mo.status == 'pending'
                      ? 'Awaiting fan-out…'
                      : 'No sub-orders found.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              );
            }
            return Column(
              children: [
                for (final o in subs)
                  _MasterSubOrderRow(data: o.data() as Map<String, dynamic>),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MasterSubOrderRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MasterSubOrderRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final seller = data['sellerName']?.toString() ?? 'Seller';
    final number = data['orderNumber']?.toString() ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final os = orderStatusOf(data);
    final courier = data['courierName']?.toString() ?? '';
    final tracking = data['trackingNumber']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$seller${number.isEmpty ? '' : ' · $number'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${formatPrice(amount.toStringAsFixed(0))} · ${orderStatusLabel(os)}'
                  '${courier.isEmpty ? '' : ' · $courier'}'
                  '${tracking.isEmpty ? '' : ' ($tracking)'}',
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

/// Admin review of pending buyer cancellation requests across all orders (spec
/// section 8). Reuses the `orders` permission. Collapses to nothing when the
/// queue is empty. Approving/rejecting here writes to the request document; the
/// onCancellationRequestDecision Cloud Function applies the outcome (cancel,
/// refund, audit, notify).
class _PendingCancellationsPanel extends StatelessWidget {
  const _PendingCancellationsPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('cancellationRequests')
          .where('requestStatus', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.cancel_schedule_send,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cancellation requests (${docs.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final doc in docs)
                  _CancellationRequestRow(
                    orderId: doc.reference.parent.parent?.id ?? '',
                    requestId: doc.id,
                    request: doc.data(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CancellationRequestRow extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _CancellationRequestRow({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = cancelReasonLabel(request['reasonCode']?.toString() ?? '');
    final details = request['reasonDetails']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('orders')
                .doc(orderId)
                .get(),
            builder: (context, s) {
              final title =
                  s.data?.data()?['listingTitle']?.toString() ?? orderId;
              return Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              );
            },
          ),
          Text(
            details.isEmpty
                ? 'Reason: $reason'
                : 'Reason: $reason — “$details”',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _decide(context, approve: false),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: () => _decide(context, approve: true),
                child: const Text('Approve & cancel'),
              ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve cancellation?' : 'Reject request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'The order will be cancelled and the buyer refunded if a '
                        'payment is held.'
                  : 'The order stays active. Add a note for the buyer.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtl,
              decoration: InputDecoration(
                labelText: approve ? 'Note (optional)' : 'Reason for the buyer',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    noteCtl.dispose();
    if (ok != true) return;
    try {
      await decideCancellationRequest(
        orderId,
        requestId,
        approve: approve,
        response: noteCtl.text,
        asAdmin: true,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Cancellation approved.' : 'Request rejected.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }
}

/// Admin view of the Lucky Draw participation list. Super-admin only. Lists
/// everyone who shared the app (luckyDrawEntries), highest share-count first,
/// with an "eligible (shared ≥ 5)" filter and a Mark-winner toggle to pick the
/// 5 winners. `isWinner` is admin-owned (buyers can't self-set it, per rules).
class _AdminLuckyDrawTab extends StatefulWidget {
  const _AdminLuckyDrawTab();

  @override
  State<_AdminLuckyDrawTab> createState() => _AdminLuckyDrawTabState();
}

class _AdminLuckyDrawTabState extends State<_AdminLuckyDrawTab> {
  bool eligibleOnly = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('config')
                .doc('luckyDraw')
                .snapshots(),
            builder: (context, snap) {
              final enabled =
                  (snap.data?.data() as Map<String, dynamic>?)?['enabled'] !=
                  false;
              return SwitchListTile(
                title: const Text(
                  'Lucky Draw campaign',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  enabled
                      ? 'ON — banner & Invite entry points show (until 14 Aug 2026)'
                      : 'OFF — campaign hidden everywhere right now',
                ),
                value: enabled,
                activeThumbColor: kPakGreen,
                onChanged: (v) {
                  FirebaseFirestore.instance
                      .collection('config')
                      .doc('luckyDraw')
                      .set({'enabled': v}, SetOptions(merge: true));
                  luckyDrawEnabled.value = v;
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Eligible (shared ≥ 5)'),
                selected: eligibleOnly,
                onSelected: (v) => setState(() => eligibleOnly = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('luckyDrawEntries')
                .orderBy('shareCount', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data!.docs;
              if (eligibleOnly) {
                docs = docs
                    .where(
                      (d) =>
                          ((d.data()['shareCount'] as num?)?.toInt() ?? 0) >= 5,
                    )
                    .toList();
              }
              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.card_giftcard,
                  title: 'No lucky-draw entries yet',
                );
              }
              final winners = docs
                  .where((d) => d.data()['isWinner'] == true)
                  .length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  Card(
                    color: kPakGreen,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        '${docs.length} entries · $winners winner(s) marked',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final d in docs)
                    _LuckyDrawEntryRow(id: d.id, data: d.data()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LuckyDrawEntryRow extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  const _LuckyDrawEntryRow({required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final phone = (data['phone'] ?? '').toString();
    final shares = (data['shareCount'] as num?)?.toInt() ?? 0;
    final isWinner = data['isWinner'] == true;
    final eligible = shares >= 5;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isWinner
              ? kGold
              : (eligible ? kPakGreen : Colors.grey.shade400),
          child: Text(
            '$shares',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(name.isEmpty ? '(no name)' : name),
        subtitle: Text(
          '${phone.isEmpty ? 'no phone' : phone} · shared $shares time(s)',
        ),
        trailing: TextButton(
          onPressed: () => _toggleWinner(context, !isWinner),
          child: Text(
            isWinner ? 'Winner ✓' : 'Mark winner',
            style: TextStyle(
              color: isWinner ? kGold : kPakGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleWinner(BuildContext context, bool val) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('luckyDrawEntries')
          .doc(id)
          .set({
            'isWinner': val,
            'winnerMarkedAt': val ? FieldValue.serverTimestamp() : null,
          }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(content: Text(val ? 'Marked as winner.' : 'Winner removed.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }
}

/// Admin review of pending buyer REFUND requests. Reuses the `orders`
/// permission; approving issues a full or partial escrow refund to the buyer's
/// wallet via the onRefundRequestDecision Cloud Function. Refunds are decided by
/// admin only (the seller does not). Collapses when the queue is empty.
class _PendingRefundsPanel extends StatelessWidget {
  const _PendingRefundsPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('refundRequests')
          .where('requestStatus', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          color: Colors.deepPurple.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.currency_exchange,
                      color: Colors.deepPurple,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Refund requests (${docs.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final doc in docs)
                  _RefundRequestRow(
                    orderId: doc.reference.parent.parent?.id ?? '',
                    requestId: doc.id,
                    request: doc.data(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RefundRequestRow extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _RefundRequestRow({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = refundReasonLabel(request['reasonCode']?.toString() ?? '');
    final details = request['reasonDetails']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('orders')
                .doc(orderId)
                .get(),
            builder: (context, s) {
              final o = s.data?.data();
              final title = o?['listingTitle']?.toString() ?? orderId;
              final amount = (o?['amount'] as num?)?.toDouble() ?? 0;
              return Text(
                amount > 0
                    ? '$title — held ${formatPrice(amount.toStringAsFixed(0))}'
                    : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              );
            },
          ),
          Text(
            details.isEmpty
                ? 'Reason: $reason'
                : 'Reason: $reason — “$details”',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _reject(context),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                onPressed: () => _approve(context),
                child: const Text('Approve refund'),
              ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final amountCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve refund?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The buyer is refunded to their PakBazar wallet. Leave the amount '
              'blank to refund the full held amount, or enter a smaller amount '
              'for a partial refund.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Refund amount (PKR) — blank = full',
                border: OutlineInputBorder(),
                prefixText: 'PKR ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    final raw = amountCtl.text.trim();
    amountCtl.dispose();
    if (ok != true) return;
    final parsed = raw.isEmpty ? null : num.tryParse(raw);
    if (raw.isNotEmpty && (parsed == null || parsed <= 0)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid amount, or leave blank.')),
      );
      return;
    }
    try {
      await decideRefundRequest(
        orderId,
        requestId,
        approve: true,
        refundAmount: parsed,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            parsed == null
                ? 'Full refund approved.'
                : 'Partial refund of ${formatPrice(parsed.toStringAsFixed(0))} '
                      'approved.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }

  Future<void> _reject(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject refund request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The order is unchanged and no money moves. Add a note for the '
              'buyer explaining why.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(
                labelText: 'Reason for the buyer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final note = noteCtl.text;
    noteCtl.dispose();
    if (ok != true) return;
    try {
      await decideRefundRequest(orderId, requestId, approve: false, note: note);
      messenger.showSnackBar(
        const SnackBar(content: Text('Refund request rejected.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }
}

/// Admin review of pending buyer RETURN requests (Phase 4). Reuses the `orders`
/// permission; approving refunds the buyer and marks the order returned via the
/// onReturnRequestDecision Cloud Function. Collapses when the queue is empty.
class _PendingReturnsPanel extends StatelessWidget {
  const _PendingReturnsPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('returnRequests')
          .where('requestStatus', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          color: Colors.blueGrey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.assignment_return,
                      color: Colors.blueGrey,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Return requests (${docs.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final doc in docs)
                  _ReturnRequestRow(
                    orderId: doc.reference.parent.parent?.id ?? '',
                    requestId: doc.id,
                    request: doc.data(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReturnRequestRow extends StatelessWidget {
  final String orderId;
  final String requestId;
  final Map<String, dynamic> request;
  const _ReturnRequestRow({
    required this.orderId,
    required this.requestId,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final reason = returnReasonLabel(request['reasonCode']?.toString() ?? '');
    final details = request['reasonDetails']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('orders')
                .doc(orderId)
                .get(),
            builder: (context, s) {
              final title =
                  s.data?.data()?['listingTitle']?.toString() ?? orderId;
              return Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              );
            },
          ),
          Text(
            details.isEmpty
                ? 'Reason: $reason'
                : 'Reason: $reason — “$details”',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _decide(context, approve: false),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                ),
                onPressed: () => _decide(context, approve: true),
                child: const Text('Approve & refund'),
              ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve return?' : 'Reject return?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'The buyer is refunded and the order marked returned '
                        '(only while the payment is still held).'
                  : 'The order stays as-is. Add a note for the buyer.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtl,
              decoration: InputDecoration(
                labelText: approve ? 'Note (optional)' : 'Reason for the buyer',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    noteCtl.dispose();
    if (ok != true) return;
    try {
      await decideReturnRequest(
        orderId,
        requestId,
        approve: approve,
        response: noteCtl.text,
        asAdmin: true,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(approve ? 'Return approved.' : 'Return rejected.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }
}

class _AdminListingsTab extends StatelessWidget {
  const _AdminListingsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No listings',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final l = Listing.fromDoc(docs[i]);
            final ref = docs[i].reference;
            final imgs = l.galleryImages;
            final featured = l.isCurrentlyFeatured;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: imgs.isEmpty
                              ? Container(
                                  width: 52,
                                  height: 52,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image),
                                )
                              : Image.network(
                                  imgs.first,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 52,
                                    height: 52,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.title.isEmpty ? '(untitled)' : l.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${formatPrice(l.price)} · ${l.sellerName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (featured)
                                    const Text(
                                      '★ Featured',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: kGold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (l.isSold)
                                    const Text(
                                      'SOLD',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Wrap(
                      spacing: 2,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdDetailsScreen(listing: l),
                            ),
                          ),
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('View'),
                        ),
                        TextButton.icon(
                          onPressed: () => ref.update(
                            featured
                                ? {'isFeatured': false}
                                : {
                                    'isFeatured': true,
                                    'featuredUntil': Timestamp.fromDate(
                                      DateTime.now().add(
                                        const Duration(days: 90),
                                      ),
                                    ),
                                  },
                          ),
                          icon: Icon(
                            featured ? Icons.star : Icons.star_border,
                            size: 18,
                            color: kGold,
                          ),
                          label: Text(featured ? 'Unfeature' : 'Feature'),
                        ),
                        TextButton.icon(
                          // Route through setListingStatus so `status` and the
                          // legacy `isSold` bool stay in sync (a bare isSold
                          // flip left status='in_stock' on a sold item).
                          onPressed: () => setListingStatus(
                            l.id,
                            l.isSold ? 'in_stock' : 'sold',
                          ),
                          icon: Icon(
                            l.isSold ? Icons.shopping_bag : Icons.sell,
                            size: 18,
                          ),
                          label: Text(
                            l.isSold ? 'Mark available' : 'Mark sold',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete ad?'),
                                content: Text(
                                  'Permanently delete "${l.title}"? This cannot '
                                  'be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await ref.delete();
                          },
                          icon: const Icon(
                            Icons.delete,
                            size: 18,
                            color: Colors.red,
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Admin chat monitoring: lists every buyer↔seller conversation on the
/// platform (most recent first), searchable by participant or ad. Tapping a
/// row opens the full thread read-only (ChatScreen in adminView mode).
class _AdminChatsTab extends StatefulWidget {
  const _AdminChatsTab();

  @override
  State<_AdminChatsTab> createState() => _AdminChatsTabState();
}

class _AdminChatsTabState extends State<_AdminChatsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by buyer, seller or ad…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .orderBy('lastTime', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading chats: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data!.docs;
              if (_query.isNotEmpty) {
                docs = docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final hay = [
                    m['buyerName'],
                    m['sellerName'],
                    m['listingTitle'],
                    m['lastMessage'],
                  ].map((e) => e?.toString().toLowerCase() ?? '').join(' ');
                  return hay.contains(_query);
                }).toList();
              }

              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No chats',
                  subtitle: 'Buyer–seller conversations will appear here.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final buyerName = data['buyerName']?.toString() ?? 'Buyer';
                  final sellerName = data['sellerName']?.toString() ?? 'Seller';
                  final listingImage = data['listingImage']?.toString() ?? '';
                  final lastTime = data['lastTime'] as Timestamp?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: listingImage.isEmpty
                          ? const CircleAvatar(child: Icon(Icons.forum))
                          : CircleAvatar(
                              backgroundImage: NetworkImage(listingImage),
                            ),
                      title: Text('$buyerName  ↔  $sellerName'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['listingTitle']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            data['lastMessage']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (lastTime != null)
                            Text(
                              timeAgo(lastTime),
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: data['chatId']?.toString() ?? docs[i].id,
                            listingId: data['listingId']?.toString() ?? '',
                            listingTitle:
                                data['listingTitle']?.toString() ?? '',
                            listingImage: listingImage,
                            buyerId: data['buyerId']?.toString() ?? '',
                            sellerId: data['sellerId']?.toString() ?? '',
                            buyerName: buyerName,
                            sellerName: sellerName,
                            adminView: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Admin → review suspension appeals. Lists pending appeals (newest first);
/// Approve reinstates the user (clears their `blocked` flag), Reject keeps them
/// suspended. Either way the user is notified of the decision.
/// Admin → control "Sell as a business". Selling as a business is approval-
/// gated: a user requests it (businessStatus 'pending') and only an admin flips
/// `isBusiness` true, which is what every BUSINESS badge / storefront in the app
/// keys on. This tab is the control surface — a review queue for pending
/// requests, the full directory of business accounts by status, the featured
/// businesses, and an activity view of each store's listings & sales.
class _AdminBusinessTab extends StatefulWidget {
  const _AdminBusinessTab();

  @override
  State<_AdminBusinessTab> createState() => _AdminBusinessTabState();
}

class _AdminBusinessTabState extends State<_AdminBusinessTab> {
  // 'accounts' shows status-filtered lists; 'activity' shows each business's
  // listing & sales counts.
  String _mode = 'accounts';
  String _status = 'pending';

  static const List<(String, String)> _statuses = [
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('suspended', 'Suspended'),
    ('rejected', 'Rejected'),
    ('featured', 'Featured'),
  ];

  /// The users query backing the current status filter. Approved businesses are
  /// identified by `isBusiness == true` (the app-wide source of truth, which
  /// also covers legacy accounts with no businessStatus); everything else is a
  /// businessStatus / featuredBusiness equality. All are single-field top-level
  /// queries, so Firestore auto-indexes them (no manual index needed).
  Query<Map<String, dynamic>> _query() {
    final users = FirebaseFirestore.instance.collection('users');
    switch (_status) {
      case 'approved':
        return users.where('isBusiness', isEqualTo: true);
      case 'featured':
        return users.where('featuredBusiness', isEqualTo: true);
      default: // pending | suspended | rejected
        return users.where('businessStatus', isEqualTo: _status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              for (final m in const [
                ('accounts', 'Accounts'),
                ('activity', 'Activity'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(m.$2),
                    selected: _mode == m.$1,
                    selectedColor: kPakGreen.withValues(alpha: 0.22),
                    onSelected: (_) => setState(() => _mode = m.$1),
                  ),
                ),
            ],
          ),
        ),
        if (_mode == 'accounts')
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in _statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.$2),
                        selected: _status == s.$1,
                        selectedColor: kPakGreen.withValues(alpha: 0.18),
                        onSelected: (_) => setState(() => _status = s.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _mode == 'activity' ? _buildActivity() : _buildAccounts(),
        ),
      ],
    );
  }

  Widget _buildAccounts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            final bt =
                (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.storefront_outlined,
            title: 'No $_status businesses',
            subtitle: _status == 'pending'
                ? 'Business requests awaiting approval appear here.'
                : 'No accounts in this category.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) => _BusinessAccountCard(userDoc: docs[i]),
        );
      },
    );
  }

  Widget _buildActivity() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isBusiness', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.insights_outlined,
            title: 'No active businesses',
            subtitle: 'Approved business stores and their activity show here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) => _BusinessActivityCard(userDoc: docs[i]),
        );
      },
    );
  }
}

/// One business account in the admin directory, with the approve/reject/
/// suspend/reactivate controls and a link into its store. Writes flip the
/// app-wide `isBusiness` flag and `businessStatus`, then notify the seller.
class _BusinessAccountCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> userDoc;
  const _BusinessAccountCard({required this.userDoc});

  @override
  State<_BusinessAccountCard> createState() => _BusinessAccountCardState();
}

class _BusinessAccountCardState extends State<_BusinessAccountCard> {
  bool _busy = false;

  (String, Color) _chip(Map<String, dynamic> d) {
    final s =
        d['businessStatus']?.toString() ??
        (d['isBusiness'] == true ? 'approved' : 'none');
    return switch (s) {
      'approved' => ('Approved', kPakGreen),
      'pending' => ('Pending', AppColors.info),
      'suspended' => ('Suspended', Colors.orange),
      'rejected' => ('Rejected', Colors.red),
      _ => ('—', AppColors.textMuted),
    };
  }

  Future<void> _decide({
    required String status,
    required bool business,
    required String verb,
    required bool positive,
    bool clearFeatured = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final d = widget.userDoc.data();
    final name = (d['businessName']?.toString() ?? '').trim();
    final store = name.isEmpty ? 'your store' : '"$name"';
    try {
      final update = <String, dynamic>{
        'isBusiness': business,
        'businessStatus': status,
      };
      if (clearFeatured) update['featuredBusiness'] = false;
      await widget.userDoc.reference.update(update);
      await widget.userDoc.reference.collection('notifications').add({
        'title': switch (status) {
          'approved' => '✅ Business approved',
          'rejected' => '⚠️ Business not approved',
          'suspended' => '⛔ Business suspended',
          _ => 'Business status updated',
        },
        'body': switch (status) {
          'approved' =>
            'Your business $store is approved. Your BUSINESS badge and store '
                'are now live — all your products appear together there.',
          'rejected' =>
            'Your request to sell as a business ($store) was not approved. You '
                'can update your details and submit again.',
          'suspended' =>
            'Your business selling ($store) has been suspended. Please contact '
                'support.',
          _ => 'Your business status was updated.',
        },
        'type': positive ? 'admin' : 'warning',
        'read': false,
        'createdAt': Timestamp.now(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Business $verb.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.userDoc.data();
    final status =
        d['businessStatus']?.toString() ??
        (d['isBusiness'] == true ? 'approved' : 'none');
    final name = (d['businessName']?.toString() ?? '').trim();
    final email = d['email']?.toString() ?? '';
    final (chipLabel, chipColor) = _chip(d);
    final featured = d['featuredBusiness'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, size: 18, color: kPakGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name.isEmpty ? '(no business name)' : name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (featured) ...[
                  const Icon(Icons.star, size: 16, color: kGold),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chipLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: chipColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (email.isNotEmpty)
              Text(email, style: TextStyle(color: AppColors.textMuted)),
            if ((d['storeCategory']?.toString() ?? '').isNotEmpty)
              Text(
                'Category: ${d['storeCategory']}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            if ((d['tagline']?.toString() ?? '').isNotEmpty)
              Text(
                d['tagline'].toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 8),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerProfileScreen(
                          sellerId: widget.userDoc.id,
                          sellerName: name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.storefront, size: 18),
                    label: const Text('Store'),
                  ),
                  if (status != 'approved')
                    ElevatedButton.icon(
                      onPressed: () => _decide(
                        status: 'approved',
                        business: true,
                        verb: 'approved',
                        positive: true,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPakGreen,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.verified, size: 18),
                      label: Text(
                        status == 'suspended' || status == 'rejected'
                            ? 'Reinstate'
                            : 'Approve',
                      ),
                    ),
                  if (status == 'approved')
                    OutlinedButton.icon(
                      onPressed: () => _decide(
                        status: 'suspended',
                        business: false,
                        verb: 'suspended',
                        positive: false,
                        clearFeatured: true,
                      ),
                      icon: const Icon(
                        Icons.pause_circle_outline,
                        color: Colors.orange,
                        size: 18,
                      ),
                      label: const Text(
                        'Suspend',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  if (status == 'pending')
                    OutlinedButton.icon(
                      onPressed: () => _decide(
                        status: 'rejected',
                        business: false,
                        verb: 'rejected',
                        positive: false,
                      ),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 18,
                      ),
                      label: const Text(
                        'Reject',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A business store's activity at a glance: live-listing count and total
/// orders, with a tap into the store. Counts use aggregate queries (cheap,
/// bounded to approved businesses).
class _BusinessActivityCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> userDoc;
  const _BusinessActivityCard({required this.userDoc});

  Future<(int, int)> _counts() async {
    final fs = FirebaseFirestore.instance;
    final listings = await fs
        .collection('listings')
        .where('userId', isEqualTo: userDoc.id)
        .count()
        .get();
    final orders = await fs
        .collection('orders')
        .where('sellerId', isEqualTo: userDoc.id)
        .count()
        .get();
    return (listings.count ?? 0, orders.count ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final d = userDoc.data();
    final name = (d['businessName']?.toString() ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x1A0A7A3C),
          child: Icon(Icons.storefront, color: kPakGreen),
        ),
        title: Text(
          name.isEmpty ? '(no business name)' : name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: FutureBuilder<(int, int)>(
          future: _counts(),
          builder: (context, snap) {
            if (!snap.hasData) return const Text('Loading activity…');
            final (listings, orders) = snap.data!;
            return Text('$listings listings · $orders orders');
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SellerProfileScreen(sellerId: userDoc.id, sellerName: name),
          ),
        ),
      ),
    );
  }
}

/// Admin → verify seller payout accounts. A seller manages their own bank /
/// wallet routing details but can NEVER self-verify (enforced in
/// firestore.rules); this is the other half of that gate. Lists every seller's
/// payout accounts by verification status (Pending first) via a collection-group
/// query, showing the full routing details an admin needs to check, and lets a
/// payments admin mark each Verified / Rejected / Suspended. Every decision is
/// written to the immutable `payoutAccountAudit` log and the seller is notified.
class _AdminPayoutAccountsTab extends StatefulWidget {
  const _AdminPayoutAccountsTab();

  @override
  State<_AdminPayoutAccountsTab> createState() =>
      _AdminPayoutAccountsTabState();
}

class _AdminPayoutAccountsTabState extends State<_AdminPayoutAccountsTab> {
  String _status = 'pending';
  static const List<String> _statuses = [
    'pending',
    'verified',
    'rejected',
    'suspended',
  ];

  String _label(String s) => switch (s) {
    'pending' => 'Pending',
    'verified' => 'Verified',
    'rejected' => 'Rejected',
    'suspended' => 'Suspended',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_label(s)),
                      selected: _status == s,
                      selectedColor: kPakGreen.withValues(alpha: 0.18),
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            // Collection-group query across every seller's payoutAccounts.
            // Sorted client-side to avoid needing a composite index (a
            // single-field collection-group index on verificationStatus is
            // declared in firestore.indexes.json).
            stream: FirebaseFirestore.instance
                .collectionGroup('payoutAccounts')
                .where('verificationStatus', isEqualTo: _status)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading accounts: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final at =
                      ((a.data() as Map)['createdAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final bt =
                      ((b.data() as Map)['createdAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  return bt.compareTo(at);
                });
              if (docs.isEmpty) {
                return EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No ${_label(_status).toLowerCase()} accounts',
                  subtitle: _status == 'pending'
                      ? 'Payout accounts awaiting verification appear here.'
                      : 'No accounts with this status.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final sellerId = doc.reference.parent.parent?.id ?? '';
                  return _PayoutAccountReviewCard(
                    account: PayoutAccount.fromDoc(doc),
                    accountRef: doc.reference,
                    sellerId: sellerId,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PayoutAccountReviewCard extends StatefulWidget {
  final PayoutAccount account;
  final DocumentReference accountRef;
  final String sellerId;
  const _PayoutAccountReviewCard({
    required this.account,
    required this.accountRef,
    required this.sellerId,
  });

  @override
  State<_PayoutAccountReviewCard> createState() =>
      _PayoutAccountReviewCardState();
}

class _PayoutAccountReviewCardState extends State<_PayoutAccountReviewCard> {
  bool _busy = false;

  (String, Color) _chip(String s) => switch (s) {
    'verified' => ('Verified', kPakGreen),
    'rejected' => ('Rejected', Colors.red),
    'suspended' => ('Suspended', Colors.orange),
    _ => ('Pending review', Colors.blueGrey),
  };

  Future<void> _setStatus(String status, String verb) async {
    if (_busy) return;
    setState(() => _busy = true);
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final a = widget.account;
    try {
      final fs = FirebaseFirestore.instance;
      await widget.accountRef.update({
        'verificationStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Immutable audit trail of the admin decision.
      await fs.collection('payoutAccountAudit').add({
        'sellerId': widget.sellerId,
        'accountId': a.id,
        'action': status, // verified | rejected | suspended
        'by': adminUid,
        'at': Timestamp.now(),
      });
      // Notify the seller and deep-link them to their payout accounts.
      if (widget.sellerId.isNotEmpty) {
        final verified = status == 'verified';
        await fs
            .collection('users')
            .doc(widget.sellerId)
            .collection('notifications')
            .add({
              'title': verified
                  ? '✅ Payout account verified'
                  : status == 'rejected'
                  ? '⚠️ Payout account rejected'
                  : '⛔ Payout account suspended',
              'body': verified
                  ? '${a.providerLabel} (${a.maskedIdentifier}) is verified and can now receive your payouts.'
                  : '${a.providerLabel} (${a.maskedIdentifier}) was $status. Please review your payout account details.',
              'type': 'payoutAccount',
              'refId': a.id,
              'read': false,
              'createdAt': Timestamp.now(),
            });
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Account $verb.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _detailRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final (chipLabel, chipColor) = _chip(a.verificationStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  a.isBank ? Icons.account_balance : Icons.phone_android,
                  size: 18,
                  color: kPakGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.providerLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chipLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: chipColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Full routing details (unmasked) so the admin can verify them.
            _detailRow('Account title', a.accountTitle),
            if (a.isBank) ...[
              _detailRow('Bank', a.bankName),
              _detailRow('IBAN', a.iban),
              _detailRow('Account no.', a.accountNumber),
              _detailRow('Branch code', a.branchCode),
            ] else
              _detailRow('${payoutTypeLabel(a.type)} no.', a.mobileNumber),
            _detailRow('Seller ID', widget.sellerId),
            _detailRow(
              'Added',
              a.createdAt == null ? '—' : timeAgo(a.createdAt),
            ),
            const SizedBox(height: 10),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (a.verificationStatus != 'verified')
                    ElevatedButton.icon(
                      onPressed: () => _setStatus('verified', 'verified'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPakGreen,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('Verify'),
                    ),
                  if (a.verificationStatus != 'suspended')
                    OutlinedButton.icon(
                      onPressed: () => _setStatus('suspended', 'suspended'),
                      icon: const Icon(
                        Icons.pause_circle_outline,
                        color: Colors.orange,
                        size: 18,
                      ),
                      label: const Text(
                        'Suspend',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  if (a.verificationStatus != 'rejected')
                    OutlinedButton.icon(
                      onPressed: () => _setStatus('rejected', 'rejected'),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 18,
                      ),
                      label: const Text(
                        'Reject',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminAppealsTab extends StatelessWidget {
  const _AdminAppealsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appeals')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading appeals: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.gavel,
            title: 'No appeals',
            subtitle: 'Suspension appeals from users will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final email = d['userEmail']?.toString() ?? '';
            final who = email.isNotEmpty ? email.split('@').first : 'User';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gavel, size: 18, color: kPakGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            who,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          timeAgo(d['createdAt'] as Timestamp?),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(d['message']?.toString() ?? ''),
                    const SizedBox(height: 10),
                    _AppealActions(
                      appealRef: docs[i].reference,
                      userId: d['userId']?.toString() ?? '',
                      who: who,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AppealActions extends StatefulWidget {
  final DocumentReference appealRef;
  final String userId;
  final String who;
  const _AppealActions({
    required this.appealRef,
    required this.userId,
    required this.who,
  });

  @override
  State<_AppealActions> createState() => _AppealActionsState();
}

class _AppealActionsState extends State<_AppealActions> {
  bool _busy = false;

  Future<void> _resolve({required bool approve}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fs = FirebaseFirestore.instance;
      await widget.appealRef.update({
        'status': approve ? 'approved' : 'rejected',
        'resolvedAt': Timestamp.now(),
      });
      final userRef = fs.collection('users').doc(widget.userId);
      if (approve) {
        await userRef.update({
          'blocked': false,
          'blockedAt': FieldValue.delete(),
        });
      }
      await userRef.collection('notifications').add({
        'title': approve
            ? '✅ Appeal approved — account restored'
            : '⚠️ Appeal declined',
        'body': approve
            ? 'Your appeal was approved and your account has been reinstated. '
                  'Please follow PakBazar rules.'
            : 'Your appeal was reviewed and declined. Your account remains '
                  'suspended. You may submit another appeal.',
        'type': approve ? 'admin' : 'warning',
        'read': false,
        'createdAt': Timestamp.now(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? '${widget.who} reinstated'
                  : '${widget.who}\'s appeal rejected',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not resolve appeal: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () => _resolve(approve: false),
          icon: const Icon(Icons.close, color: Colors.red, size: 18),
          label: const Text('Reject', style: TextStyle(color: Colors.red)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _resolve(approve: true),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Approve & unblock'),
        ),
      ],
    );
  }
}

/// One-time migration: stamp every pre-existing ad that has no moderation
/// status with `approvalStatus: 'approved'` so it keeps showing once read-level
/// hiding (which filters queries by approvalStatus) is enabled. Safe to re-run —
/// it skips ads already marked approved/pending/rejected.
Future<void> _backfillApprovals(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Approve existing ads?'),
      content: const Text(
        'This marks every ad that predates moderation as "approved" so it stays '
        'visible. Run this once. Ads already pending/rejected are left as-is.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Run'),
        ),
      ],
    ),
  );
  if (go != true) return;
  try {
    final fs = FirebaseFirestore.instance;
    final snap = await fs.collection('listings').get();
    var updated = 0;
    var batch = fs.batch();
    var inBatch = 0;
    for (final d in snap.docs) {
      final s = (d.data())['approvalStatus'];
      if (s != 'approved' && s != 'pending' && s != 'rejected') {
        batch.update(d.reference, {'approvalStatus': 'approved'});
        updated++;
        inBatch++;
        if (inBatch == 400) {
          await batch.commit();
          batch = fs.batch();
          inBatch = 0;
        }
      }
    }
    if (inBatch > 0) await batch.commit();
    messenger.showSnackBar(
      SnackBar(content: Text('Backfill done: $updated ad(s) marked approved')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Backfill failed: $e')));
  }
}

/// Admin → moderation queue. Lists ads awaiting approval (approvalStatus ==
/// 'pending'); tap to view the full ad, then Approve (goes live) or Reject
/// (stays hidden). The seller is notified of the decision.
class _AdminApprovalsTab extends StatelessWidget {
  const _AdminApprovalsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: () => _backfillApprovals(context),
              icon: const Icon(Icons.cloud_done_outlined, size: 18),
              label: const Text('Approve existing ads (one-time)'),
            ),
          ),
        ),
        Expanded(child: _buildQueue(context)),
      ],
    );
  }

  Widget _buildQueue(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('approvalStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading queue: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return at.compareTo(bt); // oldest first — clear the queue in order
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'No ads awaiting approval',
            subtitle: 'New ads will appear here for review before going live.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final listing = Listing.fromDoc(docs[i]);
            final images = listing.galleryImages;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: images.isEmpty
                          ? const CircleAvatar(child: Icon(Icons.image))
                          : CircleAvatar(
                              backgroundImage: NetworkImage(images.first),
                            ),
                      title: Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatPrice(listing.price)}'
                        '${listing.city.isNotEmpty ? ' · ${listing.city}' : ''}'
                        '${listing.sellerName.isNotEmpty ? ' · ${listing.sellerName}' : ''}'
                        '\nPosted ${timeAgo(listing.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdDetailsScreen(listing: listing),
                          ),
                        ),
                        child: const Text('View'),
                      ),
                    ),
                    _ListingApprovalActions(
                      listingRef: docs[i].reference,
                      sellerId: listing.userId,
                      title: listing.title,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ListingApprovalActions extends StatefulWidget {
  final DocumentReference listingRef;
  final String sellerId;
  final String title;
  const _ListingApprovalActions({
    required this.listingRef,
    required this.sellerId,
    required this.title,
  });

  @override
  State<_ListingApprovalActions> createState() =>
      _ListingApprovalActionsState();
}

class _ListingApprovalActionsState extends State<_ListingApprovalActions> {
  bool _busy = false;

  Future<void> _notifySeller(String title, String body, String type) async {
    if (widget.sellerId.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.sellerId)
        .collection('notifications')
        .add({
          'title': title,
          'body': body,
          'type': type,
          'read': false,
          'createdAt': Timestamp.now(),
        });
  }

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.listingRef.update({'approvalStatus': 'approved'});
      await _notifySeller(
        '✅ Your ad is now live',
        'Your ad "${widget.title}" was approved and is now visible on PakBazar.',
        'admin',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ad approved — now live')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not approve: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this ad?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason (shown to the seller)…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.listingRef.update({'approvalStatus': 'rejected'});
      await _notifySeller(
        '⚠️ Your ad was not approved',
        reason.isEmpty
            ? 'Your ad "${widget.title}" was rejected and is not visible. '
                  'Please review our rules and post again.'
            : 'Your ad "${widget.title}" was rejected: $reason',
        'warning',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ad rejected')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not reject: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: _reject,
          icon: const Icon(Icons.close, color: Colors.red, size: 18),
          label: const Text('Reject', style: TextStyle(color: Colors.red)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _approve,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Approve'),
        ),
      ],
    );
  }
}

/// Add or edit a staff member's record: email + per-area permission checkboxes
/// + active toggle. Writes to staff/{lowercased-email}. Super-admin only (the
/// tab itself is gated).
Future<void> _editStaffDialog(
  BuildContext context, {
  String? email,
  Map<String, bool>? perms,
  bool active = true,
}) async {
  final emailCtrl = TextEditingController(text: email ?? '');
  final selected = <String>{
    for (final a in kAdminAreas)
      if (perms?[a.$1] == true) a.$1,
  };
  var isActive = active;
  final isNew = email == null;
  final messenger = ScaffoldMessenger.of(context);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(isNew ? 'Add staff' : 'Edit staff'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailCtrl,
                  enabled: isNew,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Staff email',
                    hintText: 'person@example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (v) => setLocal(() => isActive = v),
                ),
                const Divider(),
                Row(
                  children: [
                    const Text(
                      'Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setLocal(
                        () => selected.addAll(kAdminAreas.map((a) => a.$1)),
                      ),
                      child: const Text('Enable all'),
                    ),
                    TextButton(
                      onPressed: () => setLocal(selected.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Text(
                  'Turn on only what this staff member should manage.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                for (final area in kAdminAreas)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(area.$2),
                    value: selected.contains(area.$1),
                    onChanged: (v) => setLocal(() {
                      if (v) {
                        selected.add(area.$1);
                      } else {
                        selected.remove(area.$1);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  final e = emailCtrl.text.trim().toLowerCase();
  emailCtrl.dispose();
  if (saved != true) return;
  if (e.isEmpty || !e.contains('@')) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Enter a valid email')),
    );
    return;
  }
  final permsMap = {for (final a in kAdminAreas) a.$1: selected.contains(a.$1)};
  try {
    await FirebaseFirestore.instance.collection('staff').doc(e).set({
      'email': e,
      'permissions': permsMap,
      'active': isActive,
      'addedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    messenger.showSnackBar(SnackBar(content: Text('Saved staff: $e')));
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $err')));
  }
}

/// Super-admin-only tab to manage staff and their permissions.
class _AdminStaffTab extends StatelessWidget {
  const _AdminStaffTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => _editStaffDialog(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add staff'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('staff').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading staff: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.group_outlined,
                  title: 'No staff yet',
                  subtitle: 'Add staff and grant them admin permissions.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final email = d['email']?.toString() ?? docs[i].id;
                  final active = d['active'] != false;
                  final perms = (d['permissions'] as Map?) ?? const {};
                  final granted = kAdminAreas
                      .where((a) => perms[a.$1] == true)
                      .map((a) => a.$2)
                      .toList();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (active ? kPakGreen : Colors.grey)
                            .withValues(alpha: 0.15),
                        child: Icon(
                          Icons.badge,
                          color: active ? kPakGreen : Colors.grey,
                        ),
                      ),
                      title: Text(email),
                      subtitle: Text(
                        active
                            ? (granted.isEmpty
                                  ? 'No permissions granted'
                                  : granted.join(', '))
                            : 'Inactive · ${granted.length} permission(s)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            _editStaffDialog(
                              context,
                              email: email,
                              perms: {
                                for (final a in kAdminAreas)
                                  a.$1: perms[a.$1] == true,
                              },
                              active: active,
                            );
                          } else if (v == 'remove') {
                            docs[i].reference.delete();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit permissions'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove staff'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Admin → account-deletion requests queue. Lists pending requests; an admin
/// can delete the user's data (their listings + profile doc) and mark it
/// resolved. The Firebase Auth login itself is removed in the Firebase Console.
class _AdminDeletionsTab extends StatelessWidget {
  const _AdminDeletionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deletionRequests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return at.compareTo(bt);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.delete_outline,
            title: 'No deletion requests',
            subtitle: 'Account-deletion requests from users appear here.',
          );
        }
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.all(10),
              child: const Text(
                'After deleting a user\'s data here, also remove their login in '
                'Firebase Console → Authentication to fully delete the account.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final uid = d['userId']?.toString() ?? docs[i].id;
                  final reason = d['reason']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['email']?.toString() ?? uid,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'UID: $uid',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            'Requested ${timeAgo(d['createdAt'] as Timestamp?)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('Reason: $reason'),
                          ],
                          const SizedBox(height: 8),
                          _DeletionActions(uid: uid, ref: docs[i].reference),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeletionActions extends StatefulWidget {
  final String uid;
  final DocumentReference ref;
  const _DeletionActions({required this.uid, required this.ref});

  @override
  State<_DeletionActions> createState() => _DeletionActionsState();
}

class _DeletionActionsState extends State<_DeletionActions> {
  bool _busy = false;

  Future<void> _deleteAndResolve() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this user\'s data?'),
        content: const Text(
          'This permanently deletes the user\'s ads and profile document. '
          'Remember to also remove their login in Firebase Console.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete data'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final fs = FirebaseFirestore.instance;
      // Delete the user's listings.
      final listings = await fs
          .collection('listings')
          .where('userId', isEqualTo: widget.uid)
          .get();
      var batch = fs.batch();
      var n = 0;
      for (final l in listings.docs) {
        batch.delete(l.reference);
        n++;
        if (n % 400 == 0) {
          await batch.commit();
          batch = fs.batch();
        }
      }
      await batch.commit();
      // Delete the profile document.
      await fs.collection('users').doc(widget.uid).delete();
      // Mark the request resolved.
      await widget.ref.update({
        'status': 'resolved',
        'resolvedAt': Timestamp.now(),
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Data deleted. Now remove the login in Firebase Console.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.ref.update({
        'status': 'dismissed',
        'resolvedAt': Timestamp.now(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _deleteAndResolve,
          icon: const Icon(Icons.delete_forever, size: 18),
          label: const Text('Delete data & resolve'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notification center
// ---------------------------------------------------------------------------
