part of '../main.dart';

// Wallet, top-ups and banner ads.

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PakBazar Wallet')),
        body: const EmptyState(
          icon: Icons.account_balance_wallet,
          title: 'Please log in',
        ),
      );
    }
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    return Scaffold(
      appBar: AppBar(title: const Text('PakBazar Wallet')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: userRef.snapshots(),
            builder: (context, snapshot) {
              // Showing "Rs 0" while loading told the user their wallet was
              // empty. Distinguish "not loaded yet" from "actually zero" —
              // and on an error show a dash rather than spinning forever.
              final failed = snapshot.hasError;
              final hasValue = snapshot.hasData && !failed;
              final balance =
                  ((snapshot.data?.data()
                              as Map<String, dynamic>?)?['walletBalance']
                          as num?)
                      ?.toInt() ??
                  0;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPakGreen, kPakGreenLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Wallet balance',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    if (failed)
                      const SizedBox(
                        height: 41,
                        child: Center(
                          child: Text(
                            'Balance unavailable',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      )
                    else if (!hasValue)
                      const SizedBox(
                        height: 41,
                        child: Center(
                          child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        formatPrice('$balance'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kPakGreen,
                          ),
                          onPressed: () => showTopupSheet(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Top up'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          onPressed: balance <= 0
                              ? null
                              : () => showWithdrawSheet(context, balance),
                          icon: const Icon(Icons.account_balance),
                          label: const Text('Withdraw'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Transactions', style: AppType.sectionTitle),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: userRef
                  .collection('walletTransactions')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const EmptyState(
                    icon: Icons.error_outline,
                    title: 'Couldn’t load transactions',
                    subtitle: 'Please try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No transactions yet',
                    subtitle: 'Top-ups and purchases appear here.',
                  );
                }
                return SurfacePanel(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      final credit = d['type'] == 'credit';
                      final amount = (d['amount'] as num?)?.toInt() ?? 0;
                      return ListTile(
                        leading: Icon(
                          credit ? Icons.south_west : Icons.north_east,
                          color: credit ? AppColors.success : AppColors.error,
                        ),
                        title: Text(
                          credit ? 'Top-up' : 'Purchase: ${d['purpose'] ?? ''}',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          timeAgo(d['createdAt'] as Timestamp?),
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        trailing: Text(
                          '${credit ? '+' : '-'} ${formatPrice('$amount')}',
                          style: TextStyle(
                            color: credit ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets a seller request a payout to their own bank / mobile-wallet account.
/// Saves the payout details on the user doc and creates a withdrawal request;
/// a Cloud Function reserves the balance and an admin pays it out.
Future<void> showWithdrawSheet(BuildContext context, int balance) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final messenger = ScaffoldMessenger.of(context);
  final snap = await userRef.get();
  final d = snap.data();
  if (!context.mounted) return;

  final bank = TextEditingController(text: d?['payoutBank']?.toString() ?? '');
  final title = TextEditingController(
    text: d?['payoutTitle']?.toString() ?? '',
  );
  final number = TextEditingController(
    text: d?['payoutNumber']?.toString() ?? '',
  );
  final amount = TextEditingController();
  // Guards against a double tap creating two withdrawals documents, each of
  // which reserves the amount against the seller's balance.
  final submitting = ValueNotifier<bool>(false);
  // The sheet is swipe-dismissible even while the button is disabled, so the
  // write can outlive it. Without this guard the completion handlers below
  // would touch a disposed notifier.
  var sheetGone = false;
  void setSubmitting(bool v) {
    if (!sheetGone) submitting.value = v;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Withdraw to your account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Available: ${formatPrice('$balance')}',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bank,
                decoration: const InputDecoration(
                  labelText: 'Bank / wallet (e.g. Meezan, JazzCash)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Account title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: number,
                decoration: const InputDecoration(
                  labelText: 'Account / IBAN / mobile number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: submitting,
                builder: (context, busy, _) => ElevatedButton.icon(
                onPressed: busy ? null : () async {
                  final amt = int.tryParse(
                    amount.text.replaceAll(RegExp(r'[^0-9]'), ''),
                  );
                  if (amt == null || amt <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Enter a valid amount')),
                    );
                    return;
                  }
                  if (amt > balance) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Amount exceeds your balance'),
                      ),
                    );
                    return;
                  }
                  if (bank.text.trim().isEmpty ||
                      title.text.trim().isEmpty ||
                      number.text.trim().isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Fill in your payout account details'),
                      ),
                    );
                    return;
                  }
                  setSubmitting(true);
                  try {
                    await userRef.set({
                      'payoutBank': bank.text.trim(),
                      'payoutTitle': title.text.trim(),
                      'payoutNumber': number.text.trim(),
                    }, SetOptions(merge: true));
                    await FirebaseFirestore.instance
                        .collection('withdrawals')
                        .add({
                          'userId': uid,
                          'userEmail':
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          'amount': amt,
                          'payoutBank': bank.text.trim(),
                          'payoutTitle': title.text.trim(),
                          'payoutNumber': number.text.trim(),
                          'status': 'pending',
                          'createdAt': Timestamp.now(),
                        });
                    // Clear the guard regardless: if the sheet's context is
                    // already unmounted it never pops, and leaving this true
                    // would leave the button permanently disabled.
                    setSubmitting(false);
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Withdrawal requested — the admin will pay out to '
                          'your account.',
                        ),
                      ),
                    );
                  } catch (e) {
                    // Previously a failed write gave the user no feedback at
                    // all, so a withdrawal that never happened looked
                    // identical to one that did.
                    setSubmitting(false);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Could not request withdrawal: $e'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.account_balance),
                label: Text(
                  busy ? 'Requesting…' : 'Request withdrawal',
                ),
              ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your balance is held while the payout is processed. If it is '
                'rejected, the amount is refunded to your wallet.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    },
  );
  bank.dispose();
  title.dispose();
  number.dispose();
  amount.dispose();
  sheetGone = true;
  submitting.dispose();
}

/// Lets a business upload a home-screen banner ad and request a slot.
class BannerAdScreen extends StatefulWidget {
  const BannerAdScreen({super.key});

  @override
  State<BannerAdScreen> createState() => _BannerAdScreenState();
}

class _BannerAdScreenState extends State<BannerAdScreen> {
  final picker = ImagePicker();
  final titleController = TextEditingController();
  final subtitleController = TextEditingController();
  String? imageUrl;
  bool uploading = false;
  bool submitting = false;
  PromoPackage? selected;

  static const bannerPackages = [
    PromoPackage('Home banner · 7 days', 7, 2000),
    PromoPackage('Home banner · 30 days', 30, 6000),
  ];

  @override
  void dispose() {
    titleController.dispose();
    subtitleController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: kUploadImageQuality,
      maxWidth: kUploadImageMaxWidth,
    );
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('banners')
          .child(uid)
          .child('ad_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, imageUploadMetadata());
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (imageUrl == null || selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a banner image and pick a package')),
      );
      return;
    }
    setState(() => submitting = true);
    final ok = await payFromWallet(
      context,
      type: 'banner',
      amount: selected!.price,
      days: selected!.days,
      extra: {
        'imageUrl': imageUrl,
        'bannerTitle': titleController.text.trim(),
        'bannerSubtitle': subtitleController.text.trim(),
      },
    );
    if (!mounted) return;
    setState(() => submitting = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy a Home Banner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.navClearance,
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Promote your business with a banner on the home screen.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                AspectRatio(
                  aspectRatio: 16 / 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      image: imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: imageUrl == null
                        ? const Center(
                            child: Text('Banner preview (≈ 1000×360)'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: uploading ? null : _pickAndUpload,
                  icon: uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image),
                  label: Text(
                    uploading
                        ? 'Uploading…'
                        : (imageUrl == null
                              ? 'Upload banner image'
                              : 'Change image'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Headline (e.g. "Eid Sale at Ali Mobiles")',
                  ),
                ),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle (optional)',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose a package',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioGroup<PromoPackage>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  child: Column(
                    children: [
                      for (final p in bannerPackages)
                        RadioListTile<PromoPackage>(
                          value: p,
                          title: Text(p.name),
                          secondary: Text(
                            formatPrice(p.price.toString()),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: submitting ? null : _submit,
                  child: Text(submitting ? 'Sending…' : 'Submit request'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Paid instantly from your PakBazar Wallet (Profile → Wallet).',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
