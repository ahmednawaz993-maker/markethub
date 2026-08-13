part of '../main.dart';

// Notifications.

IconData _notificationIcon(String type) {
  switch (type) {
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'order':
      return Icons.receipt_long;
    case 'offer':
      return Icons.local_offer;
    case 'savedSearch':
      return Icons.search;
    case 'follow':
      return Icons.person_add_alt;
    case 'priceDrop':
      return Icons.local_fire_department;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'admin':
      return Icons.campaign_outlined;
    case 'support':
      return Icons.support_agent;
    case 'payoutAccount':
      return Icons.account_balance_wallet;
    default:
      return Icons.notifications;
  }
}

/// Accent colour for a notification by type — warnings stand out in red, admin
/// notices in gold, everything else in the brand navy.
Color _notificationColor(String type) {
  switch (type) {
    case 'warning':
      return Colors.red.shade700;
    case 'admin':
      return kGold;
    default:
      return kPakGreen;
  }
}

/// Deep-links a tapped notification to the exact thing it is about.
///
/// Every notification carries a [type] and a [refId] (the id of the order/
/// offer/chat/listing/ticket it concerns — see `recordNotification` in the
/// Cloud Functions). This resolves that pair to the right screen. Anything we
/// can't route (admin broadcasts, warnings, or a target that has since been
/// deleted) falls back to showing the full message in a dialog, so a tap is
/// never a dead end.
Future<void> openNotificationTarget(
  BuildContext context,
  Map<String, dynamic> notif,
) async {
  final type = notif['type']?.toString() ?? '';
  final refId = notif['refId']?.toString() ?? '';
  final db = FirebaseFirestore.instance;

  Future<void> push(Widget screen) async {
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // Shows the notification body when there's nowhere specific to go, or when
  // the referenced item no longer exists.
  void showDetail([String? note]) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(notif['title']?.toString() ?? 'Notification'),
        content: Text(
          [
            notif['body']?.toString() ?? '',
            note ?? '',
          ].where((s) => s.isNotEmpty).join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  try {
    switch (type) {
      // A specific listing/ad.
      case 'savedSearch':
      case 'newListing':
      case 'follow':
      case 'priceDrop':
        if (refId.isEmpty) return showDetail();
        final doc = await db.collection('listings').doc(refId).get();
        if (!doc.exists) {
          return showDetail('This ad is no longer available.');
        }
        return push(AdDetailsScreen(listing: Listing.fromDoc(doc)));

      // A chat thread — rebuild the ChatScreen from the chat doc.
      case 'chat':
        if (refId.isEmpty) return showDetail();
        final doc = await db.collection('chats').doc(refId).get();
        final chat = doc.data();
        if (chat == null) {
          return showDetail('This conversation is no longer available.');
        }
        return push(
          ChatScreen(
            chatId: refId,
            listingId: chat['listingId']?.toString() ?? '',
            listingTitle: chat['listingTitle']?.toString() ?? '',
            listingImage: chat['listingImage']?.toString() ?? '',
            buyerId: chat['buyerId']?.toString() ?? '',
            sellerId: chat['sellerId']?.toString() ?? '',
            buyerName: chat['buyerName']?.toString() ?? '',
            sellerName: chat['sellerName']?.toString() ?? '',
          ),
        );

      // Offers on the user's listings / their own offers.
      case 'offer':
        return push(const OffersScreen());

      // Order lifecycle: new order, fulfillment steps, disputes, refunds.
      case 'order':
      case 'escrow_hold':
      case 'escrow_release':
      case 'refund':
      case 'dispute':
        return push(const OrdersScreen());

      // Payout-account verification decision → the seller's payout accounts.
      case 'payoutAccount':
        return push(const PayoutAccountsScreen());

      // Money movements land in the wallet.
      case 'payout':
      case 'credit':
      case 'debit':
      case 'withdrawal_paid':
      case 'withdrawal_reserve':
      case 'withdrawal_refund':
        return push(const WalletScreen());

      // A support ticket the user owns.
      case 'support':
        if (refId.isEmpty) return showDetail();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return showDetail();
        return push(
          SupportThreadScreen(ticketId: refId, ownerId: uid, adminView: false),
        );

      // Admin broadcasts, warnings, and anything unrecognised: no target.
      default:
        return showDetail();
    }
  } catch (_) {
    // Any lookup/navigation failure just falls back to the message text.
    showDetail();
  }
}

/// Bell with an unread badge for the home app bar.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final open = IconButton(
      icon: const Icon(Icons.notifications_none),
      tooltip: 'Notifications',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
    );
    if (uid == null) return open;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          offset: const Offset(-4, 4),
          child: open,
        );
      },
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final col = uid == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('notifications');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesScreen(),
              ),
            ),
          ),
          if (col != null)
            TextButton(
              onPressed: () async {
                try {
                  final unread = await col
                      .where('read', isEqualTo: false)
                      .get();
                  // Firestore caps a WriteBatch at 500 writes, so commit the
                  // updates in chunks of at most 500.
                  final docs = unread.docs;
                  for (var i = 0; i < docs.length; i += 500) {
                    final batch = FirebaseFirestore.instance.batch();
                    final end = (i + 500 < docs.length) ? i + 500 : docs.length;
                    for (final d in docs.sublist(i, end)) {
                      batch.update(d.reference, {'read': true});
                    }
                    await batch.commit();
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not mark all read. Please try again.',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: col == null
          ? const EmptyState(icon: Icons.notifications, title: 'Please log in')
          : StreamBuilder<QuerySnapshot>(
              stream: col
                  .orderBy('createdAt', descending: true)
                  .limit(50)
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
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications yet',
                    subtitle: 'Messages, offers and orders will show up here.',
                  );
                }
                // Grouped into one card so the list reads as a single block on
                // the page background.
                return SurfacePanel(
                  margin: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.lg,
                    AppSpacing.page,
                    AppSpacing.navClearance,
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.divider,
                    ),
                    itemBuilder: (context, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      final read = d['read'] == true;
                      final type = d['type']?.toString() ?? '';
                      final accent = _notificationColor(type);
                      final title = d['title']?.toString() ?? '';
                      return Semantics(
                        button: true,
                        label:
                            '${read ? '' : 'Unread. '}$title. ${d['body']?.toString() ?? ''}',
                        child: InkWell(
                          onTap: () {
                            // Mark read on tap (unread rows only) and jump to
                            // whatever this notification is about.
                            if (!read) {
                              docs[i].reference.update({'read': true});
                            }
                            openNotificationTarget(context, d);
                          },
                          child: Container(
                            // Unread rows get a subtle tint AND (below) a dot +
                            // bold title — never colour alone.
                            color: read
                                ? Colors.transparent
                                : accent.withValues(alpha: 0.06),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: accent.withValues(
                                    alpha: 0.14,
                                  ),
                                  child: Icon(
                                    _notificationIcon(type),
                                    color: accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          // Non-colour unread indicator: a dot.
                                          if (!read) ...[
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsetsDirectional.only(
                                                end: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                color: AppColors.textPrimary,
                                                fontWeight: read
                                                    ? FontWeight.w500
                                                    : FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        d['body']?.toString() ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.3,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.schedule,
                                            size: 12,
                                            color: AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            timeAgo(
                                              d['createdAt'] as Timestamp?,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          if (!read) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: accent.withValues(
                                                  alpha: 0.14,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'New',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: accent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------
