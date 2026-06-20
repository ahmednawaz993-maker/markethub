part of '../main.dart';

// Offers.

Future<void> _counterDialog(BuildContext context, DocumentReference ref) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Counter offer'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Your price (Rs)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final amt = double.tryParse(
              controller.text.replaceAll(RegExp(r'[^0-9.]'), ''),
            );
            if (amt == null || amt <= 0) return;
            await ref.update({'status': 'countered', 'counterAmount': amt});
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Send'),
        ),
      ],
    ),
  );
  controller.dispose();
}

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Offers'),
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Received'), Tab(text: 'Sent')],
          ),
        ),
        body: const TabBarView(
          children: [_OffersList(asSeller: true), _OffersList(asSeller: false)],
        ),
      ),
    );
  }
}

class _OffersList extends StatelessWidget {
  final bool asSeller;
  const _OffersList({required this.asSeller});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const EmptyState(icon: Icons.local_offer, title: 'Please log in');
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('offers')
          .where(asSeller ? 'sellerId' : 'buyerId', isEqualTo: uid)
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
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.local_offer,
            title: 'No offers yet',
            subtitle: asSeller
                ? 'Offers buyers make on your ads appear here.'
                : 'Offers you make will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final ref = docs[i].reference;
            final d = docs[i].data() as Map<String, dynamic>;
            final status = d['status']?.toString() ?? 'pending';
            final asking = (d['askingPrice'] as num?)?.toDouble() ?? 0;
            final offer = (d['offerAmount'] as num?)?.toDouble() ?? 0;
            final counter = (d['counterAmount'] as num?)?.toDouble();
            final (label, color) = switch (status) {
              'accepted' => ('Accepted', Colors.green),
              'ordered' => ('Deal agreed', Colors.green),
              'countered' => ('Countered', Colors.blue),
              'declined' => ('Declined', Colors.grey),
              'cancelled' => ('Cancelled', Colors.grey),
              _ => ('Pending', Colors.orange),
            };
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d['listingTitle']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Asking ${formatPrice(asking.toStringAsFixed(0))}  ·  '
                      'Offer ${formatPrice(offer.toStringAsFixed(0))}',
                    ),
                    if (counter != null)
                      Text(
                        'Counter: ${formatPrice(counter.toStringAsFixed(0))}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 8),
                    _actions(context, ref, d, status, offer, counter),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _actions(
    BuildContext context,
    DocumentReference ref,
    Map<String, dynamic> d,
    String status,
    double offer,
    double? counter,
  ) {
    final buttons = <Widget>[];
    if (asSeller && status == 'pending') {
      buttons.addAll([
        TextButton(
          onPressed: () => ref.update({'status': 'declined'}),
          child: const Text('Decline'),
        ),
        TextButton(
          onPressed: () => _counterDialog(context, ref),
          child: const Text('Counter'),
        ),
        ElevatedButton(
          onPressed: () =>
              ref.update({'status': 'accepted', 'agreedAmount': offer}),
          child: const Text('Accept'),
        ),
      ]);
    } else if (!asSeller && status == 'pending') {
      buttons.add(
        TextButton(
          onPressed: () => ref.update({'status': 'cancelled'}),
          child: const Text('Cancel'),
        ),
      );
    } else if (!asSeller && status == 'accepted') {
      buttons.add(
        ElevatedButton(
          onPressed: () => _orderFromOffer(ref, d, offer),
          child: Text('Buy at ${formatPrice(offer.toStringAsFixed(0))}'),
        ),
      );
    } else if (!asSeller && status == 'countered' && counter != null) {
      buttons.addAll([
        TextButton(
          onPressed: () => ref.update({'status': 'declined'}),
          child: const Text('Decline'),
        ),
        ElevatedButton(
          onPressed: () => _orderFromOffer(ref, d, counter),
          child: Text('Accept ${formatPrice(counter.toStringAsFixed(0))}'),
        ),
      ]);
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons);
  }
}

// ---------------------------------------------------------------------------
// Admin panel
// ---------------------------------------------------------------------------
