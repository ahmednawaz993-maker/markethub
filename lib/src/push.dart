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

    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
            'createdAt': Timestamp.now(),
            'platform': kIsWeb ? 'web' : 'app',
          });
    }

    if (!_onMessageListenerRegistered) {
      _onMessageListenerRegistered = true;
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n != null) {
          // App is open — the OS won't play the notification sound, so chime
          // + buzz here to make sure the seller notices the new message.
          playNotificationAlert();
          rootMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(
                [n.title, n.body].where((e) => (e ?? '').isNotEmpty).join(': '),
              ),
              // Tapping "View" jumps to whatever the notification is about.
              action: SnackBarAction(
                label: 'View',
                onPressed: () => handlePushTap(message),
              ),
            ),
          );
        }
      });

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
