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
                    Text(
                      formatPrice('$balance'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: kPakGreen,
                      ),
                      onPressed: () => showTopupSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Top up'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Transactions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
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
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final credit = d['type'] == 'credit';
                    final amount = (d['amount'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      leading: Icon(
                        credit ? Icons.south_west : Icons.north_east,
                        color: credit ? Colors.green : Colors.red,
                      ),
                      title: Text(
                        credit ? 'Top-up' : 'Purchase: ${d['purpose'] ?? ''}',
                      ),
                      subtitle: Text(timeAgo(d['createdAt'] as Timestamp?)),
                      trailing: Text(
                        '${credit ? '+' : '-'} ${formatPrice('$amount')}',
                        style: TextStyle(
                          color: credit ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('banners')
          .child('ad_${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
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
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Promote your business with a banner on the home screen.',
                  style: TextStyle(color: Colors.grey),
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
                const Text(
                  'Paid instantly from your PakBazar Wallet (Profile → Wallet).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
