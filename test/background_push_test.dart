// What has to be true for a push to arrive while the app is not on screen.
//
// None of this can be exercised from a widget test — it is FCM, an Android
// manifest and a service worker. But all of it fails silently: the app keeps
// building, the tests keep passing, and the only symptom is that somebody
// stops being told they have a message. So the wiring itself is pinned here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the device keeps a usable token', () {
    final push = File('lib/src/push.dart').readAsStringSync();

    test('a rotated token is written as soon as FCM issues it', () {
      // Registration used to happen only at launch. FCM rotates tokens on its
      // own schedule, and a rotation while the app sat in the background left
      // the user unreachable until they next opened it.
      expect(push, contains('onTokenRefresh.listen(_registerToken)'));
    });

    test('the launch path and the refresh path write the same document', () {
      // The bug this guards against is a second, subtly different copy of the
      // write — a different collection, or one that forgets the platform
      // field the sender uses.
      expect(
        RegExp("collection\\('fcmTokens'\\)").allMatches(push).length,
        1,
        reason: 'one place writes the token, both paths call it',
      );
    });
  });

  group('what a background notification looks like on Android', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('a silhouette icon is declared for the status bar', () {
      // Without this FCM falls back to the launcher icon, which Android draws
      // from its alpha channel — a filled square becomes a white block.
      expect(
        manifest,
        contains('com.google.firebase.messaging.default_notification_icon'),
      );
      expect(manifest, contains('@drawable/ic_stat_notify'));
    });

    test('and an accent colour', () {
      expect(
        manifest,
        contains('com.google.firebase.messaging.default_notification_color'),
      );
      expect(
        File(
          'android/app/src/main/res/values/colors.xml',
        ).readAsStringSync(),
        contains('notification_accent'),
      );
    });

    test('the icon exists at every density', () {
      // A missing density is not a build error; the device just picks a
      // neighbour and scales it into a blur.
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File(
            'android/app/src/main/res/drawable-$d/ic_stat_notify.png',
          ).existsSync(),
          isTrue,
          reason: 'ic_stat_notify missing for $d',
        );
      }
    });

    test('the app may post notifications on Android 13+', () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    });
  });

  group('and on the web, where a tab may be closed entirely', () {
    final sw = File('web/firebase-messaging-sw.js').readAsStringSync();

    test('the worker shows the push', () {
      expect(sw, contains('onBackgroundMessage'));
      expect(sw, contains('showNotification'));
    });

    test('tapping it goes somewhere', () {
      // It used to go nowhere: the worker showed a notification with no click
      // handler, so tapping it dismissed it and that was all.
      expect(sw, contains('notificationclick'));
      expect(sw, contains('openWindow'));
    });

    test('an existing tab is reused rather than stacked', () {
      expect(sw, contains('matchAll'));
      expect(sw, contains('client.focus()'));
    });
  });
}
