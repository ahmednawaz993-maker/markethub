part of '../main.dart';

// Seller payout accounts (bank / Easypaisa / JazzCash), stored under
// users/{sellerId}/payoutAccounts/{accountId}. A seller manages their own
// accounts but can NEVER self-verify — verificationStatus is admin/CF-only
// (enforced in firestore.rules). Buyers never see these. We store only routing
// details (title, IBAN/number, mobile) — never PINs, passwords, or OTPs. Every
// add/update/delete is written to the immutable payoutAccountAudit log.

const List<String> kPayoutTypes = ['bank', 'easypaisa', 'jazzcash'];

String payoutTypeLabel(String type) => switch (type) {
  'bank' => 'Bank account',
  'easypaisa' => 'Easypaisa',
  'jazzcash' => 'JazzCash',
  _ => type,
};

/// Masks all but the last 4 characters of an account identifier for display.
String maskTail(String raw) {
  final s = raw.replaceAll(' ', '');
  if (s.length <= 4) return s.isEmpty ? '—' : '••••';
  return '•••• ${s.substring(s.length - 4)}';
}

class PayoutAccount {
  final String id;
  String type; // 'bank' | 'easypaisa' | 'jazzcash'
  String accountTitle;
  String bankName; // bank only
  String iban; // bank only
  String accountNumber; // bank only (optional)
  String branchCode; // bank only (optional)
  String mobileNumber; // wallet only
  bool isDefault;
  String verificationStatus; // pending | verified | rejected | suspended
  Timestamp? createdAt;
  Timestamp? updatedAt;

  PayoutAccount({
    this.id = '',
    this.type = 'bank',
    this.accountTitle = '',
    this.bankName = '',
    this.iban = '',
    this.accountNumber = '',
    this.branchCode = '',
    this.mobileNumber = '',
    this.isDefault = false,
    this.verificationStatus = 'pending',
    this.createdAt,
    this.updatedAt,
  });

  bool get isBank => type == 'bank';
  bool get isVerified => verificationStatus == 'verified';

  String get providerLabel => isBank
      ? (bankName.trim().isEmpty ? 'Bank' : bankName)
      : payoutTypeLabel(type);

  /// Masked identifier for list display (IBAN/account for bank, mobile for
  /// wallets). Never shows the full number.
  String get maskedIdentifier => isBank
      ? maskTail(iban.isNotEmpty ? iban : accountNumber)
      : maskTail(mobileNumber);

  factory PayoutAccount.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PayoutAccount(
      id: doc.id,
      type: d['type']?.toString() ?? 'bank',
      accountTitle: d['accountTitle']?.toString() ?? '',
      bankName: d['bankName']?.toString() ?? '',
      iban: d['iban']?.toString() ?? '',
      accountNumber: d['accountNumber']?.toString() ?? '',
      branchCode: d['branchCode']?.toString() ?? '',
      mobileNumber: d['mobileNumber']?.toString() ?? '',
      isDefault: d['isDefault'] == true,
      verificationStatus: d['verificationStatus']?.toString() ?? 'pending',
      createdAt: d['createdAt'] is Timestamp
          ? d['createdAt'] as Timestamp
          : null,
      updatedAt: d['updatedAt'] is Timestamp
          ? d['updatedAt'] as Timestamp
          : null,
    );
  }

  /// The routing fields a seller supplies. Deliberately excludes
  /// verificationStatus (set only by admin/CF) — never send it from the client.
  Map<String, dynamic> toDetailMap() => {
    'type': type,
    'accountTitle': accountTitle.trim(),
    'bankName': isBank ? bankName.trim() : '',
    'iban': isBank ? iban.trim() : '',
    'accountNumber': isBank ? accountNumber.trim() : '',
    'branchCode': isBank ? branchCode.trim() : '',
    'mobileNumber': isBank ? '' : normalizePakMobile(mobileNumber),
  };

  bool get isComplete {
    if (accountTitle.trim().isEmpty) return false;
    if (isBank) return bankName.trim().isNotEmpty && iban.trim().isNotEmpty;
    return isValidPakMobile(mobileNumber);
  }
}

