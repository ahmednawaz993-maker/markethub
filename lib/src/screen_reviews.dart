part of '../main.dart';

// Seller reviews.

Future<void> showReviewDialog(BuildContext context, String sellerId) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null || me.uid == sellerId) return;

  int rating = 5;
  final textController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Rate this seller'),
        content: StatefulBuilder(
          builder: (context, setS) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          color: kGold,
                          size: 36,
                        ),
                        onPressed: () => setS(() => rating = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Your review (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      );
    },
  );

  if (submitted == true) {
    try {
      await submitSellerReview(
        sellerId: sellerId,
        rating: rating,
        text: textController.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your review!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not submit review: $e')));
      }
    }
  }

  textController.dispose();
}

class ReviewsScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;

  const ReviewsScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final canReview = me != null && me.uid != sellerId;

    return Scaffold(
      appBar: AppBar(title: Text('Reviews · $sellerName')),
      floatingActionButton: canReview
          ? FloatingActionButton.extended(
              onPressed: () => showReviewDialog(context, sellerId),
              icon: const Icon(Icons.rate_review),
              label: const Text('Write'),
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(sellerId)
            .collection('reviews')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reviews = snapshot.data!.docs.toList()
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

          if (reviews.isEmpty) {
            return const Center(
              child: Text(
                'No reviews yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final r = reviews[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r['reviewerName']?.toString() ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            timeAgo(r['createdAt'] as Timestamp?),
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      StarRating(
                        rating: (r['rating'] as num?)?.toDouble() ?? 0,
                        size: 16,
                      ),
                      if ((r['text']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(r['text'].toString()),
                      ],
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
