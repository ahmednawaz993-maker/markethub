part of '../main.dart';

// ---------------------------------------------------------------------------
// Customer Care — 24/7 support tickets.
//
// A user opens a ticket from the "Customer Care" button (home app bar +
// Profile) and chats with support in the ticket's `messages` subcollection.
// Each ticket carries a 24-hour resolution target (slaDueAt). Staff with the
// 'support' permission manage tickets from Admin Panel → Customer Care, where
// overdue tickets are flagged in red. When support replies, the ticket owner
// gets a notification.
// ---------------------------------------------------------------------------

CollectionReference<Map<String, dynamic>> get _supportTicketsCol =>
    FirebaseFirestore.instance.collection('supportTickets');

/// Resolution target for every ticket.
const Duration kSupportSla = Duration(hours: 24);

const List<String> kSupportCategories = [
  'Payment / Refund',
  'Order / Delivery',
  'Account / Login',
  'Report a scam',
  'Verification',
  'Technical issue',
  'Other',
];

/// Opens a new support ticket with its first message. Returns the ticket id.
Future<String?> createSupportTicket({
  required String category,
  required String subject,
  required String message,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return null;
  final now = Timestamp.now();
  final sla = Timestamp.fromDate(DateTime.now().add(kSupportSla));
  final name = me.email?.split('@').first ?? (me.phoneNumber ?? 'User');
  final ref = await _supportTicketsCol.add({
    'userId': me.uid,
    'userEmail': me.email ?? me.phoneNumber ?? '',
    'userName': name,
    'category': category,
    'subject': subject.trim(),
    'status': 'open',
    'createdAt': now,
    'updatedAt': now,
    'slaDueAt': sla,
    'lastMessage': message.trim(),
    'lastSenderRole': 'user',
  });
  await ref.collection('messages').add({
    'senderId': me.uid,
    'senderRole': 'user',
    'senderName': name,
    'text': message.trim(),
    'createdAt': now,
  });
  return ref.id;
}

/// (label, colour) for a ticket status.
(String, Color) _ticketStatusChip(String s) => switch (s) {
  'resolved' => ('Resolved', Colors.green),
  'in_progress' => ('In progress', Colors.blue),
  _ => ('Open', Colors.orange),
};

String _fmtDur(Duration d) {
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${d.inMinutes}m';
}

/// (label, colour) describing the 24h SLA state of a ticket.
(String, Color) _slaInfo(Map<String, dynamic> t) {
  final status = t['status']?.toString() ?? 'open';
  if (status == 'resolved') return ('Resolved', Colors.green);
  final due = (t['slaDueAt'] as Timestamp?)?.toDate();
  if (due == null) return ('Open', kPakGreen);
  final now = DateTime.now();
  if (now.isAfter(due)) return ('Overdue by ${_fmtDur(now.difference(due))}', Colors.red);
  final left = due.difference(now);
  return ('Due in ${_fmtDur(left)}', left.inHours < 6 ? Colors.orange : kPakGreen);
}

// ---------------------------------------------------------------------------
// User-facing: Customer Care hub
// ---------------------------------------------------------------------------

class CustomerCareScreen extends StatelessWidget {
  const CustomerCareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Care')),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showNewTicketSheet(context),
              icon: const Icon(Icons.add_comment),
              label: const Text('New request'),
            ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPakGreen, kPakGreenLight]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.support_agent, color: Colors.white, size: 26),
                    SizedBox(width: 8),
                    Text(
                      '24/7 Customer Care',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Facing a problem? Open a request any time and our team aims '
                  'to resolve it within 24 hours.',
                  style: TextStyle(color: Colors.white, height: 1.3),
                ),
              ],
            ),
          ),
          Expanded(
            child: uid == null
                ? const EmptyState(
                    icon: Icons.support_agent,
                    title: 'Please log in',
                    subtitle: 'Log in to contact Customer Care.',
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _supportTicketsCol
                        .where('userId', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      // Newest first, sorted client-side to avoid a composite
                      // index on (userId, updatedAt).
                      final docs = snapshot.data!.docs.toList()
                        ..sort((a, b) {
                          final at = ((a.data() as Map)['updatedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ?? 0;
                          final bt = ((b.data() as Map)['updatedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ?? 0;
                          return bt.compareTo(at);
                        });
                      if (docs.isEmpty) {
                        return const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'No requests yet',
                          subtitle: 'Tap "New request" to contact us.',
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          return _TicketCard(
                            data: d,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SupportThreadScreen(
                                  ticketId: docs[i].id,
                                  ownerId: d['userId']?.toString() ?? uid,
                                  adminView: false,
                                ),
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

/// A ticket row shown in the user's list and (with [showUser]) the admin tab.
class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final bool showUser;
  const _TicketCard({
    required this.data,
    required this.onTap,
    this.showUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status']?.toString() ?? 'open';
    final (sLabel, sColor) = _ticketStatusChip(status);
    final (slaLabel, slaColor) = _slaInfo(data);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text(
          data['subject']?.toString() ?? '(no subject)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${data['category'] ?? ''}'
              '${showUser && (data['userEmail']?.toString().isNotEmpty ?? false) ? ' · ${data['userEmail']}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              data['lastMessage']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _pill(sLabel, sColor),
                const SizedBox(width: 6),
                _pill(slaLabel, slaColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

Future<void> _showNewTicketSheet(BuildContext context) async {
  String category = kSupportCategories.first;
  final subjectCtrl = TextEditingController();
  final messageCtrl = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New support request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in kSupportCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setS(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Briefly, what is the issue?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageCtrl,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Describe the problem',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send),
                label: const Text('Submit request'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (result != true) return;
  final subject = subjectCtrl.text.trim();
  final message = messageCtrl.text.trim();
  if (subject.isEmpty || message.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Please add a subject and a description.')),
    );
    return;
  }
  final id = await createSupportTicket(
    category: category,
    subject: subject,
    message: message,
  );
  if (id == null || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SupportThreadScreen(
        ticketId: id,
        ownerId: FirebaseAuth.instance.currentUser!.uid,
        adminView: false,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared ticket thread (used by the user and by support staff)
// ---------------------------------------------------------------------------

class SupportThreadScreen extends StatefulWidget {
  final String ticketId;
  final String ownerId;
  final bool adminView;
  const SupportThreadScreen({
    super.key,
    required this.ticketId,
    required this.ownerId,
    required this.adminView,
  });

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _ticketRef =>
      _supportTicketsCol.doc(widget.ticketId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final me = FirebaseAuth.instance.currentUser;
    if (text.isEmpty || me == null || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    final role = widget.adminView ? 'support' : 'user';
    try {
      // Read the current status to decide the resulting status transition.
      final snap = await _ticketRef.get();
      final status = snap.data()?['status']?.toString() ?? 'open';

      await _ticketRef.collection('messages').add({
        'senderId': me.uid,
        'senderRole': role,
        'senderName': widget.adminView
            ? 'PakBazar Support'
            : (me.email?.split('@').first ?? 'You'),
        'text': text,
        'createdAt': Timestamp.now(),
      });

      final update = <String, dynamic>{
        'lastMessage': text,
        'lastSenderRole': role,
        'updatedAt': Timestamp.now(),
      };
      if (widget.adminView) {
        // A support reply means the ticket is being handled.
        if (status != 'resolved') update['status'] = 'in_progress';
      } else if (status == 'resolved') {
        // A user follow-up reopens a resolved ticket.
        update['status'] = 'open';
      }
      await _ticketRef.update(update);

      // Tell the ticket owner support has replied (staff are back-office, so
      // the notifications rule permits writing to the owner's inbox).
      if (widget.adminView && widget.ownerId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.ownerId)
            .collection('notifications')
            .add({
              'title': 'Customer Care replied',
              'body': text.length > 120 ? '${text.substring(0, 120)}…' : text,
              'type': 'support',
              'read': false,
              'createdAt': Timestamp.now(),
            });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    final update = <String, dynamic>{
      'status': status,
      'updatedAt': Timestamp.now(),
    };
    if (status == 'resolved') update['resolvedAt'] = Timestamp.now();
    await _ticketRef.update(update);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.adminView ? 'Ticket' : 'Customer Care'),
      ),
      body: Column(
        children: [
          // Header: status + SLA + (admin) actions.
          StreamBuilder<DocumentSnapshot>(
            stream: _ticketRef.snapshots(),
            builder: (context, snap) {
              final d = snap.data?.data() as Map<String, dynamic>?;
              if (d == null) return const SizedBox.shrink();
              final status = d['status']?.toString() ?? 'open';
              final (sLabel, sColor) = _ticketStatusChip(status);
              final (slaLabel, slaColor) = _slaInfo(d);
              return Container(
                width: double.infinity,
                color: sColor.withValues(alpha: 0.07),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['subject']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d['category'] ?? ''}'
                      '${widget.adminView && (d['userEmail']?.toString().isNotEmpty ?? false) ? ' · ${d['userEmail']}' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _statusPill(sLabel, sColor),
                        _statusPill(slaLabel, slaColor),
                        if (widget.adminView) ...[
                          if (status != 'in_progress' && status != 'resolved')
                            _actionChip('Mark in progress', Colors.blue,
                                () => _setStatus('in_progress')),
                          if (status != 'resolved')
                            _actionChip('Mark resolved', Colors.green,
                                () => _setStatus('resolved')),
                          if (status == 'resolved')
                            _actionChip('Reopen', Colors.orange,
                                () => _setStatus('open')),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _ticketRef
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                final mineRole = widget.adminView ? 'support' : 'user';
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data() as Map<String, dynamic>;
                    final mine = (m['senderRole']?.toString() ?? '') == mineRole;
                    final isSupport =
                        (m['senderRole']?.toString() ?? '') == 'support';
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? kPakGreen.withValues(alpha: 0.12)
                              : (isSupport
                                  ? kGold.withValues(alpha: 0.14)
                                  : Colors.grey.withValues(alpha: 0.12)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSupport
                                  ? 'PakBazar Support'
                                  : (m['senderName']?.toString() ?? 'User'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isSupport ? kGold : Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(m['text']?.toString() ?? ''),
                            const SizedBox(height: 2),
                            Text(
                              timeAgo(m['createdAt'] as Timestamp?),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: widget.adminView
                            ? 'Reply to the customer…'
                            : 'Type your message…',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
    ),
  );

  Widget _actionChip(String text, Color color, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}

// ---------------------------------------------------------------------------
// Admin Panel → Customer Care tab
// ---------------------------------------------------------------------------

class _AdminSupportTab extends StatefulWidget {
  const _AdminSupportTab();

  @override
  State<_AdminSupportTab> createState() => _AdminSupportTabState();
}

class _AdminSupportTabState extends State<_AdminSupportTab> {
  // 'active' = open + in_progress; or a specific status.
  String _filter = 'active';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final (value, label) in const [
                ('active', 'Active'),
                ('open', 'Open'),
                ('in_progress', 'In progress'),
                ('resolved', 'Resolved'),
                ('all', 'All'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _supportTicketsCol.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snapshot.data!.docs.where((doc) {
                final s = (doc.data() as Map)['status']?.toString() ?? 'open';
                return switch (_filter) {
                  'active' => s == 'open' || s == 'in_progress',
                  'all' => true,
                  _ => s == _filter,
                };
              }).toList();
              // Unresolved first; within that, soonest/most-overdue SLA first.
              docs.sort((a, b) {
                final am = a.data() as Map<String, dynamic>;
                final bm = b.data() as Map<String, dynamic>;
                final ar = (am['status'] == 'resolved') ? 1 : 0;
                final br = (bm['status'] == 'resolved') ? 1 : 0;
                if (ar != br) return ar - br;
                final ad = (am['slaDueAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ?? 0;
                final bd = (bm['slaDueAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ?? 0;
                return ad.compareTo(bd);
              });
              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.support_agent,
                  title: 'No tickets',
                  subtitle: 'Customer Care requests appear here.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  return _TicketCard(
                    data: d,
                    showUser: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SupportThreadScreen(
                          ticketId: docs[i].id,
                          ownerId: d['userId']?.toString() ?? '',
                          adminView: true,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
