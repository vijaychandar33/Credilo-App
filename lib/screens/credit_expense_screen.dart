import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';
import 'supplier_management_screen.dart';

class CreditExpenseScreen extends StatefulWidget {
  final DateTime selectedDate;

  const CreditExpenseScreen({super.key, required this.selectedDate});

  @override
  State<CreditExpenseScreen> createState() => _CreditExpenseScreenState();
}

class _CreditExpenseScreenState extends State<CreditExpenseScreen> {
  final List<CreditExpenseRow> _expenses = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  bool _showValidationErrors = false;
  final List<String> _existingExpenseIds = [];
  List<Supplier> _suppliers = [];
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
        await _loadSuppliers();
        _addNewRow();
        return;
      }

      await _loadSuppliers();

      final expenses = await _dbService.getCreditExpenses(widget.selectedDate, branch.id);
      
      if (expenses.isNotEmpty) {
        setState(() {
          _expenses.clear();
          _existingExpenseIds.clear();
          for (var expense in expenses) {
            final row = CreditExpenseRow();
            row.supplier = expense.supplier;
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
      debugPrint('Error loading credit expenses: $e');
      await _loadSuppliers();
      _addNewRow();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final branch = _authService.currentBranch;
      if (branch == null) {
        setState(() {
          _suppliers = [Supplier(name: 'Others', businessId: '')];
        });
        return;
      }

      final suppliers = await _dbService.getSuppliers(branch.businessId);
      // Only suppliers that supply to this branch (or to all branches)
      final forBranch = suppliers
          .where((s) => s.suppliesToBranch(branch.id))
          .toList();
      setState(() {
        // Remove duplicates by name (case-insensitive)
        final uniqueSuppliers = <String, Supplier>{};
        for (var supplier in forBranch) {
          final key = supplier.name.toLowerCase();
          if (!uniqueSuppliers.containsKey(key)) {
            uniqueSuppliers[key] = supplier;
          }
        }
        _suppliers = uniqueSuppliers.values.toList();
        
        // Ensure "Others" exists and is first
        if (!_suppliers.any((s) => s.name.toLowerCase() == 'others')) {
          _suppliers.insert(0, Supplier(name: 'Others', businessId: branch.businessId));
        } else {
          // Move "Others" to first position
          final others = _suppliers.firstWhere((s) => s.name.toLowerCase() == 'others');
          _suppliers.remove(others);
          _suppliers.insert(0, others);
        }
      });
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
      // Add default "Others" supplier
      final branch = _authService.currentBranch;
      setState(() {
        _suppliers = [Supplier(name: 'Others', businessId: branch?.businessId ?? '')];
      });
    }
  }

  void _addNewRow() {
    setState(() {
      _expenses.add(CreditExpenseRow());
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
        await _dbService.deleteCreditExpense(expense.id!);
        _existingExpenseIds.remove(expense.id!);
      } catch (e) {
        debugPrint('Error deleting expense from database: $e');
      }
    }
    
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

    bool hasValidationErrors = false;
    for (var expenseRow in _expenses) {
      if (expenseRow.amount != null && expenseRow.amount! > 0) {
        final missingSupplier = expenseRow.supplier == null || expenseRow.supplier!.isEmpty;
        final missingCategory = expenseRow.category == null;
        if (missingSupplier || missingCategory) {
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
          await _dbService.deleteCreditExpense(expenseId);
        } catch (e) {
          debugPrint('Error deleting existing expense: $e');
        }
      }

      // Save all current expenses
      for (var expenseRow in _expenses) {
        if (expenseRow.amount != null && expenseRow.amount! > 0) {
          if (expenseRow.supplier == null || expenseRow.supplier!.isEmpty) {
            continue; // Skip if supplier is not selected
          }
          if (expenseRow.category == null) {
            continue; // Skip if category is not selected
          }

          final supplierMatches = _suppliers
              .where((s) => s.name == expenseRow.supplier)
              .map((s) => s.id)
              .whereType<String>()
              .toList();
          final supplierId = supplierMatches.isEmpty ? null : supplierMatches.first;
          final expense = CreditExpense(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            supplier: expenseRow.supplier!,
            supplierId: supplierId,
            category: expenseRow.category!,
            amount: expenseRow.amount!,
            note: expenseRow.noteController.text.trim().isEmpty
                ? null
                : expenseRow.noteController.text.trim(),
            status: CreditExpenseStatus.unpaid, // Default to unpaid
          );

          await _dbService.saveCreditExpense(expense);
        }
      }

      // Reload data to get the new IDs
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credit expenses saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save credit expenses. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
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

  Future<void> _openSupplierManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SupplierManagementScreen()),
    );
    // Reload suppliers after returning
    await _loadSuppliers();
    setState(() {}); // Refresh UI to show updated suppliers
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Credit Expense - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Credit Expense - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.business),
            onPressed: _openSupplierManagement,
            tooltip: 'Manage Suppliers',
          ),
        ],
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
                      label: const Text('Add Credit Expense'),
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
                        'Total Credit Expenses:',
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
    );
  }

  /// Unique supplier names for selection (from _suppliers, plus orphan if any).
  List<String> _uniqueSupplierNames([String? orphanIfNotInList]) {
    final seen = <String>{};
    final names = <String>[];
    for (var s in _suppliers) {
      if (seen.add(s.name)) names.add(s.name);
    }
    if (orphanIfNotInList != null &&
        orphanIfNotInList.isNotEmpty &&
        !seen.contains(orphanIfNotInList)) {
      names.add(orphanIfNotInList);
    }
    return names;
  }

  Future<void> _openSupplierPicker(int expenseIndex) async {
    final expense = _expenses[expenseIndex];
    final names = _uniqueSupplierNames(expense.supplier);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SupplierPickerSheet(
        supplierNames: names,
        initialSelected: expense.supplier,
        searchHint: 'Search suppliers',
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        expense.supplier = selected;
      });
    }
  }

  Widget _buildExpenseRow(int index) {
    final expense = _expenses[index];
    final requiresFields = expense.amount != null && expense.amount! > 0;
    final showSupplierError = _showValidationErrors &&
        requiresFields &&
        (expense.supplier == null || expense.supplier!.isEmpty);
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
                  child: InkWell(
                    onTap: () => _openSupplierPicker(index),
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Supplier',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: showSupplierError ? 'Select supplier' : null,
                        suffixIcon: const Icon(Icons.search, size: 22),
                      ),
                      child: Text(
                        expense.supplier != null && expense.supplier!.isNotEmpty
                            ? expense.supplier!
                            : 'Select supplier',
                        style: TextStyle(
                          color: expense.supplier != null && expense.supplier!.isNotEmpty
                              ? null
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
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

  @override
  void dispose() {
    for (var expense in _expenses) {
      expense.dispose();
    }
    super.dispose();
  }
}

class _SupplierPickerSheet extends StatefulWidget {
  final List<String> supplierNames;
  final String? initialSelected;
  final String searchHint;

  const _SupplierPickerSheet({
    required this.supplierNames,
    this.initialSelected,
    this.searchHint = 'Search suppliers',
  });

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.supplierNames;
    return widget.supplierNames
        .where((name) => name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Select supplier',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (value) => setState(() => _query = value),
                autofocus: true,
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No suppliers match',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final name = filtered[i];
                        final isSelected = name == widget.initialSelected;
                        return ListTile(
                          title: Text(name),
                          trailing: isSelected
                              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                              : null,
                          onTap: () => Navigator.pop(context, name),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class CreditExpenseRow {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  String? supplier;
  String? category;
  double? amount;
  String? id; // Track if this row is saved in database

  CreditExpenseRow();

  void dispose() {
    amountController.dispose();
    noteController.dispose();
  }
}

