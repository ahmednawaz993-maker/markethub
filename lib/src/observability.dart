part of '../main.dart';

// Crash reporting and product analytics.
//
// Everything funnels through this file so call sites stay one-liners and so
// there is exactly one place that decides what may leave the device.
//
// PRIVACY RULE, and it is not negotiable: no personally identifying value ever
// becomes an analytics parameter or a Crashlytics key. No email, phone, name,
// address, or free-text the user typed (search terms included — people paste
// phone numbers into search boxes). Ids, categories, prices and counts only.
// The one identifier we do set is the Firebase uid, which is already the
// account handle and is what makes a crash report actionable.

/// Set false to compile the app with no analytics/crash reporting at all.
const bool kObservabilityEnabled = true;

FirebaseAnalytics? _analytics;

FirebaseAnalytics? get analytics => _analytics;

/// Wires up Crashlytics and Analytics. Safe to call before runApp.
///
/// Crash reporting is disabled in debug so local stack traces stay in the
/// console and do not pollute the production crash list.
Future<void> initObservability() async {
  if (!kObservabilityEnabled) return;

  // Crashlytics has no web implementation; calling into it there throws.
  if (!kIsWeb) {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);

      // Uncaught Flutter framework errors.
      final priorOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        crashlytics.recordFlutterFatalError(details);
        priorOnError?.call(details);
      };

      // Uncaught errors from the engine/platform side, including anything
      // thrown in an async gap that no zone caught.
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (_) {
      // Never let telemetry setup stop the app from starting.
    }
  }

  try {
    _analytics = FirebaseAnalytics.instance;
    await _analytics!.setAnalyticsCollectionEnabled(kReleaseMode);
  } catch (_) {
    _analytics = null;
  }
}

/// Associates subsequent crashes and events with the signed-in account.
/// Pass null on sign-out.
Future<void> setObservabilityUser(String? uid) async {
  if (!kObservabilityEnabled) return;
  try {
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
    }
    await _analytics?.setUserId(id: uid);
  } catch (_) {
    // Non-critical.
  }
}

/// Records a handled error — something we caught and recovered from, but still
/// want to see. Use this in the catch blocks that currently swallow silently.
Future<void> recordHandledError(
  Object error,
  StackTrace? stack, {
  String? context,
}) async {
  if (!kObservabilityEnabled || kIsWeb) return;
  try {
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: context,
      fatal: false,
    );
  } catch (_) {
    // Non-critical.
  }
}

/// Leaves a breadcrumb in the next crash report. Keep these free of user text.
void logBreadcrumb(String message) {
  if (!kObservabilityEnabled || kIsWeb) return;
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {
    // Non-critical.
  }
}

// ---------------------------------------------------------------------------
// Product events
//
// Six events covering the two funnels that decide whether a marketplace works:
// buyer (see -> checkout -> purchase) and seller (post). Plus search, the most
// used surface, and sign-up.
// ---------------------------------------------------------------------------

Future<void> _log(String name, [Map<String, Object>? params]) async {
  if (!kObservabilityEnabled) return;
  try {
    await _analytics?.logEvent(name: name, parameters: params);
  } catch (_) {
    // Analytics must never break a user flow.
  }
}

/// A buyer opened a listing.
Future<void> trackViewListing({
  required String listingId,
  required String category,
  required num price,
}) {
  return _log('view_listing', {
    'listing_id': listingId,
    'category': category,
    'price': price,
  });
}

/// A buyer reached checkout. The top of the paying funnel.
Future<void> trackBeginCheckout({
  required num value,
  required int itemCount,
  required String paymentMethod,
}) {
  return _log('begin_checkout', {
    'value': value,
    'currency': 'PKR',
    'item_count': itemCount,
    'payment_method': paymentMethod,
  });
}

/// An order was placed. The bottom of the paying funnel.
Future<void> trackPurchase({
  required String orderId,
  required num value,
  required String paymentMethod,
  required int itemCount,
}) {
  return _log('purchase', {
    'transaction_id': orderId,
    'value': value,
    'currency': 'PKR',
    'payment_method': paymentMethod,
    'item_count': itemCount,
  });
}

/// A seller published a listing. The seller-side activation metric.
Future<void> trackPostListing({
  required String category,
  required num price,
  required int photoCount,
}) {
  return _log('post_listing', {
    'category': category,
    'price': price,
    'photo_count': photoCount,
  });
}

/// A search ran.
///
/// Deliberately records only the SHAPE of the search — never the query text,
/// which is user-typed and routinely contains phone numbers. `result_count`
/// is the valuable part: a rising share of zero-result searches is the
/// clearest signal that supply is missing.
Future<void> trackSearch({
  required int resultCount,
  required bool hasFilters,
  String category = '',
}) {
  return _log('search', {
    'result_count': resultCount,
    'zero_results': resultCount == 0,
    'has_filters': hasFilters,
    'category': category,
  });
}

/// A new account was created.
Future<void> trackSignUp({required String method}) {
  return _log('sign_up', {'method': method});
}
