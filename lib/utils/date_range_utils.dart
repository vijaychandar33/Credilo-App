enum DateRangeOption {
  allTime,
  today,
  yesterday,
  last7Days,
  last2Weeks,
  lastMonth,
  custom,
}

class DateRangeSelection {
  final DateTime startDate;
  final DateTime endDate;

  const DateRangeSelection({
    required this.startDate,
    required this.endDate,
  });
}

DateRangeSelection? resolveDateRange(
  DateRangeOption option, {
  DateTime? customStartDate,
  DateTime? customEndDate,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (option) {
    case DateRangeOption.allTime:
      return null; // null means no date filter (all time)
    case DateRangeOption.today:
      return DateRangeSelection(startDate: today, endDate: today);
    case DateRangeOption.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return DateRangeSelection(startDate: yesterday, endDate: yesterday);
    case DateRangeOption.last7Days:
      return DateRangeSelection(
        startDate: today.subtract(const Duration(days: 6)),
        endDate: today,
      );
    case DateRangeOption.last2Weeks:
      return DateRangeSelection(
        startDate: today.subtract(const Duration(days: 13)),
        endDate: today,
      );
    case DateRangeOption.lastMonth:
      return DateRangeSelection(
        startDate: today.subtract(const Duration(days: 29)),
        endDate: today,
      );
    case DateRangeOption.custom:
      if (customStartDate != null && customEndDate != null) {
        final start = DateTime(customStartDate.year, customStartDate.month, customStartDate.day);
        final end = DateTime(customEndDate.year, customEndDate.month, customEndDate.day);
        return DateRangeSelection(startDate: start, endDate: end);
      }
      return DateRangeSelection(startDate: today, endDate: today);
  }
}

