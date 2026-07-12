part of '../main.dart';

// My ads, seller analytics and editing.

/// Small coloured pill used on My Ads to show an ad's moderation status.
Widget _statusChip(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    ),
  );
}

/// Seller-facing sales & earnings dashboard: realized earnings, gross sales,
/// commission paid, money held in escrow, pending COD, wallet balance, and a
/// 6-month earnings trend. All figures are the signed-in seller's own.
class SalesDashboardScreen extends StatelessWidget {
  const SalesDashboardScreen({super.key});

  static const _realized = {'released', 'completed'};

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      // Opaque light tile so the value + label are readable over the navy
      // gradient (a translucent tint let the navy bleed through).
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales & Earnings')),
        body: const Center(
          child: Text(
            'Please log in',
            style: TextStyle(color: AppColors.onNavyMuted),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Sales & Earnings')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('sellerId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Couldn’t load your sales. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onNavyMuted),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();

          double earnings = 0, gross = 0, commissionPaid = 0, inEscrow = 0;
          double codPending = 0;
          int sold = 0, escrowCount = 0, codCount = 0;

          // Last 6 months earnings buckets (oldest -> newest).
          final now = DateTime.now();
          final months = [
            for (int i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
          ];
          final monthEarn = {
            for (final m in months) '${m.year}-${m.month}': 0.0,
          };

          for (final o in orders) {
            final status = o['status']?.toString() ?? '';
            final amount = (o['amount'] as num?)?.toDouble() ?? 0;
            final payout = (o['sellerPayout'] as num?)?.toDouble() ?? amount;
            final comm = (o['commission'] as num?)?.toDouble() ?? 0;
            if (_realized.contains(status)) {
              earnings += payout;
              gross += amount;
              commissionPaid += comm;
              sold++;
              final ts = (o['completedAt'] ?? o['createdAt']) as Timestamp?;
              if (ts != null) {
                final d = ts.toDate();
                final key = '${d.year}-${d.month}';
                if (monthEarn.containsKey(key)) {
                  monthEarn[key] = monthEarn[key]! + payout;
                }
              }
            } else if (status == 'in_escrow') {
              inEscrow += payout;
              escrowCount++;
            } else if (status == 'cod_pending') {
              codPending += amount;
              codCount++;
            }
          }

          final maxMonth = monthEarn.values.fold<double>(
            0,
            (a, b) => b > a ? b : a,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Headline earnings.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPakGreen, kPakGreenLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total earnings',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatPrice(earnings.toStringAsFixed(0)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$sold item(s) sold${commissionActive ? ' · after 2% commission' : ' · 0% fee (free)'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metric(
                    'Gross sales',
                    formatPrice(gross.toStringAsFixed(0)),
                    Icons.point_of_sale,
                    kPakGreen,
                  ),
                  _metric(
                    'Commission paid',
                    formatPrice(commissionPaid.toStringAsFixed(0)),
                    Icons.percent,
                    Colors.deepOrange,
                  ),
                  _metric(
                    'In escrow ($escrowCount)',
                    formatPrice(inEscrow.toStringAsFixed(0)),
                    Icons.lock_clock,
                    Colors.blue,
                  ),
                  _metric(
                    'COD pending ($codCount)',
                    formatPrice(codPending.toStringAsFixed(0)),
                    Icons.local_shipping,
                    Colors.purple,
                  ),
                ],
              ),
              if (monetizationEnabled.value) ...[
                const SizedBox(height: 10),
                // Wallet balance (separate stream on the user doc).
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, us) {
                    final bal =
                        ((us.data?.data()
                                    as Map<String, dynamic>?)?['walletBalance']
                                as num?)
                            ?.toInt() ??
                        0;
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet,
                          color: kPakGreen,
                        ),
                        title: const Text('Available wallet balance'),
                        subtitle: Text(formatPrice('$bal')),
                        trailing: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WalletScreen(),
                            ),
                          ),
                          child: const Text('Wallet'),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Earnings — last 6 months',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.onNavy,
                ),
              ),
              const SizedBox(height: 10),
              if (sold == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No completed sales yet. Your earnings will show here.',
                      style: TextStyle(color: AppColors.onNavyMuted),
                    ),
                  ),
                )
              else
                for (final m in months)
                  _MonthBar(
                    label: _monthLabel(m),
                    value: monthEarn['${m.year}-${m.month}'] ?? 0,
                    max: maxMonth,
                  ),
            ],
          );
        },
      ),
    );
  }

  static String _monthLabel(DateTime m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[m.month - 1]} ${m.year % 100}';
  }
}

