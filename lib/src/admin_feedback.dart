part of '../main.dart';

// Admin side of the feedback system.
//
// Feedback used to be a wall of messages with an email address attached and a
// "Reply" button that opened the admin's mail client. Nothing was recorded, the
// user never saw a reply inside the app, and there was no way to tell who had
// written in — whether they were verified, suspended, a seller with fifty ads
// or someone who signed up an hour ago.
//
// Now each message carries the client behind it, and a reply is written back
// onto the feedback document and delivered to the user's notifications, so both
// sides can see that it was answered.

/// Status values a feedback item moves through. 'replied' sits between open and
/// resolved: answered, but not yet closed off by whoever owns the queue.
const List<String> kFeedbackStatuses = ['open', 'replied', 'resolved'];

/// Reads the author's email from either schema.
///
/// The Help & Feedback sheet writes `email`; the review-prompt path wrote
/// `userEmail`. Both are in the collection, so the admin panel has to accept
/// either or half the queue shows no address.
String feedbackEmailOf(Map<String, dynamic> d) {
  final a = d['email']?.toString() ?? '';
  if (a.isNotEmpty) return a;
  return d['userEmail']?.toString() ?? '';
}

String feedbackStatusOf(Map<String, dynamic> d) {
  final s = d['status']?.toString() ?? '';
  return kFeedbackStatuses.contains(s) ? s : 'open';
}

/// Records an admin's reply on the feedback document and delivers it to the
/// user's in-app notifications.
///
/// Two writes rather than one: the feedback doc is the durable record for the
/// back office, the notification is how the user actually finds out. The
/// notification is best-effort — a reply that is saved but not delivered is
/// recoverable, a lost reply is not.
Future<void> adminReplyToFeedback({
  required String feedbackId,
  required String userId,
  required String reply,
}) async {
  final text = reply.trim();
  if (text.isEmpty) return;
  await FirebaseFirestore.instance.collection('feedback').doc(feedbackId).set({
    'adminReply': text,
    'adminReplyBy': FirebaseAuth.instance.currentUser?.email ?? '',
    'adminReplyAt': Timestamp.now(),
    'status': 'replied',
  }, SetOptions(merge: true));

  if (userId.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add({
          'title': 'Reply from PakBazar support',
          'body': text,
          'type': 'feedback',
          'feedbackId': feedbackId,
          'read': false,
          'createdAt': Timestamp.now(),
        });
  } catch (_) {
    // The reply is saved either way; the admin can resend from the card.
  }
}

/// Support requests and suggestions sent from the Help & Feedback sheet.
class AdminFeedbackTab extends StatefulWidget {
  const AdminFeedbackTab({super.key});

  @override
  State<AdminFeedbackTab> createState() => _AdminFeedbackTabState();
}

class _AdminFeedbackTabState extends State<AdminFeedbackTab> {
  String _filter = 'open';

