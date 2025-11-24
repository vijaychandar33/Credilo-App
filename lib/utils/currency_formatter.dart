import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final Map<int, NumberFormat> _formatters = {};

  static NumberFormat _getFormatter(int decimalDigits) {
    return _formatters.putIfAbsent(
      decimalDigits,
      () => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: decimalDigits,
      ),
    );
  }

  static String format(
    num? value, {
    int decimalDigits = 2,
  }) {
    final formatter = _getFormatter(decimalDigits);
    return formatter.format((value ?? 0).toDouble());
  }
}

