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
    default:
      return Icons.notifications;
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
                final unread = await col
                    .where('read', isEqualTo: false)
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (final d in unread.docs) {
                  batch.update(d.reference, {'read': true});
                }
                await batch.commit();
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
                    return ListTile(
                      tileColor: read ? null : kPakGreen.withValues(alpha: 0.06),
                      leading: CircleAvatar(
                        backgroundColor: kPakGreen.withValues(alpha: 0.12),
                        child: Icon(_notificationIcon(type), color: kPakGreen),
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
