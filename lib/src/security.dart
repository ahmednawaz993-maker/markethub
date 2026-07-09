part of '../main.dart';

// Device integrity / anti-tamper gate.
//
// Blocks rooted / jailbroken devices from using PakBazar, as an anti-fraud
// measure that complements the mocked-GPS rejection in
// determineCurrentPosition(). Enforced ONLY on real Android/iOS release builds
// — debug/profile builds, web and desktop pass through so development and the
// web app are unaffected.
//
// NOTE: this is a client-side check and can be defeated on a sufficiently
// tampered device. Server-verified Play Integrity attestation is the stronger
// follow-up once the app is registered in Play Console.

class DeviceIntegrity {
  /// True if the device fails our security checks (currently: root / jailbreak).
  /// Fails open on any error so a flaky native check never locks out a genuine
  /// user.
  static Future<bool> isCompromised() async {
    // Never enforce on web/desktop or in non-release builds.
    if (kIsWeb || !kReleaseMode) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      return await SafeDevice.isJailBroken;
    } catch (_) {
      return false;
    }
  }
}

/// Runs the device-integrity check once at startup, showing a spinner while it
/// resolves, then either [child] (safe) or a blocking screen (compromised).
class SecurityGate extends StatefulWidget {
  final Widget child;
  const SecurityGate({super.key, required this.child});

  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate> {
  // null = still checking, false = safe, true = blocked.
  bool? _blocked;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final bad = await DeviceIntegrity.isCompromised();
    if (mounted) setState(() => _blocked = bad);
  }

  @override
  Widget build(BuildContext context) {
    if (_blocked == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_blocked == true) {
      return _BlockedScreen(
        onRetry: () {
          setState(() => _blocked = null);
          _run();
        },
      );
    }
    return widget.child;
  }
}

/// Full-screen notice shown when the device fails the integrity check.
class _BlockedScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _BlockedScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad, size: 88, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'Device not supported',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'For the safety of our marketplace, PakBazar can’t run on '
                'rooted or tampered devices. Please open PakBazar on a standard, '
                'unmodified phone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
