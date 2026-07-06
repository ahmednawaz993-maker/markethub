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
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not mark all read: $e')),
                    );
                  }
                }
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: col == null
          ? const EmptyState(
              icon: Icons.notifications,
              title: 'Please log in',
            )
          : StreamBuilder<QuerySnapshot>(
              stream: col
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
                    icon: Icons.notifications_none,
                    title: 'No notifications yet',
                    subtitle: 'Messages, offers and orders will show up here.',
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final read = d['read'] == true;
                    final type = d['type']?.toString() ?? '';
                    final accent = _notificationColor(type);
                    return ListTile(
                      tileColor: read ? null : accent.withValues(alpha: 0.06),
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.12),
                        child: Icon(_notificationIcon(type), color: accent),
                      ),
                      title: Text(
                        d['title']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: read
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(d['body']?.toString() ?? ''),
                      trailing: Text(
                        timeAgo(d['createdAt'] as Timestamp?),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      onTap: read
                          ? null
                          : () => docs[i].reference.update({'read': true}),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------
