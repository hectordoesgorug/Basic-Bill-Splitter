import 'package:basic_bill_splitter/currency/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes the approved currency list and formats cents consistently', () {
    expect(supportedCurrencies, hasLength(20));
    expect(supportedCurrencies.first.label, 'PHP (₱)');
    expect(
      supportedCurrencies.map((option) => option.code).toSet(),
      hasLength(20),
    );
    expect(formatCurrency(123456, 'PHP'), '₱1,234.56');
    expect(formatCurrency(123456, 'USD'), '\$1,234.56');
    expect(formatCurrency(123456, 'EUR', includeCode: true), 'EUR €1,234.56');
    expect(formatCurrency(-5, 'JPY'), '-¥0.05');
    expect(() => formatCurrency(10, 'XYZ'), throwsFormatException);
  });
}
