part of '../main.dart';

// ---------------------------------------------------------------------------
// Minimum-version gate and maintenance mode.
//
// WHY THIS EXISTS: Firestore cannot change region in place, so moving the
// database to asia-south1 means standing up a NEW database and cutting over.
// The moment that happens, every user still running an older build keeps
// reading and writing the OLD one — and on a marketplace holding escrow, that
// is orders placed, payments confirmed and refunds issued into a database
// nobody is watching. Silent money loss, not slow performance.
//
// Nothing in the app could previously tell an old client to stop. This can.
// It is the prerequisite for the migration, and it is independently useful
// whenever a release turns out to be broken.
//
// Driven by `config/appGate`:
//   minSupportedBuild : int    builds below this are blocked  (0 = disabled)
//   maintenance       : bool   block everyone, e.g. during a cutover
//   maintenanceMessage: string what to tell users
//   updateUrl         : string Play listing; falls back to the known one
//
// TWO RULES THIS FILE MUST NEVER BREAK:
//
//  1. FAIL OPEN. If the document is missing, unreadable, or the build number
//     is unknown, the app runs normally. A gate that fails closed would brick
//     every install the moment Firestore hiccups — far worse than the problem
//     it solves. A client that cannot reach Firestore cannot corrupt it either.
//
//  2. LIVE, not once. It listens rather than polling at startup, so flipping
//     maintenance on reaches running apps within seconds instead of on next
//     launch. During a cutover that difference is the whole point.
// ---------------------------------------------------------------------------

/// Play Store listing, used when the config supplies no updateUrl.
const String kPlayListingUrl =
    'https://play.google.com/store/apps/details?id=com.pakbazar24.app';

class AppGateState {
  final int minSupportedBuild;
  final bool maintenance;
  final String maintenanceMessage;
  final String updateUrl;

  const AppGateState({
    this.minSupportedBuild = 0,
    this.maintenance = false,
    this.maintenanceMessage = '',
    this.updateUrl = '',
  });

  /// Tolerant of whatever is actually in the document.
  ///
  /// A plain `as num?` cast throws when the field holds a string — and this
  /// document is hand-edited in the Firebase console, so a typed "68" is a
  /// realistic input. A safety mechanism must not be the thing that breaks on
  /// malformed input, so anything unparseable degrades to "do not block".
  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  factory AppGateState.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const AppGateState();
    return AppGateState(
      minSupportedBuild: _asInt(m['minSupportedBuild']),
      maintenance: m['maintenance'] == true,
      maintenanceMessage: m['maintenanceMessage']?.toString() ?? '',
      updateUrl: m['updateUrl']?.toString() ?? '',
    );
  }

  /// True when this build is older than the configured floor.
  ///
  /// Requires a known build number: [appBuildNumber] is 0 until the platform
  /// reports it, and 0 must never count as "too old" or the gate would block
  /// everyone for the first moments of every launch.
  bool get requiresUpdate =>
      minSupportedBuild > 0 &&
      appBuildNumber > 0 &&
      appBuildNumber < minSupportedBuild;

  bool get blocks => maintenance || requiresUpdate;
}

/// Current gate state. Defaults to "not blocking" and only ever tightens once
/// the config is actually read.
final ValueNotifier<AppGateState> appGateState =
    ValueNotifier<AppGateState>(const AppGateState());

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _gateSub;

/// Subscribes to `config/appGate`. Safe to call more than once.
void listenToAppGate() {
  if (_gateSub != null) return;
  try {
    _gateSub = FirebaseFirestore.instance
        .collection('config')
        .doc('appGate')
        .snapshots()
        .listen(
          (snap) => appGateState.value = AppGateState.fromMap(snap.data()),
          // Denied or offline: stay open. See rule 1 above.
          onError: (_) => appGateState.value = const AppGateState(),
        );
  } catch (_) {
    // Never let the gate stop the app from starting.
  }
}

/// Wraps the app and replaces it with a blocking screen when required.
class AppGate extends StatelessWidget {
  final Widget child;

  const AppGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppGateState>(
      valueListenable: appGateState,
      builder: (context, gate, _) {
        if (!gate.blocks) return child;
        return _AppGateBlockedScreen(gate: gate);
      },
    );
  }
}

class _AppGateBlockedScreen extends StatelessWidget {
  final AppGateState gate;

  const _AppGateBlockedScreen({required this.gate});

  Future<void> _openStore() async {
    final url = gate.updateUrl.trim().isNotEmpty
        ? gate.updateUrl.trim()
        : kPlayListingUrl;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing useful to do if no browser or store app is available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final maintenance = gate.maintenance;
    final message = gate.maintenanceMessage.trim();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  maintenance
                      ? Icons.build_circle_outlined
                      : Icons.system_update,
                  size: 64,
                  color: AppColors.accent,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  maintenance
                      ? 'PakBazar is being upgraded'
                      : 'Please update PakBazar',
                  textAlign: TextAlign.center,
                  style: AppType.sectionTitle,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  message.isNotEmpty
                      ? message
                      : (maintenance
                            ? 'We are making PakBazar faster. This takes a few '
                                  'minutes — please check back shortly.'
                            : 'This version is out of date and can no longer '
                                  'buy or sell safely. Update to continue.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!maintenance)
                  ElevatedButton.icon(
                    onPressed: _openStore,
                    icon: const Icon(Icons.download),
                    label: const Text('Update now'),
                  ),
                if (maintenance)
                  // Maintenance clears server-side; the listener picks it up
                  // within seconds, so there is nothing for the user to do but
                  // wait. A retry button that cannot help would be a lie.
                  Text(
                    'This screen will close by itself when we are done.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
