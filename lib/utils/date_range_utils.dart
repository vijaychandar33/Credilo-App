import '../utils/closing_cycle_service.dart';

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

Future<DateRangeSelection?> resolveDateRange(
  DateRangeOption option, {
  DateTime? customStartDate,
  DateTime? customEndDate,
  String? branchId,
}) async {
  // Get business date for "today" - respects branch's closing cycle when branchId provided
  final DateTime businessDate = branchId != null && branchId.isNotEmpty
      ? await ClosingCycleService.getBusinessDate(branchId)
      : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final today = DateTime(businessDate.year, businessDate.month, businessDate.day);

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

