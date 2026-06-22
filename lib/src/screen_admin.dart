part of '../main.dart';

// Admin panel and its tabs.

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 17,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Panel'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Verify ID'),
              Tab(text: 'Payments'),
              Tab(text: 'Escrow'),
              Tab(text: 'Featured'),
              Tab(text: 'Feedback'),
              Tab(text: 'Users'),
              Tab(text: 'Reports'),
              Tab(text: 'Top-ups'),
              Tab(text: 'Payment a/c'),
              Tab(text: 'Withdrawals'),
              Tab(text: 'Promotions'),
              Tab(text: 'Orders'),
              Tab(text: 'Offers'),
              Tab(text: 'Purchases'),
              Tab(text: 'Listings'),
              Tab(text: 'Chats'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminOverviewTab(),
            _AdminVerificationsTab(),
            _AdminPaymentsTab(),
            _AdminEscrowTab(),
            _AdminFeaturedTab(),
            _AdminFeedbackTab(),
            _AdminUsersTab(),
            _AdminReportsTab(),
            _AdminTopupsTab(),
            _AdminPaymentTab(),
            _AdminWithdrawalsTab(),
            _AdminPromotionsTab(),
            _AdminOrdersTab(),
            _AdminOffersTab(),
            _AdminPurchasesTab(),
            _AdminListingsTab(),
            _AdminChatsTab(),
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
            final commission = amount * commissionRate;
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
    return StreamBuilder<QuerySnapshot>(
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
            Widget img(String url) => Expanded(
              child: GestureDetector(
                onTap: url.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FullScreenGallery(images: [selfie, cnic]),
                        ),
                      ),
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
                    if (pending)
                      _VerificationActions(uid: uid, ref: docs[i].reference),
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

/// Approve / reject buttons for a pending verification. Stateful so both
/// buttons disable while the decision is being written — avoids a double-tap
/// applying the change twice and sending duplicate notifications.
class _VerificationActions extends StatefulWidget {
  const _VerificationActions({required this.uid, required this.ref});

  final String uid;
  final DocumentReference ref;

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
      }, SetOptions(merge: true));
      await users.doc(widget.uid).collection('notifications').add(
        approve
            ? {
                'title': 'Identity verified ✓',
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

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
  if (ok != true) return;
  final text = controller.text.trim();
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
  if (ok != true) return;
  await ref.update({
    'blocked': block,
    'blockedAt': block ? Timestamp.now() : FieldValue.delete(),
  });
  final reason = controller.text.trim();
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
          if (m['status'] == 'completed') {
            revenue += (m['commission'] as num?)?.toDouble() ?? 0;
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

// ---------------------------------------------------------------------------
// Notification center
// ---------------------------------------------------------------------------
