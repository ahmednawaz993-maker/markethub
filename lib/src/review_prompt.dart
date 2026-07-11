part of '../main.dart';

// Policy-compliant Play Store in-app review flow.
//
// Rules we hold to (Google Play review policy):
//  * No incentives, coins, discounts or rewards for reviewing.
//  * Never force or pre-select a star rating; never ask for "only 5 stars".
//  * Never block features behind a review, never nag.
//  * Never fake the Play review sheet — we call the official API and let Google
//    decide whether to show it.
//  * We do NOT learn or claim the star rating that Google collects.
//  * Never shown during checkout / payment / OTP / disputes / errors.
//
// Engagement state lives on-device (SharedPreferences); only anonymous funnel
// events go to Firestore (see section I analytics).

/// Configurable eligibility thresholds — kept in one place, not scattered as
/// magic numbers. Tune here without touching the flow logic.
class ReviewPromptConfig {
  static const int minSessions = 5;
  static const int minActiveDays = 3;
  static const int minDaysSinceInstall = 7;
  static const int cooldownDays = 90;

  /// Stop asking entirely after this many "Not now" dismissals (anti-nag).
  static const int maxDismissals = 3;
}

// SharedPreferences keys for the review-prompt state (all local to the device).
const _kFirstInstallAt = 'rp_firstInstallAt'; // ms since epoch
const _kSessionCount = 'rp_sessionCount';
const _kActiveDayCount = 'rp_activeDayCount';
const _kLastActiveDay = 'rp_lastActiveDay'; // 'y-m-d'
const _kMeaningfulAction = 'rp_meaningfulActionCompleted';
const _kLastPromptAt = 'rp_lastPromptAt'; // ms since epoch
const _kDismissCount = 'rp_promptDismissCount';
const _kFeedbackSubmitted = 'rp_feedbackSubmitted';
const _kReviewFlowRequested = 'rp_reviewFlowRequested';

/// Records one app-engagement session. Call once per launch (from main).
/// Sets firstInstallAt on first ever launch, bumps sessionCount, and counts a
/// new active day when the calendar day changes.
Future<void> recordAppSession() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (!prefs.containsKey(_kFirstInstallAt)) {
      await prefs.setInt(_kFirstInstallAt, now.millisecondsSinceEpoch);
    }
    await prefs.setInt(_kSessionCount, (prefs.getInt(_kSessionCount) ?? 0) + 1);
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString(_kLastActiveDay) != today) {
      await prefs.setString(_kLastActiveDay, today);
      await prefs.setInt(
        _kActiveDayCount,
        (prefs.getInt(_kActiveDayCount) ?? 0) + 1,
      );
    }
  } catch (_) {
    // Non-critical — never block app startup on this.
  }
}

/// Marks that the user completed a meaningful action (a successful order, or a
/// published listing). One is enough to satisfy that eligibility signal.
Future<void> recordMeaningfulAction() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMeaningfulAction, true);
  } catch (_) {}
}

/// True when every eligibility rule is currently satisfied.
bool _isReviewEligible(SharedPreferences prefs) {
  final firstInstall = prefs.getInt(_kFirstInstallAt);
  if (firstInstall == null) return false;

  // Already went through the official flow once — don't ask again.
  if (prefs.getBool(_kReviewFlowRequested) ?? false) return false;
  if ((prefs.getInt(_kDismissCount) ?? 0) >= ReviewPromptConfig.maxDismissals) {
    return false;
  }

  final now = DateTime.now();
  final daysSinceInstall = now
      .difference(DateTime.fromMillisecondsSinceEpoch(firstInstall))
      .inDays;

  if ((prefs.getInt(_kSessionCount) ?? 0) < ReviewPromptConfig.minSessions) {
    return false;
  }
  if ((prefs.getInt(_kActiveDayCount) ?? 0) <
      ReviewPromptConfig.minActiveDays) {
    return false;
  }
  if (!(prefs.getBool(_kMeaningfulAction) ?? false)) return false;
  if (daysSinceInstall < ReviewPromptConfig.minDaysSinceInstall) return false;

  final lastPrompt = prefs.getInt(_kLastPromptAt);
  if (lastPrompt != null) {
    final daysSincePrompt = now
        .difference(DateTime.fromMillisecondsSinceEpoch(lastPrompt))
        .inDays;
    if (daysSincePrompt < ReviewPromptConfig.cooldownDays) return false;
  }
  return true;
}

/// Best-effort, privacy-conscious funnel analytics (section I). We store only
/// the event name + uid + platform + server time — never the star rating.
Future<void> _logReviewEvent(String event) async {
  try {
    await FirebaseFirestore.instance.collection('reviewPromptEvents').add({
      'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'event': event,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'at': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

/// Shows the satisfaction prompt IF eligible. Call ONLY from safe, neutral
/// screens (e.g. Home) — never during checkout / payment / OTP / disputes /
/// errors. No-op on web/desktop (no in-app review there).
Future<void> maybeShowReviewPrompt(BuildContext context) async {
  if (kIsWeb) return;
  if (!(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  if (!_isReviewEligible(prefs)) return;
  if (!context.mounted) return;

  _logReviewEvent('eligible');
  _logReviewEvent('prompt_shown');
  // Starting the cooldown as soon as we prompt (regardless of the answer).
  await prefs.setInt(_kLastPromptAt, DateTime.now().millisecondsSinceEpoch);
  if (!context.mounted) return;

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you enjoying PakBazar?'),
      content: const Text('Your honest feedback helps us improve.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'not_now'),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'not_really'),
          child: const Text('Not really'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, 'yes'),
          child: const Text('Yes'),
        ),
      ],
    ),
  );

  switch (choice) {
    case 'yes':
      _logReviewEvent('yes');
      // Mark requested BEFORE calling so a failure can't loop the prompt.
      await prefs.setBool(_kReviewFlowRequested, true);
      _logReviewEvent('review_flow_requested');
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          // Google decides whether to actually show the sheet; we never learn
          // the rating and never claim a review was submitted.
          await review.requestReview();
        }
      } catch (_) {}
    case 'not_really':
      _logReviewEvent('not_really');
      if (context.mounted) await _showPrivateFeedbackDialog(context, prefs);
    default:
      // 'not_now' or dismissed by tapping outside.
      _logReviewEvent('not_now');
      await prefs.setInt(
        _kDismissCount,
        (prefs.getInt(_kDismissCount) ?? 0) + 1,
      );
  }
}

/// Private feedback capture shown when the user says "Not really". We do NOT
/// send them to the Play Store — we collect improvement notes for admins in the
/// existing `feedback` collection.
Future<void> _showPrivateFeedbackDialog(
  BuildContext context,
  SharedPreferences prefs,
) async {
  final controller = TextEditingController();
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tell us how we can improve'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'What could be better? (private — only our team sees this)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  if (sent == true) {
    final text = controller.text.trim();
    if (text.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('feedback').add({
          'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
          'source': 'review_prompt',
          'message': text,
          'createdAt': Timestamp.now(),
        });
        await prefs.setBool(_kFeedbackSubmitted, true);
        _logReviewEvent('feedback_submitted');
      } catch (_) {}
    }
  }
  controller.dispose();
}
