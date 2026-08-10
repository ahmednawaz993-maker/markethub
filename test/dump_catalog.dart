import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Not a test - a one-off exporter. Dumps the built-in catalog exactly as the app
// would serialise it, so a Firestore seed cannot drift from the Dart source.
//
//   CATALOG_OUT=<path> flutter test test/dump_catalog.dart
//
// Skips unless CATALOG_OUT is set, so a plain `flutter test` does not write a
// stray file into the repo.
void main() {
  test('dump built-in catalog to CATALOG_OUT', () {
    final path = Platform.environment['CATALOG_OUT'];
    if (path == null || path.isEmpty) {
      markTestSkipped('CATALOG_OUT not set - nothing to export');
      return;
    }
    final items = defaultCatalog().map((c) => c.toMap()).toList();
    File(path).writeAsStringSync(jsonEncode(items));
    stdout.writeln('wrote ${items.length} categories to $path');
  });
}