/// Short month label like "Jun 26" for trend charts.
String monthShortLabel(DateTime m) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${names[m.month - 1]} ${m.year % 100}';
}

/// A single horizontal bar for a 6-month trend. [money] formats the value as a
/// price; otherwise it shows a plain count.
class _MonthBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final bool money;
  const _MonthBar({
    required this.label,
    required this.value,
    required this.max,
    this.money = true,
  });

  @override
  Widget build(BuildContext context) {
    final frac = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.onNavy),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Container(
                    height: 22,
                    width: c.maxWidth * frac,
                    decoration: BoxDecoration(
                      color: kPakGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              money
                  ? formatPrice(value.toStringAsFixed(0))
                  : '${value.toInt()}',
              style: const TextStyle(fontSize: 11, color: AppColors.onNavy),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class SellerAnalyticsScreen extends StatelessWidget {
  const SellerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ads = snapshot.data!.docs
              .map((d) => Listing.fromDoc(d))
              .toList();
          if (ads.isEmpty) {
            return const EmptyState(
              icon: Icons.bar_chart,
              title: 'No data yet',
              subtitle: 'Post ads to start seeing views and leads.',
            );
          }
          int views = 0, calls = 0, chats = 0, waps = 0, sold = 0;
          for (final a in ads) {
            views += a.views;
            calls += a.calls;
            chats += a.chats;
            waps += a.whatsapps;
            if (a.isSold) sold++;
          }
          final leads = calls + chats + waps;
          final top = [...ads]
            ..sort(
              (a, b) => (b.calls + b.chats + b.whatsapps + b.views).compareTo(
                a.calls + a.chats + a.whatsapps + a.views,
              ),
            );
          final maxViews = ads
              .map((a) => a.views)
              .fold<int>(1, (m, v) => v > m ? v : m);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statCard(Icons.remove_red_eye, '$views', 'Views'),
                  _statCard(Icons.call, '$calls', 'Calls'),
                  _statCard(Icons.chat, '$chats', 'Chats'),
                  _statCard(Icons.whatshot, '$waps', 'WhatsApp'),
                  _statCard(Icons.trending_up, '$leads', 'Total leads'),
                  _statCard(Icons.inventory_2, '${ads.length}', 'Active ads'),
                  _statCard(Icons.sell, '$sold', 'Sold'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Top performing ads',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ...top.take(10).map((a) {
                final l = a.calls + a.chats + a.whatsapps;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title.isEmpty ? '(untitled)' : a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (a.views / maxViews).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(kPakGreen),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${a.views} views · $l leads '
                          '(📞 ${a.calls}  💬 ${a.chats}  🟢 ${a.whatsapps})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return SizedBox(
      width: 108,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: kPakGreen, size: 26),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick seller action to reduce an ad's price — records the drop so cards show
/// the "Price dropped" badge and savers/followers get alerted.
Future<void> showLowerPriceSheet(BuildContext context, Listing listing) async {
  final current = parsePrice(listing.price);
  final controller = TextEditingController();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Lower the price',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current price: ${formatPrice(listing.price)}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A lower price shows a "Price dropped" badge and alerts '
                  'everyone who saved this ad or follows you.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'New price (Rs)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final newP = double.tryParse(
                      controller.text.replaceAll(RegExp(r'[^0-9.]'), ''),
                    );
                    if (newP == null || newP <= 0) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount')),
                      );
                      return;
                    }
                    if (current > 0 && newP >= current) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'New price must be lower than the current price',
                          ),
                        ),
                      );
                      return;
                    }
                    await FirebaseFirestore.instance
                        .collection('listings')
                        .doc(listing.id)
                        .update({
                          'price': newP.toStringAsFixed(0),
                          'previousPrice': listing.price,
                          'priceDropAt': Timestamp.now(),
                        });
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Price lowered — buyers will be notified',
                        ),
                      ),
                    );
                  },
                  child: const Text('Lower price'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
}