  bool _inFilter(Map<String, dynamic> d) =>
      _filter == 'all' || feedbackStatusOf(d) == _filter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load feedback: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!.docs;
        final docs = all
            .where((x) => _inFilter(x.data() as Map<String, dynamic>))
            .toList();
        return Column(
          children: [
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.page,
                  vertical: 4,
                ),
                children: [
                  for (final (code, label) in const [
                    ('open', 'Open'),
                    ('replied', 'Replied'),
                    ('resolved', 'Resolved'),
                    ('all', 'All'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: FilterChip(
                        selected: _filter == code,
                        label: Text(
                          '$label (${all.where((x) {
                            final m = x.data() as Map<String, dynamic>;
                            return code == 'all' ||
                                feedbackStatusOf(m) == code;
                          }).length})',
                        ),
                        onSelected: (_) => setState(() => _filter = code),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? EmptyState(
                      icon: Icons.feedback_outlined,
                      title: all.isEmpty ? 'No messages yet' : 'Nothing here',
                      subtitle: all.isEmpty
                          ? 'Help requests and suggestions appear here.'
                          : 'No feedback with this status.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.sm,
                        AppSpacing.page,
                        AppSpacing.navClearance,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => AdminFeedbackCard(
                        docId: docs[i].id,
                        data: docs[i].data() as Map<String, dynamic>,
                        onSetStatus: (s) =>
                            docs[i].reference.update({'status': s}),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// One feedback message and everything an admin can do with it.
///
/// Takes plain data plus a callback rather than a Firestore snapshot, so the
/// layout tests can pump it at real phone widths without a live backend. The
/// card is dense — a client panel of wrapped tags, a quoted reply block and a
/// button row — and this repo has already shipped one admin screen that
/// overflowed a 320px phone.
class AdminFeedbackCard extends StatelessWidget {
  const AdminFeedbackCard({
    super.key,
    required this.docId,
    required this.data,
    this.onSetStatus,
  });

  final String docId;
  final Map<String, dynamic> data;
  final Future<void> Function(String status)? onSetStatus;

  @override
  Widget build(BuildContext context) {
    final type = data['type']?.toString() ?? 'Help';
    final msg = data['message']?.toString() ?? '';
    final status = feedbackStatusOf(data);
    final isSuggestion = type == 'Suggestion';
    final reply = data['adminReply']?.toString() ?? '';
    final source = data['source']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuggestion ? Icons.lightbulb_outline : Icons.help_outline,
                  size: 18,
                  color: isSuggestion ? kGold : kPakGreen,
                ),
                const SizedBox(width: 6),
                // Flexible + ellipsis: at 1.3x text scale on a 320px phone the
                // type and source together pushed the status chip off the edge.
                Flexible(
                  child: Text(
                    source.isEmpty ? type : '$type · $source',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 2),
            Text(timeAgo(data['createdAt'] as Timestamp?), style: AppType.caption),

            // Who wrote in — the whole point of the rebuild.
            const SizedBox(height: 8),
            _FeedbackClientPanel(
              userId: data['userId']?.toString() ?? '',
              fallbackEmail: feedbackEmailOf(data),
            ),

            const Divider(height: 20),
            Text(msg),

            if (reply.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPakGreen.withValues(alpha: 0.08),
                  borderRadius: AppRadius.rMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.reply, size: 14, color: kPakGreen),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Replied by ${data['adminReplyBy'] ?? 'admin'} · '
                            '${timeAgo(data['adminReplyAt'] as Timestamp?)}',
                            style: AppType.caption,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(reply, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 4),
            // Wrap, not Row: "Reply again" plus "Mark resolved" overflowed a
            // 320px phone by up to 154px at large text.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  onPressed: () => _reply(context),
                  icon: const Icon(Icons.reply, size: 18),
                  label: Text(reply.isEmpty ? 'Reply' : 'Reply again'),
                ),
                if (status != 'resolved')
                  TextButton(
                    onPressed: onSetStatus == null
                        ? null
                        : () => onSetStatus!('resolved'),
                    child: const Text('Mark resolved'),
                  )
                else
                  TextButton(
                    onPressed:
                        onSetStatus == null ? null : () => onSetStatus!('open'),
                    child: const Text('Re-open'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'replied' => ('Replied', Colors.blue),
      'resolved' => ('Resolved', Colors.green),
      _ => ('Open', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.rMd,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _reply(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController(
      text: data['adminReply']?.toString() ?? '',
    );
    final uid = data['userId']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply to this message'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uid.isEmpty
                    ? 'This message has no account attached, so the reply is '
                          'recorded here but cannot be delivered in-app.'
                    : 'The reply is saved on this message and sent to the '
                          'user\'s notifications.',
                style: AppType.secondary,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Your reply',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send reply'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true || text.trim().isEmpty) return;
    try {
      await adminReplyToFeedback(
        feedbackId: docId,
        userId: uid,
        reply: text,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Reply sent.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not reply: $e')));
    }
  }
}

/// The account behind a feedback message: who they are, how to reach them, and
/// the standing that decides how seriously to take the complaint.
class _FeedbackClientPanel extends StatefulWidget {
  const _FeedbackClientPanel({
    required this.userId,
    required this.fallbackEmail,
  });

  final String userId;
  final String fallbackEmail;

  @override
  State<_FeedbackClientPanel> createState() => _FeedbackClientPanelState();
}

class _FeedbackClientPanelState extends State<_FeedbackClientPanel> {
  Map<String, dynamic>? _user;
  String _email = '';
  String _phone = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var email = widget.fallbackEmail;
    var phone = '';
    Map<String, dynamic>? user;
    if (widget.userId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();
        user = snap.data();
      } catch (_) {}
      try {
        // Phone/email live in the private subcollection, not the public user
        // doc. Requires can('feedback') on users/{uid}/private.
        final c = await loadPrivateContact(widget.userId);
        final p = c['phone']?.toString() ?? '';
        if (p.isNotEmpty) phone = p;
        final e = c['email']?.toString() ?? '';
        if (email.isEmpty && e.isNotEmpty) email = e;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _user = user;
      _email = email;
      _phone = phone;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Text('Loading sender…', style: AppType.caption);
    }
    if (widget.userId.isEmpty && _email.isEmpty) {
      return Text('No account attached to this message.', style: AppType.caption);
    }
    final u = _user ?? const <String, dynamic>{};
    final name = (u['name'] ?? u['displayName'] ?? '').toString();
    final verified = u['idVerified'] == true;
    final blocked = u['blocked'] == true;
    final business = u['isBusiness'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name.isEmpty ? '(no name on profile)' : name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _tag(
                verified ? 'ID verified' : 'Not verified',
                verified ? kPakGreen : Colors.orange,
              ),
              if (blocked) _tag('Suspended', Colors.red),
              if (business) _tag('Business', Colors.indigo),
              if (u['createdAt'] is Timestamp)
                _tag('Joined ${timeAgo(u['createdAt'] as Timestamp)}',
                    AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 6),
          if (_email.isNotEmpty)
            Text(_email, style: AppType.caption)
          else
            Text('No email on file', style: AppType.caption),
          Text(
            _phone.isEmpty ? 'No phone on file' : _phone,
            style: AppType.caption,
          ),
          // Wrapped and on their own line — three icon buttons beside the
          // number did not fit beside a long one at large text.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (_phone.isNotEmpty) ...[
                IconButton(
                  tooltip: 'WhatsApp',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chat, size: 18, color: Color(0xFF25D366)),
                  onPressed: () => _openWhatsAppNumber(_phone),
                ),
                IconButton(
                  tooltip: 'Call',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call, size: 18, color: kPakGreen),
                  onPressed: () => _dialNumber(_phone),
                ),
              ],
              if (_email.isNotEmpty)
                IconButton(
                  tooltip: 'Email',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  onPressed: () => launchUrl(
                    Uri.parse('mailto:$_email'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: AppRadius.rSm,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
