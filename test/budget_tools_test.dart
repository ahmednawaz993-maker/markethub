import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

void main() {
  test('parseRupees ignores commas, spaces and symbols', () {
    expect(parseRupees('85,000'), 85000);
    expect(parseRupees('Rs 1 200'), 1200);
    expect(parseRupees(''), 0);
    expect(parseRupees('abc'), 0);
  });

  test('budget summary totals', () {
    const s = BudgetSummary(80000, 60000, 4);
    expect(s.left, 20000);
    expect(s.perPerson, 15000);
    expect(s.savingsPercent, 25);
    expect(s.spentShare, 0.75);
  });

  test('over budget and no income', () {
    const over = BudgetSummary(50000, 65000, 5);
    expect(over.left, -15000);
    expect(over.savingsPercent, -30);
    const none = BudgetSummary(0, 10000, 2);
    expect(none.savingsPercent, isNull);
    expect(none.spentShare, 0);
  });

  test('expense keys match the server allowlist', () {
    expect(kBudgetExpenseLines.map((l) => l.key).toList(), [
      'rent',
      'groceries',
      'utilities',
      'transport',
      'education',
      'health',
      'loans',
      'committee',
      'other',
    ]);
  });
}
