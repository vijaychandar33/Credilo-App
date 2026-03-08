import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cash_expense.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';
import '../utils/unsaved_changes_dialog.dart';

class CashExpenseScreen extends StatefulWidget {
  final DateTime selectedDate;

  const CashExpenseScreen({super.key, required this.selectedDate});

  @override
  State<CashExpenseScreen> createState() => _CashExpenseScreenState();
}

class _CashExpenseScreenState extends State<CashExpenseScreen> {
  final List<CashExpenseRow> _expenses = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  bool _showValidationErrors = false;
  bool _isDirty = false;
  final List<String> _existingExpenseIds = []; // Track existing expense IDs
  final List<String> _categories = [
    'Supplies',
    'Wages',
    'Utilities',
    'Misc',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) {
        setState(() {
          _isLoading = false;
        });
        _addNewRow();
        return;
      }

      final expenses = await _dbService.getCashExpenses(widget.selectedDate, branch.id);
      
      if (expenses.isNotEmpty) {
        setState(() {
          _isDirty = false;
          _expenses.clear();
          _existingExpenseIds.clear();
          for (var expense in expenses) {
            final row = CashExpenseRow();
            row.itemController.text = expense.item;
            row.amountController.text = expense.amount.toStringAsFixed(2);
            row.category = expense.category;
            row.amount = expense.amount;
            if (expense.note != null) {
              row.noteController.text = expense.note!;
            }
            if (expense.id != null) {
              row.id = expense.id!;
              _existingExpenseIds.add(expense.id!);
            }
            _expenses.add(row);
          }
        });
      } else {
        _addNewRow();
      }
    } catch (e) {
      debugPrint('Error loading cash expenses: $e');
      _addNewRow();
    } finally {
      setState(() {
        _isLoading = false;
        _isDirty = false;
      });
    }
  }

  void _addNewRow() {
    setState(() {
      _isDirty = true;
      _expenses.add(CashExpenseRow());
    });
  }

  Future<void> _removeRow(int index) async {
    final expense = _expenses[index];
    final hasValue = expense.amount != null && expense.amount! > 0;
    
    if (hasValue) {
      final confirmed = await showDeleteConfirmationDialog(
        context,
        title: 'Delete Expense',
        message: 'Are you sure you want to delete this expense?',
      );
      if (!confirmed) return;
    }
    
    // If this row was saved to database, delete it
    if (expense.id != null) {
      try {
        await _dbService.deleteCashExpense(expense.id!);
        _existingExpenseIds.remove(expense.id!);
      } catch (e) {
        debugPrint('Error deleting expense from database: $e');
      }
    }
    
    setState(() {
      _isDirty = true;
      _expenses.removeAt(index);
      if (_expenses.isEmpty) {
        _addNewRow();
      }
    });
  }

  double _getTotal() {
    return _expenses.fold(0.0, (sum, expense) => sum + (expense.amount ?? 0));
  }

  bool _canSave() {
    return _expenses.any((e) => e.amount != null && e.amount! > 0);
  }

  Future<void> _save() async {
    if (!_canSave()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one expense with amount')),
      );
      return;
    }

    bool hasValidationErrors = false;
    for (var expenseRow in _expenses) {
      if (expenseRow.amount != null && expenseRow.amount! > 0) {
        final missingItem = expenseRow.itemController.text.trim().isEmpty;
        final missingCategory = expenseRow.category == null;
        if (missingItem || missingCategory) {
          hasValidationErrors = true;
        }
      }
    }

    if (hasValidationErrors) {
      setState(() {
        _showValidationErrors = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all required fields to save')),
      );
      return;
    } else if (_showValidationErrors) {
      setState(() {
        _showValidationErrors = false;
      });
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
      // Delete existing expenses for this date to avoid duplicates
      for (var expenseId in _existingExpenseIds) {
        try {
          await _dbService.deleteCashExpense(expenseId);
        } catch (e) {
          debugPrint('Error deleting existing expense: $e');
        }
      }

      // Save all current expenses
      for (var expenseRow in _expenses) {
        if (expenseRow.amount != null && expenseRow.amount! > 0) {
          if (expenseRow.itemController.text.trim().isEmpty) {
            continue; // Skip if item name is empty
          }
          if (expenseRow.category == null) {
            continue; // Skip if category is not selected
          }

          final expense = CashExpense(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            item: expenseRow.itemController.text.trim(),
            category: expenseRow.category!,
            amount: expenseRow.amount!,
            note: expenseRow.noteController.text.trim().isEmpty
                ? null
                : expenseRow.noteController.text.trim(),
          );

          await _dbService.saveCashExpense(expense);
        }
      }

      // Reload data to get the new IDs
      await _loadData();

      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save expenses. $errorMessage')),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Cash Daily Expense - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await showUnsavedChangesDialog(context);
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Cash Daily Expense - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _expenses.length + 1,
              itemBuilder: (context, index) {
                if (index == _expenses.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addNewRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Expense Item'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }
                return _buildExpenseRow(index);
              },
            ),
          ),
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
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Expenses:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(_getTotal()),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_canSave() && !_isSaving) ? _save : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildExpenseRow(int index) {
    final expense = _expenses[index];
    final requiresFields = expense.amount != null && expense.amount! > 0;
    final showItemError = _showValidationErrors &&
        requiresFields &&
        expense.itemController.text.trim().isEmpty;
    final showCategoryError = _showValidationErrors && requiresFields && expense.category == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: expense.itemController,
                    decoration: InputDecoration(
                      labelText: 'Item / Description',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: showItemError ? 'Enter item' : null,
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _removeRow(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: expense.category,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: showCategoryError ? 'Select category' : null,
                    ),
                    items: _categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _isDirty = true;
                        expense.category = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: expense.amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '₹',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _isDirty = true;
                        expense.amount = value.isEmpty
                            ? null
                            : double.tryParse(value);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: expense.noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              onChanged: (_) => setState(() => _isDirty = true),
            ),
          ],
        ),
      ),
    );
  }
}

class CashExpenseRow {
  final TextEditingController itemController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  String? category;
  double? amount;
  String? id; // Track if this row is saved in database

  CashExpenseRow();

  void dispose() {
    itemController.dispose();
    amountController.dispose();
    noteController.dispose();
  }
}

