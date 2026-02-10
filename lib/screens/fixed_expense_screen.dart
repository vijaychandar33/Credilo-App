import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/fixed_expense.dart';
import '../models/branch.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';
import '../utils/date_range_utils.dart';
import '../utils/app_colors.dart';
import '../widgets/date_selector.dart';

class FixedExpenseScreen extends StatefulWidget {
  final DateTime selectedDate;

  const FixedExpenseScreen({super.key, required this.selectedDate});

  @override
  State<FixedExpenseScreen> createState() => _FixedExpenseScreenState();
}

class _FixedExpenseScreenState extends State<FixedExpenseScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  
  List<FixedExpense> _expenses = [];
  bool _isLoading = false;
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();
  DateRangeOption _selectedRangeOption = DateRangeOption.allTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  final DateFormat _dateFormat = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) return;

      // Get date range based on selected option
      final dateRange = await resolveDateRange(
        _selectedRangeOption,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        branchId: branch.id,
      );
      
      // Load expenses
      final expenses = await _dbService.getFixedExpenses(
        branch.id,
        startDate: dateRange?.startDate,
        endDate: dateRange?.endDate,
      );

      setState(() {
        _expenses = expenses;
      });
    } catch (e) {
      debugPrint('Error loading fixed expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addExpense() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note/Comment is required')),
      );
      return;
    }

    final user = _authService.currentUser;
    final branch = _authService.currentBranch;

    if (user == null || branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User or branch not found')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final expense = FixedExpense(
        date: _selectedDate,
        userId: user.id,
        branchId: branch.id,
        category: 'other', // Default category since it's removed from UI
        amount: amount,
        note: _noteController.text.trim(),
      );

      await _dbService.saveFixedExpense(expense);

      // Clear form
      _amountController.clear();
      _noteController.clear();

      // Reload data
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fixed expense recorded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording expense: ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteExpense(FixedExpense expense) async {
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: 'Delete Expense',
      message: 'Are you sure you want to delete this fixed expense?',
    );

    if (!confirmed || expense.id == null) return;

    try {
      await _dbService.deleteFixedExpense(expense.id!);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    }
  }

  bool _canDelete() {
    return _authService.canDelete();
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    // Reload expenses for the selected date
    _loadData();
  }

  Future<void> _showCustomDatePicker() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => _FixedExpenseDatePickerDialog(
        initialStartDate: _customStartDate ?? DateTime.now(),
        initialEndDate: _customEndDate ?? DateTime.now(),
      ),
    );

    if (result != null) {
      final startDate = result['start'];
      final endDate = result['end'];

      if (startDate != null && endDate != null) {
        setState(() {
          _customStartDate = DateTime(startDate.year, startDate.month, startDate.day);
          _customEndDate = DateTime(endDate.year, endDate.month, endDate.day);
          _selectedRangeOption = DateRangeOption.custom;
        });
        _loadData();
      }
    }
  }

  String _dateRangeLabel(DateRangeOption option) {
    switch (option) {
      case DateRangeOption.allTime:
        return 'All Time';
      case DateRangeOption.today:
        return 'Today';
      case DateRangeOption.yesterday:
        return 'Yesterday';
      case DateRangeOption.last7Days:
        return 'Last 7 Days';
      case DateRangeOption.last2Weeks:
        return 'Last 2 Weeks';
      case DateRangeOption.lastMonth:
        return 'Last Month';
      case DateRangeOption.custom:
        if (_customStartDate != null && _customEndDate != null) {
          if (_customStartDate!.isAtSameMomentAs(_customEndDate!)) {
            return _dateFormat.format(_customStartDate!);
          }
          return '${DateFormat('d MMM').format(_customStartDate!)} - ${_dateFormat.format(_customEndDate!)}';
        }
        return 'Custom';
    }
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'rent':
        return 'Rent';
      case 'electricity':
        return 'Electricity';
      case 'other':
        return 'Other';
      default:
        return category;
    }
  }

  Widget _buildBranchDetailsCard(BuildContext context, AuthService authService) {
    final branch = authService.currentBranch;
    if (branch == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          branch.location,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: branch.status == BranchStatus.active
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.textTertiary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  branch.status.toString().split('.').last.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: branch.status == BranchStatus.active
                        ? AppColors.success
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return DropdownButtonFormField<DateRangeOption>(
      key: ValueKey(_selectedRangeOption),
      initialValue: _selectedRangeOption,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isExpanded: true,
      items: const [
        DropdownMenuItem(
          value: DateRangeOption.allTime,
          child: Text('All Time'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.today,
          child: Text('Today'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.yesterday,
          child: Text('Yesterday'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.last7Days,
          child: Text('Last 7 Days'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.last2Weeks,
          child: Text('Last 2 Weeks'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.lastMonth,
          child: Text('Last Month'),
        ),
        DropdownMenuItem(
          value: DateRangeOption.custom,
          child: Text('Custom'),
        ),
      ],
      selectedItemBuilder: (context) {
        return [
          const Text('All Time', overflow: TextOverflow.ellipsis),
          const Text('Today', overflow: TextOverflow.ellipsis),
          const Text('Yesterday', overflow: TextOverflow.ellipsis),
          const Text('Last 7 Days', overflow: TextOverflow.ellipsis),
          const Text('Last 2 Weeks', overflow: TextOverflow.ellipsis),
          const Text('Last Month', overflow: TextOverflow.ellipsis),
          Text(_dateRangeLabel(DateRangeOption.custom), overflow: TextOverflow.ellipsis),
        ];
      },
      onChanged: (value) async {
        if (value == null) return;
        if (value == DateRangeOption.custom) {
          await _showCustomDatePicker();
        } else {
          setState(() {
            _selectedRangeOption = value;
            _customStartDate = null;
            _customEndDate = null;
          });
          _loadData();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixed Expenditure'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  // Branch Details Card
                  if (_authService.currentBranch != null)
                    _buildBranchDetailsCard(context, _authService),
                  // Date Selector
                  DateSelector(
                    selectedDate: _selectedDate,
                    onDateSelected: _onDateSelected,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Add Expense Section
                          Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Add Fixed Expense',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _amountController,
                                    decoration: const InputDecoration(
                                      labelText: 'Amount',
                                      prefixText: '₹',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _noteController,
                                    decoration: const InputDecoration(
                                      labelText: 'Note / Comment',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: 2,
                                    textCapitalization: TextCapitalization.sentences,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _isSaving ? null : _addExpense,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: _isSaving
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Record Expense'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Expenses List Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Text(
                                  'Expense History',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 150,
                                  child: _buildDateRangeSelector(),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Expenses List
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.5,
                            ),
                            child: _expenses.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inbox_outlined,
                                          size: 64,
                                          color: Theme.of(context).colorScheme.outline,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No expenses found',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _expenses.length,
                                    itemBuilder: (context, index) {
                                      final expense = _expenses[index];
                                      
                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                            child: Icon(
                                              Icons.receipt_long,
                                              color: Theme.of(context).colorScheme.onErrorContainer,
                                            ),
                                          ),
                                          title: Text(
                                            _getCategoryDisplayName(expense.category),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateFormat('d MMM yyyy').format(expense.date),
                                              ),
                                              if (expense.note != null && expense.note!.isNotEmpty)
                                                Text(
                                                  expense.note!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context).colorScheme.outline,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                CurrencyFormatter.format(expense.amount),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context).colorScheme.error,
                                                ),
                                              ),
                                              if (_canDelete() && 
                                                  _isSameDate(expense.date, _selectedDate))
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline),
                                                  color: Colors.red,
                                                  onPressed: () => _deleteExpense(expense),
                                                  tooltip: 'Delete expense',
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}

class _FixedExpenseDatePickerDialog extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;

  const _FixedExpenseDatePickerDialog({
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  State<_FixedExpenseDatePickerDialog> createState() => _FixedExpenseDatePickerDialogState();
}

class _FixedExpenseDatePickerDialogState extends State<_FixedExpenseDatePickerDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isRangeMode = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (!_isRangeMode || _endDate.isBefore(_startDate)) {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Widget _buildDateCard({
    required BuildContext context,
    required String label,
    required DateTime date,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMM yyyy').format(date),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  int _getDaysDifference() => _endDate.difference(_startDate).inDays + 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysDiff = _getDaysDifference();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Date',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isRangeMode ? Icons.date_range : Icons.calendar_today,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRangeMode ? 'Date Range' : 'Single Date',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _isRangeMode,
                    onChanged: (value) {
                      setState(() {
                        _isRangeMode = value;
                        if (!value) {
                          _endDate = _startDate;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!_isRangeMode)
              _buildDateCard(
                context: context,
                label: 'Select Date',
                date: _startDate,
                onTap: _selectStartDate,
                icon: Icons.calendar_today,
              )
            else
              Column(
                children: [
                  _buildDateCard(
                    context: context,
                    label: 'From',
                    date: _startDate,
                    onTap: _selectStartDate,
                    icon: Icons.play_arrow,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '$daysDiff ${daysDiff == 1 ? 'day' : 'days'} selected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDateCard(
                    context: context,
                    label: 'To',
                    date: _endDate,
                    onTap: _selectEndDate,
                    icon: Icons.stop,
                  ),
                ],
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop({
                        'start': _startDate,
                        'end': _endDate,
                      });
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
