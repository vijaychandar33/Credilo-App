import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import 'package:intl/intl.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'supplier_edit_screen.dart';
import '../utils/error_message_helper.dart';
import '../utils/date_range_utils.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;
  final List<String>? selectedBranchIds;
  final DateRangeOption? dateRangeOption;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Set<CreditExpenseStatus>? selectedStatuses;

  const SupplierDetailScreen({
    super.key,
    required this.supplier,
    this.selectedBranchIds,
    this.dateRangeOption,
    this.customStartDate,
    this.customEndDate,
    this.selectedStatuses,
  });

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<CreditExpense> _expenses = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) return;

      // Apply filters from parent screen
      List<String>? branchIds = widget.selectedBranchIds;
      DateTime? startDate;
      DateTime? endDate;
      List<CreditExpenseStatus>? statuses;

      // Resolve date range if filter is provided
      if (widget.dateRangeOption != null) {
        final dateRange = await resolveDateRange(
          widget.dateRangeOption!,
          customStartDate: widget.customStartDate,
          customEndDate: widget.customEndDate,
          branchId: branch.id,
        );
        if (dateRange != null) {
          startDate = dateRange.startDate;
          endDate = dateRange.endDate;
        }
      }

      // Use selected statuses if provided
      if (widget.selectedStatuses != null && widget.selectedStatuses!.isNotEmpty) {
        statuses = widget.selectedStatuses!.toList();
      }

      final expenses = widget.supplier.id != null
          ? await _dbService.getCreditExpensesBySupplierId(
              widget.supplier.id!,
              branch.businessId,
              branchIds: branchIds,
              startDate: startDate,
              endDate: endDate,
              statuses: statuses,
            )
          : await _dbService.getCreditExpensesBySupplier(
              widget.supplier.name,
              branch.businessId,
              branchIds: branchIds,
              startDate: startDate,
              endDate: endDate,
              statuses: statuses,
            );
      setState(() {
        _expenses = expenses;
        _selectedIds.clear();
      });
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load expenses. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Persistent filter bar below app bar (same as Owner's Dashboard): always visible,
  /// shows "All branches" / "All time" / "All" when no filter applied.
  Widget _buildFilterSummarySection() {
    final chips = <Widget>[
      _buildFilterChip('Branches', _branchFilterLabel()),
      _buildFilterChip('Date', _dateRangeFilterLabel()),
      _buildFilterChip('Status', _statusFilterLabel()),
    ];

    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _branchFilterLabel() {
    final branches = _authService.ownerBranches.isNotEmpty
        ? _authService.ownerBranches
        : _authService.userBranches;
    if (branches.isEmpty) return 'No branches';
    final selected = widget.selectedBranchIds;
    if (selected == null || selected.isEmpty || selected.length == branches.length) {
      return 'All branches';
    }
    if (selected.length == 1) {
      final match = branches.where((e) => e.id == selected.first).toList();
      return match.isNotEmpty ? match.first.name : '1 branch';
    }
    return '${selected.length} branches';
  }

  String _dateRangeFilterLabel() {
    final opt = widget.dateRangeOption;
    if (opt == null || opt == DateRangeOption.allTime) return 'All time';
    final formatter = DateFormat('d MMM yyyy');
    switch (opt) {
      case DateRangeOption.today:
        return 'Today';
      case DateRangeOption.yesterday:
        return 'Yesterday';
      case DateRangeOption.last7Days:
        return 'Last 7 days';
      case DateRangeOption.last2Weeks:
        return 'Last 2 weeks';
      case DateRangeOption.lastMonth:
        return 'Last month';
      case DateRangeOption.custom:
        if (widget.customStartDate != null && widget.customEndDate != null) {
          final s = widget.customStartDate!;
          final e = widget.customEndDate!;
          if (s.year == e.year && s.month == e.month && s.day == e.day) {
            return formatter.format(s);
          }
          return '${formatter.format(s)} - ${formatter.format(e)}';
        }
        return 'Custom';
      case DateRangeOption.allTime:
        return 'All time';
    }
  }

  String _statusFilterLabel() {
    final s = widget.selectedStatuses;
    if (s == null || s.isEmpty) return 'All';
    if (s.length == 1) {
      return s.first == CreditExpenseStatus.paid ? 'Paid' : 'Unpaid';
    }
    return 'Paid, Unpaid';
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  double _getSelectedTotal() {
    return _expenses
        .where((e) => e.id != null && _selectedIds.contains(e.id!))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> _markAsPaid() async {
    if (_selectedIds.isEmpty) return;

    final unpaidIds = _expenses
        .where((e) => e.id != null &&
            _selectedIds.contains(e.id!) &&
            e.status == CreditExpenseStatus.unpaid)
        .map((e) => e.id!)
        .toList();

    if (unpaidIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unpaid expenses selected')),
      );
      return;
    }

    final payment = await _showPaymentMethodDialog();
    if (payment == null || !mounted) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      await _dbService.updateCreditExpensesStatus(
        unpaidIds,
        CreditExpenseStatus.paid,
        paymentMethod: payment.method.value,
        paymentNote: payment.note,
      );
      await _loadExpenses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${unpaidIds.length} expense(s) marked as paid')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update status. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  /// Returns (method, note) or null if cancelled. Note is required when method is others.
  Future<({CreditExpensePaymentMethod method, String? note})?> _showPaymentMethodDialog() async {
    return showDialog<({CreditExpensePaymentMethod method, String? note})>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PaymentMethodDialog(),
    );
  }

  Future<void> _showStatusChangeDialog(CreditExpense expense) async {
    if (expense.id == null) return;

    final newStatus = await showDialog<CreditExpenseStatus>(
      context: context,
      builder: (context) {
        CreditExpenseStatus selectedStatus = expense.status;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Change Status'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${DateFormat('d MMM yyyy').format(expense.date)}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount: ${CurrencyFormatter.format(expense.amount)}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select new status:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Paid'),
                  leading: Radio<CreditExpenseStatus>(
                    value: CreditExpenseStatus.paid,
                    // ignore: deprecated_member_use
                    groupValue: selectedStatus,
                    // ignore: deprecated_member_use
                    onChanged: null,
                    activeColor: AppColors.success,
                  ),
                  selected: selectedStatus == CreditExpenseStatus.paid,
                  onTap: () {
                    Navigator.pop(context, CreditExpenseStatus.paid);
                  },
                ),
                ListTile(
                  title: const Text('Unpaid'),
                  leading: Radio<CreditExpenseStatus>(
                    value: CreditExpenseStatus.unpaid,
                    // ignore: deprecated_member_use
                    groupValue: selectedStatus,
                    // ignore: deprecated_member_use
                    onChanged: null,
                    activeColor: AppColors.warning,
                  ),
                  selected: selectedStatus == CreditExpenseStatus.unpaid,
                  onTap: () {
                    Navigator.pop(context, CreditExpenseStatus.unpaid);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );

    if (newStatus != null && newStatus != expense.status) {
      if (newStatus == CreditExpenseStatus.paid) {
        final payment = await _showPaymentMethodDialog();
        if (payment == null || !mounted) return;
        setState(() {
          _isUpdating = true;
        });
        try {
          await _dbService.updateCreditExpenseStatus(
            expense.id!,
            CreditExpenseStatus.paid,
            paymentMethod: payment.method.value,
            paymentNote: payment.note,
          );
          await _loadExpenses();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Status changed to Paid')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Unable to update status. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isUpdating = false;
            });
          }
        }
      } else {
        setState(() {
          _isUpdating = true;
        });
        try {
          await _dbService.updateCreditExpenseStatus(expense.id!, CreditExpenseStatus.unpaid);
          await _loadExpenses();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Status changed to Unpaid')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Unable to update status. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isUpdating = false;
            });
          }
        }
      }
    }
  }

  Future<void> _editSupplier() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierEditScreen(supplier: widget.supplier),
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true); // Return to supplier list and refresh
    }
  }

  Future<void> _deleteSupplier() async {
    final branch = _authService.currentBranch;
    if (branch == null) return;

    final hasExpenses = widget.supplier.id != null
        ? await _dbService.hasCreditExpensesBySupplierId(widget.supplier.id!)
        : await _dbService.hasCreditExpenses(widget.supplier.name, branch.businessId);

    if (hasExpenses) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete supplier with existing credit expense records'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Are you sure you want to delete "${widget.supplier.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.supplier.id != null) {
      try {
        await _dbService.deleteSupplier(widget.supplier.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Supplier deleted successfully')),
          );
          Navigator.pop(context, true); // Return to supplier list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to delete supplier. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unpaidExpenses = _expenses.where((e) => e.status == CreditExpenseStatus.unpaid).toList();
    final totalUnpaid = unpaidExpenses.fold(0.0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          if (!_authService.isReadOnly()) ...[
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editSupplier,
            tooltip: 'Edit Supplier',
          ),
          if (_expenses.isEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSupplier,
              tooltip: 'Delete Supplier',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilterSummarySection(),
                // Summary Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Remaining:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(totalUnpaid),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedIds.isNotEmpty) ...[
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Selected (${_selectedIds.length}):',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(_getSelectedTotal()),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Expenses List
                Expanded(
                  child: _expenses.isEmpty
                      ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(
                              'No expenses found',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _expenses.length,
                          itemBuilder: (context, index) {
                            final expense = _expenses[index];
                            final isSelected = expense.id != null && _selectedIds.contains(expense.id!);
                            final isUnpaid = expense.status == CreditExpenseStatus.unpaid;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                                  : null,
                              child: InkWell(
                                onTap: () {
                                  if (expense.id != null) {
                                    _toggleSelection(expense.id!);
                                  }
                                },
                                onLongPress: () {
                                  if (expense.id != null) {
                                    _showStatusChangeDialog(expense);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: expense.id != null
                                            ? (value) => _toggleSelection(expense.id!)
                                            : null,
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  DateFormat('d MMM yyyy').format(expense.date),
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  CurrencyFormatter.format(expense.amount),
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            if (expense.branchName != null) ...[
                                              Row(
                                                children: [
                                                  Icon(Icons.store, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    expense.branchName!,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w500,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  if (expense.branchLocation != null) ...[
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '(${expense.branchLocation!})',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            Row(
                                              children: [
                                                Text(
                                                  expense.category,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isUnpaid
                                                        ? AppColors.warning.withValues(alpha: 0.2)
                                                        : AppColors.success.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isUnpaid ? 'Unpaid' : 'Paid',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: isUnpaid ? AppColors.warning : AppColors.success,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (expense.paymentDisplayText != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                expense.paymentDisplayText!,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                            if (expense.note != null && expense.note!.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                expense.note!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Action Button
                if (_selectedIds.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.overlay,
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isUpdating ? null : _markAsPaid,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isUpdating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Mark Selected as Paid', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  CreditExpensePaymentMethod _method = CreditExpensePaymentMethod.cash;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_method == CreditExpensePaymentMethod.others) {
      final note = _noteController.text.trim();
      if (note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a note for Others')),
        );
        return;
      }
      Navigator.pop(context, (method: _method, note: note));
    } else {
      Navigator.pop(context, (method: _method, note: null));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Payment method'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How was this amount paid?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            RadioGroup<CreditExpensePaymentMethod>(
              groupValue: _method,
              onChanged: (v) {
                if (v != null) setState(() => _method = v);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...CreditExpensePaymentMethod.values.map((m) {
                    final isOthers = m == CreditExpensePaymentMethod.others;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Text(m.displayLabel),
                          leading: Radio<CreditExpensePaymentMethod>(
                            value: m,
                            activeColor: Theme.of(context).colorScheme.primary,
                          ),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setState(() => _method = m),
                        ),
                        if (isOthers && _method == CreditExpensePaymentMethod.others) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 48, right: 8, bottom: 8),
                            child: TextField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                labelText: 'Note *',
                                hintText: 'Enter payment details',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              maxLines: 2,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

