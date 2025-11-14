import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'supplier_edit_screen.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

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

      final expenses = await _dbService.getCreditExpensesBySupplier(
        widget.supplier.name,
        branch.businessId,
      );
      setState(() {
        _expenses = expenses;
        _selectedIds.clear();
      });
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading expenses: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

    setState(() {
      _isUpdating = true;
    });

    try {
      await _dbService.updateCreditExpensesStatus(
        unpaidIds,
        CreditExpenseStatus.paid,
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
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
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
                  'Amount: ₹${expense.amount.toStringAsFixed(2)}',
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
                    activeColor: Colors.green,
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
                    activeColor: Colors.orange,
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
      setState(() {
        _isUpdating = true;
      });

      try {
        await _dbService.updateCreditExpenseStatus(expense.id!, newStatus);
        await _loadExpenses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Status changed to ${newStatus == CreditExpenseStatus.paid ? 'Paid' : 'Unpaid'}',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating status: $e')),
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

    final hasExpenses = await _dbService.hasCreditExpenses(
      widget.supplier.name,
      branch.businessId,
    );

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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            SnackBar(content: Text('Error deleting supplier: $e')),
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
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _isUpdating ? null : _markAsPaid,
              tooltip: 'Mark as Paid',
            ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editSupplier,
            tooltip: 'Edit Supplier',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteSupplier,
            tooltip: 'Delete Supplier',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
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
                            '₹${totalUnpaid.toStringAsFixed(2)}',
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
                              '₹${_getSelectedTotal().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
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
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No expenses found',
                                style: TextStyle(color: Colors.grey[400]),
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
                                                  '₹${expense.amount.toStringAsFixed(2)}',
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
                                                  Icon(Icons.store, size: 14, color: Colors.grey[600]),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    expense.branchName!,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w500,
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                  if (expense.branchLocation != null) ...[
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '(${expense.branchLocation!})',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
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
                                                    color: Colors.grey[600],
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
                                                        ? Colors.orange.withValues(alpha: 0.2)
                                                        : Colors.green.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isUnpaid ? 'Unpaid' : 'Paid',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: isUnpaid ? Colors.orange : Colors.green,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (expense.note != null && expense.note!.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                expense.note!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
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
              ],
            ),
    );
  }
}

