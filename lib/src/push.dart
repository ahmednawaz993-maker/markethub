part of '../main.dart';

// Firebase Cloud Messaging / push-notification setup.

const String fcmVapidKey =
    'BAOvH3nPZu5Q8_NQivTrJuOM-i2YY1BvBx9gKf-df5RexGZhzejVShaMudQ1GBMejHjylLWMt75LY5xzuopJPPY';

/// Shows snackbars from anywhere (e.g. foreground push notifications).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Global navigator, so a tapped push notification (system tray → app) can
/// deep-link to the thing it's about from outside the widget tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Turns an FCM data payload into the `{type, refId, title, body}` shape the
/// in-app notification router understands, then opens the target. The push
/// `data` map uses a per-type id key (orderId, chatId, …); normalise it to a
/// single `refId` exactly as the Cloud Function does when it stores the inbox
/// copy.
void handlePushTap(RemoteMessage message) {
  final data = message.data;
  final type = (data['type'] ?? '').toString();
  if (type.isEmpty) return;
  final refId =
      (data['refId'] ??
              data['orderId'] ??
              data['offerId'] ??
              data['chatId'] ??
              data['listingId'] ??
              data['ticketId'] ??
              data['withdrawalId'] ??
              data['masterId'] ??
              '')
          .toString();
  final n = message.notification;
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;
  openNotificationTarget(ctx, {
    'type': type,
    'refId': refId,
    'title': n?.title ?? '',
    'body': n?.body ?? '',
  });
}

/// Shows a premium heads-up notification banner that slides in from the TOP of
/// the screen (over whatever the user is doing), auto-dismisses after a few
/// seconds, and deep-links on tap. Used for foreground push notifications
/// instead of a bottom snackbar. No-ops if the navigator/overlay isn't ready.
void showTopNotificationBanner({
  required String title,
  required String body,
  VoidCallback? onTap,
}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _TopNotificationBanner(
      title: title,
      body: body,
      onTap: onTap,
      onClosed: remove,
    ),
  );
  overlay.insert(entry);
}

class _TopNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback onClosed;
  const _TopNotificationBanner({
    required this.title,
    required this.body,
    required this.onClosed,
    this.onTap,
  });

  @override
  State<_TopNotificationBanner> createState() => _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    // Auto-dismiss after a few seconds if the user doesn't interact.
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) {
      try {
        await _c.reverse();
      } catch (_) {}
    }
    widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _c,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: _c,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: AppRadius.rCard,
                  onTap: () {
                    final cb = widget.onTap;
                    if (cb != null) cb();
                    _dismiss();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.rCard,
                      border: Border.all(
                        color: kPakGreen.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kPakGreen.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_active,
                            color: kPakGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.title.isNotEmpty)
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              if (widget.body.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    widget.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          onPressed: _dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-lived player reused for the in-app notification chime, so a new message
/// arriving while the app is open (foreground) is audible — Android suppresses
/// the system notification sound when the app is in the foreground, delivering
/// the message to `onMessage` instead. Low-latency so the ding is instant.
final AudioPlayer _notifyPlayer = AudioPlayer()
  ..setPlayerMode(PlayerMode.lowLatency)
  ..setReleaseMode(ReleaseMode.stop);

/// Plays the short notification chime and a light buzz. Best-effort: any audio
/// error (no audio focus, muted, etc.) is ignored so it never breaks the push.
Future<void> playNotificationAlert() async {
  try {
    await HapticFeedback.mediumImpact();
    await _notifyPlayer.stop();
    await _notifyPlayer.play(AssetSource('sounds/notify.wav'));
  } catch (_) {
    // Audio unavailable — the snackbar/notification still shows.
  }
}

/// Ensures the foreground `onMessage` listener is registered only once for the
/// app's lifetime, even if `setupPushNotifications()` runs again (e.g. when
/// HomeScreen re-mounts).
bool _onMessageListenerRegistered = false;

/// Records this device's token against the signed-in user, which is what the
/// Cloud Functions read when they push. Best-effort: a device that cannot
/// write it just does not get notified.
Future<void> _registerToken(String token) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token)
        .set({
          'createdAt': Timestamp.now(),
          'platform': kIsWeb ? 'web' : 'app',
        });
  } catch (_) {
    // Offline or signed out mid-flight.
  }
}

/// Requests notification permission, registers this device's FCM token under
/// users/{uid}/fcmTokens, and surfaces foreground messages. Fully guarded:
/// if messaging isn't configured/available it silently no-ops.
Future<void> setupPushNotifications() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // On web a VAPID key is required; skip cleanly until it's set.
    if (kIsWeb && fcmVapidKey.isEmpty) return;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: fcmVapidKey)
        : await messaging.getToken();

    if (token != null) await _registerToken(token);

    if (!_onMessageListenerRegistered) {
      _onMessageListenerRegistered = true;
      FirebaseMessaging.onMessage.listen((message) {
        // A push arriving IS the change signal. The badge used to learn this
        // from a permanent Firestore listener watching for the very event that
        // is being delivered here anyway — so the listener is gone and this
        // updates the count instead. See user_session.dart.
        userSession.refreshUnread();

        final n = message.notification;
        if (n != null) {
          // App is open — the OS won't play the notification sound, so chime
          // + buzz here to make sure the seller notices the new message.
          playNotificationAlert();
          // Premium heads-up banner slides in from the TOP of the screen (not a
          // bottom snackbar). Tapping it deep-links to whatever it's about.
          showTopNotificationBanner(
            title: n.title ?? '',
            body: n.body ?? '',
            onTap: () => handlePushTap(message),
          );
        }
      });

      // FCM rotates a device's token on its own schedule — a restore to a new
      // phone, a Play Services update, clearing the app's data. The old token
      // stops receiving anything at that moment, and registration only ran at
      // launch, so a user who left the app in the background simply stopped
      // being notified until they next opened it. This writes the replacement
      // as soon as it is issued.
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

      // Tapping a tray notification while the app is backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen(handlePushTap);

      // App launched from a tray notification (cold start): route once the
      // navigator exists, after the first frame.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => handlePushTap(initial),
        );
      }
    }
  } catch (_) {
    // Messaging unavailable/unconfigured — ignore.
  }
}

/// Mirrors this device's FCM token into the shared `supportTokens` collection
/// when the signed-in user is a Customer Care agent (super admin or 'support'
/// staff), so the notifyOnNewSupportMessage Cloud Function can push new-message
/// alerts to every agent's device — even when the app is closed. Best-effort;
/// call after staff permissions have loaded (e.g. when the admin panel opens).
Future<void> syncSupportPushToken() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (kIsWeb && fcmVapidKey.isEmpty) return;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: fcmVapidKey)
        : await messaging.getToken();
    if (token == null) return;

    final ref = FirebaseFirestore.instance
        .collection('supportTokens')
        .doc(token);
    if (isSuperAdmin() || hasAdminPerm('support')) {
      await ref.set({
        'uid': uid,
        'platform': kIsWeb ? 'web' : 'app',
        'updatedAt': Timestamp.now(),
      });
    } else {
      // No longer an agent on this device — drop any stale registration.
      await ref.delete();
    }
  } catch (_) {
    // Messaging unavailable / not permitted / not an agent — ignore.
  }
}

/// Default country dialing code for Pakistan (used to build WhatsApp links).
