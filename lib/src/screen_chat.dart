part of '../main.dart';

// Chats and conversation screen.

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: const EmptyStateWidget(
          icon: Icons.chat_bubble_outline,
          title: 'Log in to see your chats',
          subtitle: 'Message sellers and keep every conversation in one place.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorStateWidget(
              message: 'We couldn’t load your chats. Please try again.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final at =
                  ((a.data() as Map<String, dynamic>)['lastTime'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              final bt =
                  ((b.data() as Map<String, dynamic>)['lastTime'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              return bt.compareTo(at);
            });

          if (chats.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              subtitle: 'Message a seller from any ad to start a conversation.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.navClearance,
            ),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final data = chats[index].data() as Map<String, dynamic>;
              final isBuyer = data['buyerId'] == uid;
              final otherName = isBuyer
                  ? (data['sellerName']?.toString() ?? 'Seller')
                  : (data['buyerName']?.toString() ?? 'Buyer');
              final otherUid =
                  (isBuyer
                      ? data['sellerId']?.toString()
                      : data['buyerId']?.toString()) ??
                  '';
              final listingImage = data['listingImage']?.toString() ?? '';

              // Acknowledge delivery for anything newer than my last-delivered
              // marker, so the sender's ticks go double-grey once I have the
              // thread listed. Guarded to avoid a write loop.
              final lastTime = data['lastTime'] as Timestamp?;
              final myDelivered = readMarker(data['deliveredAt'], uid);
              if (lastTime != null &&
                  (myDelivered == null ||
                      lastTime.millisecondsSinceEpoch >
                          myDelivered.millisecondsSinceEpoch)) {
                final chatDocId = data['chatId']?.toString() ?? chats[index].id;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => markChatDelivered(chatDocId, uid),
                );
              }

              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      listingImage.isEmpty
                          ? const CircleAvatar(child: Icon(Icons.image))
                          : CircleAvatar(
                              backgroundImage: NetworkImage(listingImage),
                            ),
                      if (otherUid.isNotEmpty)
                        PositionedDirectional(
                          end: -1,
                          bottom: -1,
                          child: PresenceDot(otherUid),
                        ),
                    ],
                  ),
                  title: Text(
                    otherName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data['listingTitle']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption,
                      ),
                      Text(
                        data['lastMessage']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.secondary,
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: data['chatId']?.toString() ?? chats[index].id,
                          listingId: data['listingId']?.toString() ?? '',
                          listingTitle: data['listingTitle']?.toString() ?? '',
                          listingImage: listingImage,
                          buyerId: data['buyerId']?.toString() ?? '',
                          sellerId: data['sellerId']?.toString() ?? '',
                          buyerName: data['buyerName']?.toString() ?? 'Buyer',
                          sellerName:
                              data['sellerName']?.toString() ?? 'Seller',
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Heuristic scam detector for chat — flags attempts to move the deal off
/// PakBazar or take advance/online payment, in English, Roman Urdu and Urdu.
bool looksScammy(String text) {
  final t = text.toLowerCase();
  const flags = [
    // English — advance / online payment
    'advance', 'deposit', 'booking fee', 'token money', 'token amount',
    'pay first', 'pay in advance', 'send money', 'bank account',
    'account number', 'account no', 'easypaisa', 'easy paisa', 'jazzcash',
    'jazz cash', 'western union', 'gift card', ' otp', 'one time password',
    'pin code', 'transfer the money', 'courier charge', 'delivery charges',
    // English — off-platform
    'deal outside', 'outside the app', 'off the app', 'whatsapp me',
    'contact me on whatsapp', 'call me directly', 'meet outside the',
    // Roman Urdu
    'paise bhej', 'paise bhej', 'advance bhej', 'advance de', 'pehle paise',
    'rakam bhej', 'booking ke paise', 'token ke paise', 'app se bahar',
    'bahar deal', 'whatsapp pe', 'account me paise', 'paise transfer',
    // Urdu script
    'پیسے', 'ایڈوانس', 'اکاؤنٹ', 'بھیجو', 'بھیج دو', 'رقم', 'ٹوکن',
    'جاز کیش', 'ایزی پیسہ',
  ];
  for (final f in flags) {
    if (t.contains(f)) return true;
  }
  return false;
}

/// Short clock time for chat bubbles, e.g. "3:07 PM".
String _msgTime(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  final m = d.minute.toString().padLeft(2, '0');
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$m $ampm';
}

/// Safety warning shown atop a chat when a message looks like an off-platform
/// or advance-payment scam.
class _ChatScamBanner extends StatelessWidget {
  const _ChatScamBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3CD),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stay safe: never pay in advance, share OTPs/bank details, or '
              'deal outside PakBazar. Report anyone who asks.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String listingImage;
  final String buyerId;
  final String sellerId;
  final String buyerName;
  final String sellerName;

  /// Read-only monitoring mode for admins: shows the whole thread (both sides)
  /// but hides the composer so the admin cannot post into the conversation.
  final bool adminView;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.listingImage,
    required this.buyerId,
    required this.sellerId,
    required this.buyerName,
    required this.sellerName,
    this.adminView = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final picker = ImagePicker();
  bool sendingImage = false;

  /// Live chat-doc metadata (participants' read/delivered markers), used to
  /// render delivery ticks on my own messages.
  Map<String, dynamic>? _meta;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _metaSub;

  DocumentReference get chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  /// The other party in this 1:1 thread (from my perspective).
  String get _otherUid =>
      widget.buyerId == _myUid ? widget.sellerId : widget.buyerId;

  @override
  void initState() {
    super.initState();
    if (!widget.adminView) {
      _metaSub = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .snapshots()
          .listen((snap) {
            if (mounted) setState(() => _meta = snap.data());
          });
    }
  }

  /// Marks messages from the other party as read once I have the thread open,
  /// guarded so it only writes when something newer than my last read exists.
  void _maybeMarkRead(Timestamp? latestIncoming) {
    final me = _myUid;
    if (widget.adminView || me == null || latestIncoming == null) return;
    final myRead = readMarker(_meta?['readAt'], me);
    if (myRead != null &&
        myRead.millisecondsSinceEpoch >=
            latestIncoming.millisecondsSinceEpoch) {
      return;
    }
    markChatRead(widget.chatId, me);
  }

  Future<void> sendImageMessage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || sendingImage) return;
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (img == null) return;
    setState(() => sendingImage = true);
    try {
      final bytes = await img.readAsBytes();
      final senderUid = FirebaseAuth.instance.currentUser?.uid;
      if (senderUid == null) return;
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(senderUid)
          .child(
            '${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
      await ref.putData(bytes, imageUploadMetadata());
      final url = await ref.getDownloadURL();
      await chatRef.set({
        'chatId': widget.chatId,
        'listingId': widget.listingId,
        'listingTitle': widget.listingTitle,
        'listingImage': widget.listingImage,
        'buyerId': widget.buyerId,
        'sellerId': widget.sellerId,
        'buyerName': widget.buyerName,
        'sellerName': widget.sellerName,
        'participants': [widget.buyerId, widget.sellerId],
        'lastMessage': '📷 Photo',
        'lastTime': Timestamp.now(),
      }, SetOptions(merge: true));
      await chatRef.collection('messages').add({
        'senderId': uid,
        'text': '📷 Photo',
        'imageUrl': url,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send photo: $e')));
      }
    } finally {
      if (mounted) setState(() => sendingImage = false);
    }
  }

  Future<void> sendMessage([String? preset]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final text = (preset ?? messageController.text).trim();
    if (uid == null || text.isEmpty) return;

    if (preset == null) messageController.clear();

    try {
      await chatRef.set({
        'chatId': widget.chatId,
        'listingId': widget.listingId,
        'listingTitle': widget.listingTitle,
        'listingImage': widget.listingImage,
        'buyerId': widget.buyerId,
        'sellerId': widget.sellerId,
        'buyerName': widget.buyerName,
        'sellerName': widget.sellerName,
        'participants': [widget.buyerId, widget.sellerId],
        'lastMessage': text,
        'lastTime': Timestamp.now(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': uid,
        'text': text,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      // Restore the typed text so it isn't lost on a failed send.
      if (preset == null) {
        messageController.text = text;
        messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: messageController.text.length),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send message: $e')));
      }
    }
  }

  @override
  void dispose() {
    _metaSub?.cancel();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final otherName = widget.adminView
        ? '${widget.buyerName} ↔ ${widget.sellerName}'
        : (widget.buyerId == uid ? widget.sellerName : widget.buyerName);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(otherName),
            if (widget.adminView)
              Text(
                widget.listingTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )
            else ...[
              PresenceStatusLine(_otherUid),
              Text(
                widget.listingTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.adminView)
            Container(
              width: double.infinity,
              // Opaque light gold so the notice is readable over navy.
              color: const Color(0xFFFBF3D5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Admin monitoring — read only. You cannot send messages here.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: chatRef
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorStateWidget(
                    message: 'We could not load this conversation.',
                    onRetry: () => setState(() {}),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                // Once the thread is open, mark the newest incoming message read
                // so the sender sees blue ticks. Post-frame to avoid writing
                // during build; guarded inside _maybeMarkRead against loops.
                if (!widget.adminView) {
                  Timestamp? latestIncoming;
                  for (final m in messages) {
                    final d = m.data() as Map<String, dynamic>;
                    if (d['senderId'] == _myUid) continue;
                    final ts = d['createdAt'] as Timestamp?;
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
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hello 👋',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                final scamRisk = messages.any(
                  (m) =>
                      looksScammy((m.data() as Map)['text']?.toString() ?? ''),
                );

                return Column(
                  children: [
                    if (scamRisk) const _ChatScamBanner(),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final data =
                              messages[index].data() as Map<String, dynamic>;
                          // In admin (monitoring) mode the viewer is neither party, so
                          // anchor the seller's messages right and the buyer's left and
                          // label who said what; otherwise it's the usual "me vs them".
                          final isMine = widget.adminView
                              ? data['senderId'] == widget.sellerId
                              : data['senderId'] == uid;
                          final senderLabel = widget.adminView
                              ? (data['senderId'] == widget.sellerId
                                    ? widget.sellerName
                                    : widget.buyerName)
                              : null;

                          return Align(
                            alignment: isMine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.72,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? kPakGreen
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isMine ? 14 : 2),
                                  bottomRight: Radius.circular(isMine ? 2 : 14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (senderLabel != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                        senderLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isMine
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  if ((data['imageUrl']?.toString() ?? '')
                                      .isNotEmpty)
                                    GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FullScreenGallery(
                                            images: [
                                              data['imageUrl'].toString(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: AppRadius.rSm,
                                        child: Image.network(
                                          data['imageUrl'].toString(),
                                          width: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.broken_image,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      data['text']?.toString() ?? '',
                                      style: TextStyle(
                                        color: isMine
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _msgTime(
                                          data['createdAt'] as Timestamp?,
                                        ),
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: isMine
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                      if (isMine && !widget.adminView) ...[
                                        const SizedBox(width: 4),
                                        MessageStatusTick(
                                          sentAt:
                                              data['createdAt'] as Timestamp?,
                                          deliveredAt: readMarker(
                                            _meta?['deliveredAt'],
                                            _otherUid,
                                          ),
                                          seenAt: readMarker(
                                            _meta?['readAt'],
                                            _otherUid,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (!widget.adminView)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final q in const [
                            'Is this still available?',
                            'Is this the last price?',
                            'Can I get a discount?',
                            'Can you tell me more about it?',
                            'Where can we meet?',
                            'Thank you for contacting!',
                          ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  q,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () => sendMessage(q),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Send photo',
                          onPressed: sendingImage ? null : sendImageMessage,
                          icon: sendingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_outlined,
                                  color: kPakGreen,
                                ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => sendMessage(),
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: kPakGreen,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