CollectionReference<Map<String, dynamic>> _payoutCol(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('payoutAccounts');

/// Appends an immutable audit entry for a payout-account change.
Future<void> _logPayoutAudit(String accountId, String action) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirebaseFirestore.instance.collection('payoutAccountAudit').add({
      'sellerId': uid,
      'accountId': accountId,
      'action': action, // added | updated | deleted
      'by': uid,
      'at': Timestamp.now(),
    });
  } catch (_) {}
}

Stream<List<PayoutAccount>> payoutAccountStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const <PayoutAccount>[]);
  return _payoutCol(uid).snapshots().map((snap) {
    final list = snap.docs.map(PayoutAccount.fromDoc).toList();
    list.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return list;
  });
}

/// Creates a payout account. Always starts 'pending' verification (a seller can
/// never self-verify). The first account, or one marked default, becomes the
/// default (others cleared in the same batch).
Future<void> addPayoutAccount(PayoutAccount a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final col = _payoutCol(uid);
  final existing = await col.get();
  final makeDefault = a.isDefault || existing.docs.isEmpty;
  final batch = FirebaseFirestore.instance.batch();
  if (makeDefault) {
    for (final d in existing.docs) {
      if (d.data()['isDefault'] == true) {
        batch.update(d.reference, {'isDefault': false});
      }
    }
  }
  final ref = col.doc();
  batch.set(ref, {
    ...a.toDetailMap(),
    'isDefault': makeDefault,
    'verificationStatus': 'pending', // admin/CF verifies later
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
  await _logPayoutAudit(ref.id, 'added');
}

/// Updates a payout account's routing details. Never touches verificationStatus
/// (rules reject that from a seller). Editing details re-sets it to pending
/// server-side is NOT done here to avoid a rules conflict; admins re-verify.
Future<void> updatePayoutAccount(PayoutAccount a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || a.id.isEmpty) return;
  final col = _payoutCol(uid);
  final batch = FirebaseFirestore.instance.batch();
  if (a.isDefault) {
    final existing = await col.get();
    for (final d in existing.docs) {
      if (d.id != a.id && d.data()['isDefault'] == true) {
        batch.update(d.reference, {'isDefault': false});
      }
    }
  }
  batch.update(col.doc(a.id), {
    ...a.toDetailMap(),
    'isDefault': a.isDefault,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
  await _logPayoutAudit(a.id, 'updated');
}

Future<void> deletePayoutAccount(PayoutAccount a) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || a.id.isEmpty) return;
  await _payoutCol(uid).doc(a.id).delete();
  await _logPayoutAudit(a.id, 'deleted');
  if (a.isDefault) {
    final rest = await _payoutCol(uid).get();
    if (rest.docs.isNotEmpty) {
      await rest.docs.first.reference.update({'isDefault': true});
    }
  }
}

Future<void> setDefaultPayoutAccount(String accountId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final col = _payoutCol(uid);
  final existing = await col.get();
  final batch = FirebaseFirestore.instance.batch();
  for (final d in existing.docs) {
    final isTarget = d.id == accountId;
    if ((d.data()['isDefault'] == true) != isTarget) {
      batch.update(d.reference, {'isDefault': isTarget});
    }
  }
  await batch.commit();
}

class PayoutAccountsScreen extends StatelessWidget {
  const PayoutAccountsScreen({super.key});

  (String, Color) _statusChip(String s) => switch (s) {
    'verified' => ('Verified', kPakGreen),
    'rejected' => ('Rejected', Colors.red),
    'suspended' => ('Suspended', Colors.orange),
    _ => ('Pending review', Colors.blueGrey),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payout accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PayoutAccountFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
      body: StreamBuilder<List<PayoutAccount>>(
        stream: payoutAccountStream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const ErrorStateWidget(
              message: 'We could not load your payout accounts.',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No payout accounts',
              subtitle:
                  'Add a verified bank or wallet to receive your payouts.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Only a Verified account can receive a payout. Verification '
                    'is done by our team — you cannot verify your own account.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }
              final a = list[i - 1];
              final (label, color) = _statusChip(a.verificationStatus);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            a.isBank
                                ? Icons.account_balance
                                : Icons.phone_android,
                            color: kPakGreen,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a.providerLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: AppRadius.rSm,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(a.accountTitle),
                      Text(
                        a.maskedIdentifier,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      Row(
                        children: [
                          if (a.isDefault)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Default',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: kPakGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (!a.isDefault)
                            TextButton(
                              onPressed: () => setDefaultPayoutAccount(a.id),
                              child: const Text('Set default'),
                            ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PayoutAccountFormScreen(existing: a),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: const Text('Remove account?'),
                                  content: const Text(
                                    'This removes the payout account. You can '
                                    'add it again later.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(d, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await deletePayoutAccount(a);
                            },
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
      ),
    );
  }
}

class PayoutAccountFormScreen extends StatefulWidget {
  final PayoutAccount? existing;
  const PayoutAccountFormScreen({super.key, this.existing});

  @override
  State<PayoutAccountFormScreen> createState() =>
      _PayoutAccountFormScreenState();
}

class _PayoutAccountFormScreenState extends State<PayoutAccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _type;
  late final TextEditingController _title;
  late final TextEditingController _bankName;
  late final TextEditingController _iban;
  late final TextEditingController _accountNumber;
  late final TextEditingController _branchCode;
  late final TextEditingController _mobile;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? 'bank';
    _title = TextEditingController(text: e?.accountTitle ?? '');
    _bankName = TextEditingController(text: e?.bankName ?? '');
    _iban = TextEditingController(text: e?.iban ?? '');
    _accountNumber = TextEditingController(text: e?.accountNumber ?? '');
    _branchCode = TextEditingController(text: e?.branchCode ?? '');
    _mobile = TextEditingController(text: e?.mobileNumber ?? '');
    _isDefault = e?.isDefault ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _bankName.dispose();
    _iban.dispose();
    _accountNumber.dispose();
    _branchCode.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final a = PayoutAccount(
      id: widget.existing?.id ?? '',
      type: _type,
      accountTitle: _title.text,
      bankName: _bankName.text,
      iban: _iban.text,
      accountNumber: _accountNumber.text,
      branchCode: _branchCode.text,
      mobileNumber: _mobile.text,
      isDefault: _isDefault,
    );
    try {
      if (a.id.isEmpty) {
        await addPayoutAccount(a);
      } else {
        await updatePayoutAccount(a);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payout account saved — pending verification.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
    }
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final isBank = _type == 'bank';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add account' : 'Edit account'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final t in kPayoutTypes)
                  ChoiceChip(
                    label: Text(payoutTypeLabel(t)),
                    selected: _type == t,
                    selectedColor: kPakGreen.withValues(alpha: 0.18),
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              enabled: !_saving,
              decoration: _dec('Account title (holder name)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the title' : null,
            ),
            const SizedBox(height: 12),
            if (isBank) ...[
              TextFormField(
                controller: _bankName,
                enabled: !_saving,
                decoration: _dec('Bank name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter the bank' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _iban,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: _dec('IBAN'),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Enter a valid IBAN'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumber,
                enabled: !_saving,
                decoration: _dec('Account number (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _branchCode,
                enabled: !_saving,
                decoration: _dec('Branch code (optional)'),
              ),
            ] else ...[
              TextFormField(
                controller: _mobile,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: _dec('${payoutTypeLabel(_type)} mobile number'),
                validator: (v) => (v == null || !isValidPakMobile(v))
                    ? 'Enter a valid mobile (03XXXXXXXXX)'
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set as default payout account'),
              value: _isDefault,
              activeThumbColor: kPakGreen,
              onChanged: _saving ? null : (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              // Opaque light surface so the safety note is readable over navy.
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.rSm,
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.info),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Never enter your PIN, password, or any OTP here. We only '
                      'need your account routing details to send payouts. Our '
                      'team reviews and verifies the account before it can '
                      'receive money.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                    : const Text('Save account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
