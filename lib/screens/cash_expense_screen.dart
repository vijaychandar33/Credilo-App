import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cash_expense.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

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
  List<String> _existingExpenseIds = []; // Track existing expense IDs
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
            _expenses.add(row);
            if (expense.id != null) {
              _existingExpenseIds.add(expense.id!);
            }
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
      });
    }
  }

  void _addNewRow() {
    setState(() {
      _expenses.add(CashExpenseRow());
    });
  }

  void _removeRow(int index) {
    setState(() {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expenses: $e')),
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

    return Scaffold(
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
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
                      '₹${_getTotal().toStringAsFixed(2)}',
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
        ],
      ),
    );
  }

  Widget _buildExpenseRow(int index) {
    final expense = _expenses[index];
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
                    decoration: const InputDecoration(
                      labelText: 'Item / Description',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
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
                        expense.amount = value.isEmpty
                            ? null
                            : double.tryParse(value);
                      });
                    },
                    autofocus: index == _expenses.length - 1 && expense.amount == null,
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

  CashExpenseRow();

  void dispose() {
    itemController.dispose();
    amountController.dispose();
    noteController.dispose();
  }
}

