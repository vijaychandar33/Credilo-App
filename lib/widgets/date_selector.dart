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
  late DateTime _currentWeekStart;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _currentWeekStart = _getWeekStart(_selectedDate);
    _pageController = PageController(initialPage: 1000);
  }

  @override
  void didUpdateWidget(DateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _selectedDate = widget.selectedDate;
      _currentWeekStart = _getWeekStart(_selectedDate);
    }
  }

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return date.subtract(Duration(days: weekday - 1));
  }

  List<DateTime> _getWeekDays(DateTime weekStart) {
    return List.generate(7, (index) => weekStart.add(Duration(days: index)));
  }

  void _onDateTap(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    widget.onDateSelected(date);
  }

  void _onPageChanged(int page) {
    final weekOffset = page - 1000;
    setState(() {
      _currentWeekStart = _getWeekStart(DateTime.now())
          .add(Duration(days: weekOffset * 7));
    });
  }

  void _jumpToToday() {
    final today = DateTime.now();
    final weekStart = _getWeekStart(today);
    final weeksDiff = _currentWeekStart.difference(weekStart).inDays ~/ 7;
    _pageController.animateToPage(
      1000 + weeksDiff,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _onDateTap(today);
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final weekStart = _getWeekStart(picked);
      final weeksDiff = weekStart.difference(_getWeekStart(DateTime.now())).inDays ~/ 7;
      _pageController.animateToPage(
        1000 + weeksDiff,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _onDateTap(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
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
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) {
                  final weekOffset = page - 1000;
                  final weekStart = _getWeekStart(DateTime.now())
                      .add(Duration(days: weekOffset * 7));
                  final days = _getWeekDays(weekStart);

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
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: Theme.of(context).colorScheme.primary,
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
                                      ? Colors.white
                                      : Theme.of(context)
                                          .colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                date.day.toString(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
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
            icon: const Icon(Icons.calendar_today),
            onPressed: _showDatePicker,
            tooltip: 'Select date',
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _jumpToToday,
            child: const Text('Today'),
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

