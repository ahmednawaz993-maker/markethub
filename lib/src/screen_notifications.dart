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

/// Bell with an unread badge for the home app bar.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final open = IconButton(
      icon: const Icon(Icons.notifications_none, color: Colors.white),
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
                // The list sits on a white surface so the dark notification
                // text is high-contrast (it was previously rendered directly on
                // the navy gradient, making titles/bodies hard to read).
                return SurfacePanel(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                          onTap: read
                              ? null
                              : () => docs[i].reference.update({'read': true}),
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
                                              margin: const EdgeInsets.only(
                                                right: 6,
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
