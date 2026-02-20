import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateSelector extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<DateSelector> createState() => _DateSelectorState();
}

class _DateSelectorState extends State<DateSelector> {
  late PageController _pageController;
  late DateTime _selectedDate;

  static const int _initialPage = 1000;
  static const int _daysPerChunk = 5;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void didUpdateWidget(DateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _selectedDate = widget.selectedDate;
    }
  }

  /// Center day for a 5-day chunk: today + (pageOffset * 5).
  /// Chunk shows [center-2, center-1, center, center+1, center+2].
  List<DateTime> _getChunkDays(int pageOffset) {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final centerDay = todayDateOnly.add(Duration(days: pageOffset * _daysPerChunk));
    return List.generate(
      _daysPerChunk,
      (index) => centerDay.add(Duration(days: index - 2)),
    );
  }

  /// Page offset that contains the given date.
  int _pageOffsetForDate(DateTime date) {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final diff = date.difference(todayDateOnly).inDays;
    return ((diff + 2) / _daysPerChunk).floor();
  }

  void _onDateTap(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    widget.onDateSelected(date);
  }

  void _jumpToToday() {
    _pageController.animateToPage(
      _initialPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    _onDateTap(todayDateOnly);
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final pageOffset = _pageOffsetForDate(picked);
      _pageController.animateToPage(
        _initialPage + pageOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      final dateOnly = DateTime(picked.year, picked.month, picked.day);
      _onDateTap(dateOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.3 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 80,
              child: PageView.builder(
                controller: _pageController,
                itemBuilder: (context, page) {
                  final pageOffset = page - _initialPage;
                  final days = _getChunkDays(pageOffset);

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: days.map((date) {
                      final isSelected = _isSameDay(date, _selectedDate);
                      final isToday = _isSameDay(date, todayDateOnly);
                      final dateOnly = DateTime(date.year, date.month, date.day);

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _onDateTap(dateOnly),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isToday && !isSelected
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('EEE').format(date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary
                                        : onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  date.day.toString(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary
                                        : onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.calendar_today, color: onSurface),
            onPressed: _showDatePicker,
            tooltip: 'Select date',
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _jumpToToday,
            child: Text('Today', style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

