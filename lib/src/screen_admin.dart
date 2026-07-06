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
      ('approvals', 'Approvals', _AdminApprovalsTab()),
      ('verifyId', 'Verify ID', _AdminVerificationsTab()),
      ('payments', 'Payments', _AdminPaymentsTab()),
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
                e.$1 == 'support'
                    ? _SupportTabLabel(e.$2)
                    : Tab(text: e.$2),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [for (final e in visible) e.$3],
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That ad no longer exists.')),
    );
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final amount = (d['amount'] as num?)?.toDouble() ?? 0;
            final commission =
                (d['commission'] as num?)?.toDouble() ?? (amount * commissionRate);
            final payout = amount - commission;
            final confirmed = d['buyerConfirmed'] == true;
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
                    const SizedBox(height: 2),
                    Text(
                      'Buyer: ${d['buyerName'] ?? ''}   ·   '
                      'Seller: ${d['sellerName'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Held ${formatPrice(amount.toStringAsFixed(0))}  ·  '
                      'payout ${formatPrice(payout.toStringAsFixed(0))}  ·  '
                      'fee ${formatPrice(commission.toStringAsFixed(0))}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          confirmed
                              ? Icons.check_circle
                              : Icons.hourglass_top,
                          size: 15,
                          color: confirmed ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          confirmed
                              ? 'Buyer confirmed receipt'
                              : 'Buyer has not confirmed yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: confirmed ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _EscrowActions(orderId: docs[i].id),
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

/// Release / refund buttons for one escrowed order. Stateful so both disable
/// while the instruction is written — a double-tap can't queue two actions
/// (the Cloud Function also guards on order status, so it stays idempotent).
class _EscrowActions extends StatefulWidget {
  const _EscrowActions({required this.orderId});

  final String orderId;

  @override
  State<_EscrowActions> createState() => _EscrowActionsState();
}

class _EscrowActionsState extends State<_EscrowActions> {
  bool busy = false;

  Future<void> _act(String type) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await FirebaseFirestore.instance.collection('escrowActions').add({
        'orderId': widget.orderId,
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
          onPressed: busy ? null : () => _act('refund'),
          child: const Text('Refund buyer'),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: busy ? null : () => _act('release'),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Release to seller'),
        ),
      ],
    );
  }
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                          style: const TextStyle(
                            color: Colors.grey,
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
      stream: FirebaseFirestore.instance.collection('verifications').snapshots(),
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
                (am['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt =
                (bm['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
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
                        final gallery = [selfie, cnic]
                            .where((u) => u.isNotEmpty)
                            .toList();
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Selfie  ·  CNIC  (tap to enlarge)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.home_outlined,
                            size: 16, color: kPakGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address.isEmpty ? '(no address provided)' : address,
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
                            builder: (_) => FullScreenGallery(images: [proof]),
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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          'Address proof (tap to enlarge)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
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
    final ref =
        FirebaseFirestore.instance.collection('config').doc('verification');
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
      await users.doc(widget.uid).collection('notifications').add(
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
                  const Text(
                    'Users online now',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text(
                  'Customer Care',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(height: 4),
                PresenceStatusLine(
                  kSupportPresenceId,
                  onlinePrefix: 'Support is',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
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
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
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
        _section('Escrow & your earnings', fs.collection('orders').snapshots(), (
          docs,
        ) {
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
                earnings += (m['commission'] as num?) ?? (amt * commissionRate);
            }
          }
          return [
            _Metric('$settled', 'Deals done'),
            _Metric(formatPrice('${gmv.toInt()}'), 'GMV'),
            _Metric(formatPrice('${earnings.toInt()}'), 'Your earnings (2%)'),
            _Metric('$inEscrow', 'In escrow'),
            _Metric(formatPrice('${held.toInt()}'), 'Held now'),
          ];
        }),
        _section('Negotiation & purchases', fs.collection('offers').snapshots(), (
          docs,
        ) {
          return [_Metric('${docs.length}', 'Total offers')];
        }),
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
            return ((m['commission'] as num?)?.toDouble()) ?? amt * commissionRate;
          },
          money: true,
        ),
        _trendCard(
          'New users',
          fs.collection('users').snapshots(),
          (m) => 1.0,
        ),
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
        content: Text(block ? '$name has been blocked' : '$name has been unblocked'),
      ),
    );
  }
}

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').limit(300).snapshots(),
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
            final name = isBusiness && (d['businessName']?.toString() ?? '').isNotEmpty
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
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Wallet ${formatPrice('$balance')}'
                  '${city.isNotEmpty ? ' · 📍 $city' : ''}'
                  '${hasGeo ? ' · 🛰️ GPS' : ''}'
                  '${isBusiness ? ' · Business' : ''}'
                  '${d['featuredBusiness'] == true ? ' · ★Featured' : ''}'
                  '${blocked ? ' · ⛔ BLOCKED' : ''}',
                  style: blocked
                      ? const TextStyle(color: Colors.red)
                      : null,
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
                            Icon(Icons.map_outlined,
                                size: 20, color: kPakGreen),
                            SizedBox(width: 10),
                            Text('View on map'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'message',
                      child: Row(
                        children: [
                          Icon(Icons.campaign_outlined,
                              size: 20, color: kPakGreen),
                          SizedBox(width: 10),
                          Text('Send message'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'warn',
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 20, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Issue warning'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(blocked ? Icons.lock_open : Icons.block,
                              size: 20,
                              color: blocked ? Colors.green : Colors.red),
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
                            Text(d['featuredBusiness'] == true
                                ? 'Unfeature business'
                                : 'Feature business'),
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
                title: Text('${d['type'] ?? 'purchase'} · ${formatPrice('$amount')}'),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                          onPressed: () =>
                              docs[i].reference.delete(),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                            onPressed: () =>
                                docs[i].reference.update({'status': 'rejected'}),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                            onPressed: () =>
                                docs[i].reference.update({'status': 'rejected'}),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () async {
                              if (userId.isEmpty || amount <= 0) return;
                              final fs = FirebaseFirestore.instance;
                              final topupRef = docs[i].reference;
                              final userRef = fs.collection('users').doc(userId);
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
                                  userRef.collection('walletTransactions').doc(),
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
            revenue += (m['commission'] as num?)?.toDouble() ?? amt * commissionRate;
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
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
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
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
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
                          onPressed: () => ref.update({'isSold': !l.isSold}),
                          icon: Icon(
                            l.isSold ? Icons.shopping_bag : Icons.sell,
                            size: 18,
                          ),
                          label: Text(l.isSold ? 'Mark available' : 'Mark sold'),
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
                return Center(child: Text('Error loading chats: ${snapshot.error}'));
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
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
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
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
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
                            listingTitle: data['listingTitle']?.toString() ?? '',
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
          return Center(child: Text('Error loading appeals: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final at = ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
            final bt = ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
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
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resolve appeal: $e')),
        );
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
            final at = ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
            final bt = ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
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
                            builder: (_) =>
                                AdDetailsScreen(listing: listing),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad approved — now live')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reject: $e')),
        );
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
                const Text(
                  'Turn on only what this staff member should manage.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
                return Center(child: Text('Error loading staff: ${snapshot.error}'));
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
            final at = ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
            final bt = ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
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
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            'Requested ${timeAgo(d['createdAt'] as Timestamp?)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
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