class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ads'),
        actions: [
          IconButton(
            tooltip: 'Analytics',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SellerAnalyticsScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Couldn’t load your ads. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onNavyMuted),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No ads posted yet',
              subtitle: 'Tap the green SELL button to post your first ad.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final listing = Listing.fromDoc(docs[index]);
              final images = listing.galleryImages;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: images.isEmpty
                      ? const Icon(Icons.image, size: 40)
                      : Image.network(
                          images.first,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.image, size: 40);
                          },
                        ),
                  title: Row(
                    children: [
                      Flexible(child: Text(listing.title)),
                      if (listing.isCurrentlyFeatured) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 16, color: kGold),
                      ],
                      if (listing.approvalStatus == 'pending') ...[
                        const SizedBox(width: 6),
                        _statusChip('Pending review', Colors.orange),
                      ] else if (listing.approvalStatus == 'rejected') ...[
                        const SizedBox(width: 6),
                        _statusChip('Rejected', Colors.red),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${[listing.city, listing.location].where((e) => e.isNotEmpty).join(', ')}'
                    '${listing.subcategory.isEmpty ? '' : ' • ${listing.subcategory}'}'
                    '\n👁 ${listing.views}  📞 ${listing.calls}  '
                    '💬 ${listing.chats}  🟢 ${listing.whatsapps}',
                  ),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditListingScreen(listing: listing),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Bump to top',
                        icon: const Icon(Icons.arrow_upward, color: kPakGreen),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final created = listing.createdAt?.toDate();
                          if (created != null &&
                              DateTime.now().difference(created).inHours < 24) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Still recent — you can bump 24h after '
                                  'posting or your last bump.',
                                ),
                              ),
                            );
                            return;
                          }
                          await FirebaseFirestore.instance
                              .collection('listings')
                              .doc(listing.id)
                              .update({'createdAt': Timestamp.now()});
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Bumped to the top!')),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: listing.isFeatured
                            ? 'Featured'
                            : 'Promote (Feature)',
                        icon: Icon(
                          listing.isFeatured
                              ? Icons.star
                              : Icons.campaign_outlined,
                          color: kGold,
                        ),
                        onPressed: () => showPromoteSheet(context, listing),
                      ),
                      IconButton(
                        tooltip:
                            'Inventory status'
                            '${listing.statusLabel.isEmpty ? '' : ' · ${listing.statusLabel}'}',
                        icon: Icon(
                          listing.isAvailableForSale
                              ? Icons.inventory_2_outlined
                              : Icons.inventory_2,
                          color: listing.isAvailableForSale
                              ? Colors.grey
                              : Colors.red,
                        ),
                        onPressed: () => showInventorySheet(context, listing),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) async {
                          if (value == 'lower') {
                            showLowerPriceSheet(context, listing);
                          } else if (value == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Delete ad?'),
                                content: const Text(
                                  'This permanently removes the ad and '
                                  'cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await FirebaseFirestore.instance
                                  .collection('listings')
                                  .doc(listing.id)
                                  .delete();
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (!listing.isSold)
                            const PopupMenuItem(
                              value: 'lower',
                              child: ListTile(
                                leading: Icon(
                                  Icons.south,
                                  color: Colors.deepOrange,
                                ),
                                title: Text('Lower price'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('Delete'),
                              contentPadding: EdgeInsets.zero,
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
      ),
    );
  }
}

class EditListingScreen extends StatefulWidget {
  final Listing listing;

  const EditListingScreen({super.key, required this.listing});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  late TextEditingController titleController;
  late TextEditingController priceController;
  late TextEditingController deliveryFeeController;
  late TextEditingController locationController;
  late TextEditingController phoneController;
  late TextEditingController descriptionController;
  late String selectedCategory;
  late String selectedSubcategory;
  late String selectedCondition;
  late String selectedUnit;
  late bool deliveryAvailable;
  late bool codAvailable;
  late bool negotiable;
  final Map<String, TextEditingController> attrControllers = {};
  late String selectedCity;

  TextEditingController _attrCtrl(String label) => attrControllers.putIfAbsent(
    label,
    () => TextEditingController(text: widget.listing.attributes[label] ?? ''),
  );
  double? latitude;
  double? longitude;
  bool isLocating = false;

  final ImagePicker picker = ImagePicker();
  List<XFile> newImages = [];
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    latitude = widget.listing.latitude;
    longitude = widget.listing.longitude;

    titleController = TextEditingController(text: widget.listing.title);
    priceController = TextEditingController(text: widget.listing.price);
    deliveryFeeController = TextEditingController(
      text: widget.listing.deliveryFee,
    );
    locationController = TextEditingController(text: widget.listing.location);
    phoneController = TextEditingController(text: widget.listing.phone);
    descriptionController = TextEditingController(
      text: widget.listing.description,
    );
    selectedCategory = widget.listing.category.isEmpty
        ? 'Motors'
        : widget.listing.category;
    // Validate the saved subcategory against the current category's list so the
    // state variable matches what the dropdown displays (which falls back to
    // subcategories.first for a missing/invalid value). Keeps Update from
    // persisting a stale value the user never sees, and avoids a dropdown
    // assertion when value isn't in items.
    final initSubcategories = categoryByTitle(selectedCategory).subcategories;
    selectedSubcategory = initSubcategories.contains(widget.listing.subcategory)
        ? widget.listing.subcategory
        : initSubcategories.first;
    selectedCondition = itemConditions.contains(widget.listing.condition)
        ? widget.listing.condition
        : 'Used';
    selectedUnit = pricingUnits.contains(widget.listing.unit)
        ? widget.listing.unit
        : 'None';
    deliveryAvailable = widget.listing.deliveryAvailable;
    codAvailable = widget.listing.codAvailable;
    negotiable = widget.listing.negotiable;
    // Keep the saved place, including a custom town/village not in the list.
    selectedCity = widget.listing.city.isNotEmpty
        ? widget.listing.city
        : 'Karachi';
  }

  Future<void> useCurrentLocation() async {
    setState(() => isLocating = true);
    try {
      final position = await determineCurrentPosition();
      if (!mounted) return;
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Current location updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> pickImages() async {
    final imgs = await picker.pickMultiImage();
    if (imgs.isNotEmpty) setState(() => newImages = imgs);
  }

  Future<List<String>> uploadImages() async {
    final urls = <String>[];
    for (var i = 0; i < newImages.length; i++) {
      final bytes = await newImages[i].readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('listings')
          .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> updateListing() async {
    // Match submitListing's guards so an edit can't blank out required fields or
    // save a zero/invalid price (which would make cards show "Rs" with no amount
    // and record amount:0 on any resulting order).
    if (titleController.text.trim().isEmpty ||
        priceController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title, price, and location')),
      );
      return;
    }
    if (parsePrice(priceController.text.trim()) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }
    if (normalizePhoneForWhatsApp(phoneController.text.trim()).length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }
    setState(() => isSaving = true);
    try {
      final data = <String, dynamic>{
        'title': titleController.text.trim(),
        'price': priceController.text.trim(),
        'location': locationController.text.trim(),
        'city': selectedCity,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phoneController.text.trim(),
        'description': descriptionController.text.trim(),
        'category': selectedCategory,
        'subcategory': selectedSubcategory,
        'condition': selectedCondition,
        'unit': selectedUnit == 'None' ? '' : selectedUnit,
        'deliveryFee': deliveryAvailable
            ? deliveryFeeController.text.trim()
            : '',
        'deliveryAvailable': deliveryAvailable,
        'codAvailable': codAvailable,
        'negotiable': negotiable,
      };
      final attributes = <String, String>{};
      for (final label in attributeFieldsFor(selectedCategory)) {
        final v = attrControllers[label]?.text.trim() ?? '';
        if (v.isNotEmpty) attributes[label] = v;
      }
      data['attributes'] = attributes;
      if (newImages.isNotEmpty) {
        final urls = await uploadImages();
        data['images'] = urls;
        data['imageUrl'] = urls.isNotEmpty ? urls.first : '';
      }
      // Track price reductions so cards can show a "Price dropped" badge.
      final oldP = parsePrice(widget.listing.price);
      final newP = parsePrice(priceController.text.trim());
      if (newP > 0 && oldP > 0 && newP < oldP) {
        data['previousPrice'] = widget.listing.price;
        data['priceDropAt'] = Timestamp.now();
      } else if (newP != oldP) {
        // Price unchanged-numeric or raised — clear any stale drop marker.
        data['previousPrice'] = '';
        data['priceDropAt'] = FieldValue.delete();
      }
      // Any edit re-enters the moderation queue so changes are reviewed before
      // going live again (also lets a rejected ad be resubmitted by editing).
      // Demo/review accounts stay auto-approved.
      data['approvalStatus'] = isDemoUser() ? 'approved' : 'pending';
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listing.id)
          .update(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved — your ad will be reviewed before going live'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    deliveryFeeController.dispose();
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    for (final c in attrControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = categoryByTitle(selectedCategory).subcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Photos',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (newImages.isNotEmpty)
                        for (final x in newImages)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FutureBuilder<Uint8List>(
                                future: x.readAsBytes(),
                                builder: (context, snap) => snap.hasData
                                    ? Image.memory(
                                        snap.data!,
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 90,
                                        height: 90,
                                        color: Colors.grey.shade300,
                                      ),
                              ),
                            ),
                          )
                      else
                        for (final u in widget.listing.galleryImages)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                u,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 90,
                                  height: 90,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isSaving ? null : pickImages,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(
                    newImages.isEmpty
                        ? 'Change photos'
                        : '${newImages.length} new photo(s) selected',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Price (PKR)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Area / Block'),
                ),
                const SizedBox(height: 12),
                CitySelector(
                  value: selectedCity,
                  label: 'City / Town / Village',
                  allowCustom: true,
                  onChanged: (value) => setState(() => selectedCity = value),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isLocating ? null : useCurrentLocation,
                  icon: isLocating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          latitude != null
                              ? Icons.location_on
                              : Icons.my_location,
                          color: latitude != null ? Colors.green : null,
                        ),
                  label: Text(
                    latitude != null
                        ? 'Current location set ✓'
                        : 'Use my current location',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCondition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: itemConditions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedCondition = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Price unit (optional, e.g. per kg/dozen/plate)',
                  ),
                  items: pricingUnits
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u == 'None' ? 'None' : 'per $u'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => selectedUnit = value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delivery available'),
                  subtitle: const Text('Show a delivery badge on your ad'),
                  value: deliveryAvailable,
                  activeThumbColor: kPakGreen,
                  onChanged: (v) => setState(() => deliveryAvailable = v),
                ),
                if (deliveryAvailable)
                  TextField(
                    controller: deliveryFeeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Delivery fee (PKR, optional)',
                      hintText: 'Leave blank for free delivery',
                      prefixIcon: Icon(Icons.local_shipping),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cash on Delivery'),
                  subtitle: const Text(
                    'Let buyers pay cash when the item arrives',
                  ),
                  value: codAvailable,
                  activeThumbColor: kPakGreen,
                  onChanged: (v) => setState(() => codAvailable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Price negotiable'),
                  subtitle: const Text('Buyers can make an offer'),
                  value: negotiable,
                  activeThumbColor: kPakGreen,
                  onChanged: (v) => setState(() => negotiable = v),
                ),
                for (final label in attributeFieldsFor(selectedCategory))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _attrCtrl(label),
                      decoration: InputDecoration(
                        labelText: '$label (optional)',
                      ),
                    ),
                  ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp / Phone Number *',
                    hintText: 'Example: 03001234567 or +92 300 1234567',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Main Category'),
                  items: appCategories
                      .where((category) => category.title != 'All')
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.title,
                          child: Text(category.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedCategory = value;
                        selectedSubcategory = categoryByTitle(
                          value,
                        ).subcategories.first;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: subcategories.contains(selectedSubcategory)
                      ? selectedSubcategory
                      : subcategories.first,
                  decoration: const InputDecoration(labelText: 'Subcategory'),
                  items: subcategories
                      .map(
                        (subcategory) => DropdownMenuItem(
                          value: subcategory,
                          child: Text(subcategory),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedSubcategory = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isSaving ? null : updateListing,
                  child: isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ad details
// ---------------------------------------------------------------------------

/// Fullscreen, swipeable, pinch-to-zoom image viewer.
