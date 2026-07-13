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

/// Admin-managed customer-care helpline numbers (config/customerCare). Shown to
/// users on the Customer Care screen; staff with 'support' edit them.
DocumentReference<Map<String, dynamic>> get _careConfigDoc =>
    FirebaseFirestore.instance.collection('config').doc('customerCare');

List<Map<String, dynamic>> _parseCareNumbers(Map<String, dynamic>? data) {
  final raw = data?['numbers'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((m) => (m['number']?.toString() ?? '').isNotEmpty)
      .toList();
}

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

/// Policy guidance shown when a user picks certain categories. Order problems
/// are between buyer and seller; refunds are only handled by support when the
/// buyer paid through PakBazar's on-platform options (escrow).
String? _categoryNote(String category) {
  switch (category) {
    case 'Order / Delivery':
      return 'For order or delivery problems, please contact the seller '
          'directly through chat or their listed phone number. PakBazar can '
          'only step in for payments made through the platform.';
    case 'Payment / Refund':
      return 'Refunds can only be handled by us if you paid through PakBazar\'s '
          'on-platform payment options (escrow). If you paid the seller '
          'directly — cash on delivery, bank transfer, etc. — please settle it '
          'with the seller.';
    default:
      return null;
  }
}

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
  if (now.isAfter(due)) {
    return ('Overdue by ${_fmtDur(now.difference(due))}', Colors.red);
  }
  final left = due.difference(now);
  return (
    'Due in ${_fmtDur(left)}',
    left.inHours < 6 ? Colors.orange : kPakGreen,
  );
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
              gradient: const LinearGradient(
                colors: [kPakGreen, kPakGreenLight],
              ),
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
          const _CareNumbersBar(),
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
                      // Newest first, sorted client-side to avoid a composite
                      // index on (userId, updatedAt).
                      final docs = snapshot.data!.docs.toList()
                        ..sort((a, b) {
                          final at =
                              ((a.data() as Map)['updatedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0;
                          final bt =
                              ((b.data() as Map)['updatedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0;
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
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
              if (_categoryNote(category) != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kGold.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: kGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _categoryNote(category)!,
                          style: const TextStyle(fontSize: 12.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  final subject = subjectCtrl.text.trim();
  final message = messageCtrl.text.trim();
  subjectCtrl.dispose();
  messageCtrl.dispose();

  if (result != true) return;
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

  /// My role in this ticket and the counterpart whose read-marker drives my
  /// ticks.
  String get _myRole => widget.adminView ? 'support' : 'user';
  String get _otherRole => widget.adminView ? 'user' : 'support';

  /// Live ticket-doc metadata (read/delivered markers) for rendering ticks.
  Map<String, dynamic>? _meta;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _metaSub;

  // Voice recording state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _uploadingVoice = false;
  Timer? _recTimer;
  int _recSeconds = 0;

  DocumentReference<Map<String, dynamic>> get _ticketRef =>
      _supportTicketsCol.doc(widget.ticketId);

  @override
  void initState() {
    super.initState();
    _metaSub = _ticketRef.snapshots().listen((snap) {
      if (mounted) setState(() => _meta = snap.data());
    });
  }

  @override
  void dispose() {
    _metaSub?.cancel();
    _controller.dispose();
    _recTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  /// Marks the newest counterpart message read for my role, guarded to avoid
  /// write loops.
  void _maybeMarkRead(Timestamp? latestIncoming) {
    if (latestIncoming == null) return;
    final myRead = readMarker(_meta?['readAt'], _myRole);
    if (myRead != null &&
        myRead.millisecondsSinceEpoch >=
            latestIncoming.millisecondsSinceEpoch) {
      return;
    }
    markTicketRead(widget.ticketId, _myRole);
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Shared writer for text and voice messages: appends the message, advances
  /// the ticket status the same way, and notifies the owner on a support reply.
  Future<void> _postMessage(
    Map<String, dynamic> messageFields,
    String lastLabel,
  ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final role = widget.adminView ? 'support' : 'user';
    final snap = await _ticketRef.get();
    final status = snap.data()?['status']?.toString() ?? 'open';
    await _ticketRef.collection('messages').add({
      'senderId': me.uid,
      'senderRole': role,
      'senderName': widget.adminView
          ? 'PakBazar Support'
          : (me.email?.split('@').first ?? 'You'),
      'createdAt': Timestamp.now(),
      ...messageFields,
    });
    final update = <String, dynamic>{
      'lastMessage': lastLabel,
      'lastSenderRole': role,
      'updatedAt': Timestamp.now(),
    };
    if (widget.adminView) {
      if (status != 'resolved') update['status'] = 'in_progress';
    } else if (status == 'resolved') {
      update['status'] = 'open';
    }
    await _ticketRef.update(update);
    if (widget.adminView && widget.ownerId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.ownerId)
          .collection('notifications')
          .add({
            'title': 'Customer Care replied',
            'body': lastLabel.length > 120
                ? '${lastLabel.substring(0, 120)}…'
                : lastLabel,
            'type': 'support',
            'read': false,
            'createdAt': Timestamp.now(),
          });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await _postMessage({'text': text}, text);
    } catch (e) {
      // Restore the typed text so it isn't lost on a failed send.
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _snack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (FirebaseAuth.instance.currentUser == null ||
        _recording ||
        _uploadingVoice) {
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _snack('Microphone permission is needed for voice messages.');
        return;
      }
      // On web the path is ignored (records to a blob); on mobile we need a
      // real temp file path.
      String path = 'voice.webm';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(const RecordConfig(), path: path);
      setState(() {
        _recording = true;
        _recSeconds = 0;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSeconds++);
        if (_recSeconds >= 120) _stopAndSendVoice(); // cap at 2 minutes
      });
    } catch (e) {
      _snack('Could not start recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording) return;
    _recTimer?.cancel();
    final secs = _recSeconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    if (secs < 1) {
      _snack('Voice message too short.');
      return;
    }
    if (!mounted) return;
    setState(() => _uploadingVoice = true);
    try {
      final bytes = await XFile(path).readAsBytes();
      final ext = kIsWeb ? 'webm' : 'm4a';
      final ctype = kIsWeb ? 'audio/webm' : 'audio/mp4';
      final ref = FirebaseStorage.instance
          .ref()
          .child('support_voice')
          .child(
            '${widget.ticketId}_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
      await ref.putData(bytes, SettableMetadata(contentType: ctype));
      final url = await ref.getDownloadURL();
      await _postMessage({
        'type': 'voice',
        'audioUrl': url,
        'durationSec': secs,
        'text': '',
      }, '🎤 Voice message');
    } catch (e) {
      _snack('Could not send voice: $e');
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.adminView ? 'Ticket' : 'Customer Care'),
            // User sees whether Care is live; the agent sees the ticket owner.
            if (widget.adminView)
              (widget.ownerId.isEmpty
                  ? const SizedBox.shrink()
                  : PresenceStatusLine(widget.ownerId))
            else
              const PresenceStatusLine(
                kSupportPresenceId,
                onlinePrefix: 'Support is',
              ),
          ],
        ),
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
                // Opaque light header so the subject/category read over navy.
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['subject']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d['category'] ?? ''}'
                      '${widget.adminView && (d['userEmail']?.toString().isNotEmpty ?? false) ? ' · ${d['userEmail']}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
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
                            _actionChip(
                              'Mark in progress',
                              Colors.blue,
                              () => _setStatus('in_progress'),
                            ),
                          if (status != 'resolved')
                            _actionChip(
                              'Mark resolved',
                              Colors.green,
                              () => _setStatus('resolved'),
                            ),
                          if (status == 'resolved')
                            _actionChip(
                              'Reopen',
                              Colors.orange,
                              () => _setStatus('open'),
                            ),
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

                // Mark the newest counterpart message read so their ticks turn
                // blue. Post-frame; guarded against write loops.
                Timestamp? latestIncoming;
                for (final d in docs) {
                  final m = d.data() as Map<String, dynamic>;
                  if ((m['senderRole']?.toString() ?? '') == mineRole) continue;
                  final ts = m['createdAt'] as Timestamp?;
                  if (ts == null) continue;
                  if (latestIncoming == null ||
                      ts.millisecondsSinceEpoch >
                          latestIncoming.millisecondsSinceEpoch) {
                    latestIncoming = ts;
                  }
                }
                final pending = latestIncoming;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _maybeMarkRead(pending),
                );

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data() as Map<String, dynamic>;
                    final mine =
                        (m['senderRole']?.toString() ?? '') == mineRole;
                    final isSupport =
                        (m['senderRole']?.toString() ?? '') == 'support';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        // Opaque bubbles so the text is readable over navy.
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFFDCE6F5) // light navy tint
                              : (isSupport
                                    ? const Color(0xFFFBF3D5) // light gold tint
                                    : AppColors.surface),
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
                                color: isSupport
                                    ? AppColors.warning
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if ((m['type']?.toString() ?? '') == 'voice')
                              _VoiceBubble(
                                url: m['audioUrl']?.toString() ?? '',
                                durationSec:
                                    (m['durationSec'] as num?)?.toInt() ?? 0,
                                mine: mine,
                              )
                            else
                              Text(
                                m['text']?.toString() ?? '',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeAgo(m['createdAt'] as Timestamp?),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                if (mine) ...[
                                  const SizedBox(width: 4),
                                  MessageStatusTick(
                                    sentAt: m['createdAt'] as Timestamp?,
                                    deliveredAt: readMarker(
                                      _meta?['deliveredAt'],
                                      _otherRole,
                                    ),
                                    seenAt: readMarker(
                                      _meta?['readAt'],
                                      _otherRole,
                                    ),
                                    baseColor: Colors.black38,
                                  ),
                                ],
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
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: _recording
                  ? Row(
                      children: [
                        IconButton(
                          tooltip: 'Cancel',
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: _cancelRecording,
                        ),
                        const _RecordingDot(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recording…  ${_fmtClock(_recSeconds)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Send voice',
                          onPressed: _stopAndSendVoice,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    )
                  : Row(
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
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _uploadingVoice
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Record voice message',
                                icon: const Icon(Icons.mic, color: kPakGreen),
                                onPressed: _startRecording,
                              ),
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

/// User-facing list of helpline numbers (tap to call). Hidden when none set.
class _CareNumbersBar extends StatelessWidget {
  const _CareNumbersBar();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _careConfigDoc.snapshots(),
      builder: (context, snap) {
        final numbers = _parseCareNumbers(
          snap.data?.data() as Map<String, dynamic>?,
        );
        if (numbers.isEmpty) return const SizedBox.shrink();
        return SurfacePanel(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Contact our helpline',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              for (final n in numbers) _careNumberRow(n),
            ],
          ),
        );
      },
    );
  }

  Widget _careNumberRow(Map<String, dynamic> n) {
    final number = n['number']?.toString() ?? '';
    final label = n['label']?.toString() ?? '';
    final hasWhatsApp = n['whatsapp'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isNotEmpty ? '$label · $number' : number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Call',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.call, color: kPakGreen),
            onPressed: number.isEmpty
                ? null
                : () => launchUrl(
                    Uri.parse('tel:$number'),
                    mode: LaunchMode.externalApplication,
                  ),
          ),
          if (hasWhatsApp)
            IconButton(
              tooltip: 'WhatsApp',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
              onPressed: number.isEmpty ? null : () => _openWhatsApp(number),
            ),
        ],
      ),
    );
  }

  void _openWhatsApp(String number) {
    final cleaned = normalizePhoneForWhatsApp(number);
    if (cleaned.isEmpty) return;
    launchUrl(
      Uri.parse('https://wa.me/$cleaned'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// Admin/support screen to add, edit and delete the helpline numbers shown to
/// users on the Customer Care screen.
class CareNumbersAdminScreen extends StatelessWidget {
  const CareNumbersAdminScreen({super.key});

  Future<void> _save(List<Map<String, dynamic>> numbers) => _careConfigDoc.set({
    'numbers': numbers,
    'updatedAt': Timestamp.now(),
  }, SetOptions(merge: true));

  /// Opens the add/edit dialog; [existing]/[index] are null when adding.
  Future<void> _edit(
    BuildContext context,
    List<Map<String, dynamic>> numbers,
    int? index,
  ) async {
    final entry = index != null ? numbers[index] : null;
    final labelCtrl = TextEditingController(
      text: entry?['label']?.toString() ?? '',
    );
    final numberCtrl = TextEditingController(
      text: entry?['number']?.toString() ?? '',
    );
    bool whatsapp = entry?['whatsapp'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add number' : 'Edit number'),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (e.g. Helpline, Orders)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: numberCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Number',
                  hintText: '+92 3xx xxxxxxx',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Available on WhatsApp'),
                subtitle: const Text('Shows a WhatsApp chat button to users'),
                value: whatsapp,
                onChanged: (v) => setS(() => whatsapp = v ?? false),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final label = labelCtrl.text.trim();
    final number = numberCtrl.text.trim();
    labelCtrl.dispose();
    numberCtrl.dispose();
    if (ok != true) return;
    if (number.isEmpty) return;
    final updated = [...numbers];
    final newEntry = {'label': label, 'number': number, 'whatsapp': whatsapp};
    if (index != null) {
      updated[index] = newEntry;
    } else {
      updated.add(newEntry);
    }
    await _save(updated);
  }

  Future<void> _delete(
    BuildContext context,
    List<Map<String, dynamic>> numbers,
    int index,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete number?'),
        content: Text('Remove ${numbers[index]['number']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final updated = [...numbers]..removeAt(index);
    await _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Helpline numbers')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _careConfigDoc.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final numbers = _parseCareNumbers(
            snap.data!.data() as Map<String, dynamic>?,
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => _edit(context, numbers, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add number'),
                  ),
                ),
              ),
              Expanded(
                child: numbers.isEmpty
                    ? const EmptyState(
                        icon: Icons.phone_disabled,
                        title: 'No helpline numbers',
                        subtitle: 'Add a number for users to call.',
                      )
                    : SurfacePanel(
                        margin: const EdgeInsets.all(12),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: numbers.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (context, i) {
                            final n = numbers[i];
                            final label = n['label']?.toString() ?? '';
                            final sub = [
                              if (label.isNotEmpty) label,
                              if (n['whatsapp'] == true) 'WhatsApp enabled',
                            ].join(' · ');
                            return ListTile(
                              leading: const Icon(Icons.call, color: kPakGreen),
                              title: Text(n['number']?.toString() ?? ''),
                              subtitle: sub.isNotEmpty ? Text(sub) : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _edit(context, numbers, i),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _delete(context, numbers, i),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The Admin Panel tab label for Customer Care, with a badge counting tickets
/// that need a staff reply (not resolved and the last message was the
/// customer's). Returns a [Tab] so it slots straight into the TabBar.
class _SupportTabLabel extends StatelessWidget {
  final String title;
  const _SupportTabLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Single-field filter (no composite index); status filtered client-side.
      stream: _supportTicketsCol
          .where('lastSenderRole', isEqualTo: 'user')
          .snapshots(),
      builder: (context, snap) {
        final count = (snap.data?.docs ?? []).where((d) {
          final s = (d.data() as Map)['status']?.toString() ?? 'open';
          return s != 'resolved';
        }).length;
        return Tab(
          child: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            offset: const Offset(6, -4),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(title),
            ),
          ),
        );
      },
    );
  }
}

/// Invisible watcher mounted in the admin panel: while a support agent has the
/// app open, it pops a snackbar the moment a user posts a new support message,
/// so incoming messages are noticed immediately across any tab. No-op for
/// non-support users. Push notifications (Cloud Function) cover the offline case.
class SupportAlertWatcher extends StatefulWidget {
  const SupportAlertWatcher({super.key});

  @override
  State<SupportAlertWatcher> createState() => _SupportAlertWatcherState();
}

class _SupportAlertWatcherState extends State<SupportAlertWatcher> {
  int?
  _lastMax; // newest user-message updatedAt seen (ms); null until baseline.

  @override
  Widget build(BuildContext context) {
    if (!(isSuperAdmin() || hasAdminPerm('support'))) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _supportTicketsCol
          .where('lastSenderRole', isEqualTo: 'user')
          .snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? []).where((d) {
          final s = (d.data() as Map)['status']?.toString() ?? 'open';
          return s != 'resolved';
        }).toList();

        QueryDocumentSnapshot? newest;
        int maxTs = 0;
        for (final d in docs) {
          final ts =
              ((d.data() as Map)['updatedAt'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          if (ts > maxTs) {
            maxTs = ts;
            newest = d;
          }
        }

        // Baseline on the first snapshot (don't alert for the existing backlog).
        if (_lastMax == null) {
          _lastMax = maxTs;
        } else if (maxTs > _lastMax! && newest != null) {
          _lastMax = maxTs;
          final m = newest.data() as Map<String, dynamic>;
          final who = m['userName']?.toString().trim();
          final preview = m['lastMessage']?.toString() ?? '';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            rootMessengerKey.currentState
              ?..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  backgroundColor: kPakGreen,
                  duration: const Duration(seconds: 6),
                  content: Text(
                    '📩 New support message'
                    '${(who != null && who.isNotEmpty) ? ' from $who' : ''}'
                    '${preview.isEmpty ? '' : ': $preview'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  action: SnackBarAction(
                    label: 'OK',
                    textColor: Colors.white,
                    onPressed: () {},
                  ),
                ),
              );
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CareNumbersAdminScreen(),
                ),
              ),
              icon: const Icon(Icons.call),
              label: const Text('Manage helpline numbers'),
            ),
          ),
        ),
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
                final ad =
                    (am['slaDueAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                final bd =
                    (bm['slaDueAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
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

/// m:ss clock from a seconds count.
String _fmtClock(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Pulsing red dot shown while recording a voice message.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A voice message bubble: tap to play/pause the audio from its URL, with a
/// duration label. Used for both user and support voice messages.
class _VoiceBubble extends StatefulWidget {
  final String url;
  final int durationSec;
  final bool mine;
  const _VoiceBubble({
    required this.url,
    required this.durationSec,
    required this.mine,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.isEmpty) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        setState(() => _loading = true);
        await _player.play(UrlSource(widget.url));
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.mine ? kPakGreen : kGold;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _loading
            ? SizedBox(
                width: 34,
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
              )
            : InkWell(
                onTap: _toggle,
                child: Icon(
                  _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  size: 34,
                  color: color,
                ),
              ),
        const SizedBox(width: 8),
        Icon(Icons.graphic_eq, size: 20, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(
          widget.durationSec > 0 ? _fmtClock(widget.durationSec) : 'Voice',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
