const supportedCurrencies = <CurrencyOption>[
  CurrencyOption('PHP', '₱'),
  CurrencyOption('USD', r'$'),
  CurrencyOption('EUR', '€'),
  CurrencyOption('GBP', '£'),
  CurrencyOption('JPY', '¥'),
  CurrencyOption('CNY', '¥'),
  CurrencyOption('INR', '₹'),
  CurrencyOption('CAD', 'C\$'),
  CurrencyOption('AUD', 'A\$'),
  CurrencyOption('SGD', 'S\$'),
  CurrencyOption('NZD', 'NZ\$'),
  CurrencyOption('HKD', 'HK\$'),
  CurrencyOption('KRW', '₩'),
  CurrencyOption('TWD', 'NT\$'),
  CurrencyOption('THB', '฿'),
  CurrencyOption('MYR', 'RM'),
  CurrencyOption('IDR', 'Rp'),
  CurrencyOption('VND', '₫'),
  CurrencyOption('AED', 'د.إ'),
  CurrencyOption('CHF', 'CHF'),
];

class CurrencyOption {
  const CurrencyOption(this.code, this.symbol);

  final String code;
  final String symbol;

  String get label => '$code ($symbol)';
}

CurrencyOption currencyOption(String code) {
  for (final option in supportedCurrencies) {
    if (option.code == code) return option;
  }
  throw FormatException('Unsupported currency code: $code');
}

String formatCurrency(int cents, String code, {bool includeCode = false}) {
  final option = currencyOption(code);
  final absolute = cents.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final amount = '$whole.$fraction';
  final symbolValue = RegExp(r'^[A-Z]+$').hasMatch(option.symbol)
      ? '${option.symbol} $amount'
      : '${option.symbol}$amount';
  final signed = cents < 0 ? '-$symbolValue' : symbolValue;
  return includeCode ? '${option.code} $signed' : signed;
}
