import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The gate is the safety mechanism for the Firestore region migration: it is
// what stops an outdated client writing orders into a database nobody is
// watching after the cutover.
//
// Its failure modes are asymmetric. Failing to block is a bounded problem.
// Blocking WRONGLY takes the whole marketplace down for every user at once and
// cannot be fixed from the client. So most of what follows pins fail-open.

void main() {
  final realBuild = appBuildNumber;
  tearDown(() => appBuildNumber = realBuild);

  group('fail-open', () {
    test('a missing config document does not block', () {
      final gate = AppGateState.fromMap(null);
      expect(gate.blocks, isFalse);
      expect(gate.requiresUpdate, isFalse);
    });

    test('an empty config document does not block', () {
      expect(AppGateState.fromMap(<String, dynamic>{}).blocks, isFalse);
    });

    // appBuildNumber is 0 until the platform reports it. Treating 0 as "older
    // than the floor" would blank the app on every launch.
    test('an unknown build number never blocks', () {
      appBuildNumber = 0;
      final gate = AppGateState.fromMap({'minSupportedBuild': 999});
      expect(gate.requiresUpdate, isFalse);
      expect(gate.blocks, isFalse);
    });

    test('minSupportedBuild of 0 disables the version gate', () {
      appBuildNumber = 1;
      expect(
        AppGateState.fromMap({'minSupportedBuild': 0}).requiresUpdate,
        isFalse,
      );
    });

    test('junk field types do not block and do not throw', () {
      appBuildNumber = 10;
      for (final raw in <Map<String, dynamic>>[
        {'minSupportedBuild': 'not a number'},
        {'maintenance': 'yes'},
        {'minSupportedBuild': null, 'maintenance': null},
      ]) {
        late AppGateState gate;
        expect(() => gate = AppGateState.fromMap(raw), returnsNormally);
        expect(gate.blocks, isFalse, reason: 'raw: $raw');
      }
    });
  });

  group('blocking', () {
    test('an older build is asked to update', () {
      appBuildNumber = 50;
      final gate = AppGateState.fromMap({'minSupportedBuild': 68});
      expect(gate.requiresUpdate, isTrue);
      expect(gate.blocks, isTrue);
    });

    test('the exact floor build is allowed through', () {
      appBuildNumber = 68;
      expect(
        AppGateState.fromMap({'minSupportedBuild': 68}).requiresUpdate,
        isFalse,
      );
    });

    test('a newer build is allowed through', () {
      appBuildNumber = 99;
      expect(
        AppGateState.fromMap({'minSupportedBuild': 68}).requiresUpdate,
        isFalse,
      );
    });

    test('maintenance blocks every build, including the newest', () {
      appBuildNumber = 99999;
      final gate = AppGateState.fromMap({'maintenance': true});
      expect(gate.blocks, isTrue);
      expect(gate.requiresUpdate, isFalse);
    });
  });

  group('config parsing', () {
    test('carries the message and update url through', () {
      final gate = AppGateState.fromMap({
        'maintenance': true,
        'maintenanceMessage': 'Back in 10 minutes',
        'updateUrl': 'https://example.test/app',
      });
      expect(gate.maintenanceMessage, 'Back in 10 minutes');
      expect(gate.updateUrl, 'https://example.test/app');
    });

    test('numeric build arrives as an int even when stored as a double', () {
      expect(
        AppGateState.fromMap({'minSupportedBuild': 68.0}).minSupportedBuild,
        68,
      );
    });
  });
}
