// Unit tests for PakBazar pure helpers.

import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  test('formatPrice groups digits with commas', () {
    expect(formatPrice('4250000'), 'Rs 4,250,000');
    expect(formatPrice('500'), 'Rs 500');
  });

  test('formatPrice handles empty input gracefully', () {
    expect(formatPrice(''), 'Rs');
  });
}
