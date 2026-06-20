part of '../main.dart';

// Firebase Cloud Messaging / push-notification setup.

const String fcmVapidKey =
    'BAOvH3nPZu5Q8_NQivTrJuOM-i2YY1BvBx9gKf-df5RexGZhzejVShaMudQ1GBMejHjylLWMt75LY5xzuopJPPY';

/// Shows snackbars from anywhere (e.g. foreground push notifications).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

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

    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) {
        rootMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              [n.title, n.body].where((e) => (e ?? '').isNotEmpty).join(': '),
            ),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    });
  } catch (_) {
    // Messaging unavailable/unconfigured — ignore.
  }
}

/// Default country dialing code for Pakistan (used to build WhatsApp links).
