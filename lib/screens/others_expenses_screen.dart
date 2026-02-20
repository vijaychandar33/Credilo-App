import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/error_message_helper.dart';

/// Lists all credit expense entries saved under "Others" (temporary supplier).
/// Long-press an entry to move it to a specific supplier.
class OthersExpensesScreen extends StatefulWidget {
  const OthersExpensesScreen({super.key});

  @override
  State<OthersExpensesScreen> createState() => _OthersExpensesScreenState();
}

class _OthersExpensesScreenState extends State<OthersExpensesScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<CreditExpense> _expenses = [];
  List<Supplier> _suppliers = [];
  bool _isLoading = false;
  static const String _othersSupplierName = 'Others';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String? get _businessId {
    final branch = _authService.currentBranch;
    if (branch != null) return branch.businessId;
    if (_authService.ownerBranches.isNotEmpty) {
      return _authService.ownerBranches.first.businessId;
    }
    if (_authService.userBranches.isNotEmpty) {
      return _authService.userBranches.first.businessId;
    }
    return null;
  }

  Future<void> _loadData() async {
    final businessId = _businessId;
    if (businessId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final expenses = await _dbService.getCreditExpensesBySupplier(
        _othersSupplierName,
        businessId,
        branchIds: null,
        startDate: null,
        endDate: null,
        statuses: null,
      );
      final suppliers = await _dbService.getSuppliers(businessId);
      setState(() {
        _expenses = expenses;
        _suppliers = suppliers
            .where((s) => s.name.toLowerCase() != _othersSupplierName.toLowerCase())
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading Others expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to load entries. ${ErrorMessageHelper.getUserFriendlyError(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showMoveToSheet(CreditExpense expense) async {
    if (_suppliers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Add a supplier first, then you can move this entry to them.',
            ),
          ),
        );
      }
      return;
    }

    // Only show suppliers that supply to this entry's branch
    final suppliersForBranch = _suppliers
        .where((s) => s.suppliesToBranch(expense.branchId))
        .toList();

    if (suppliersForBranch.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No suppliers supply to this branch (${expense.branchName ?? expense.branchId}). Add a supplier for this branch first.',
            ),
          ),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<Supplier>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: _MoveToSupplierSheet(
            key: ValueKey<String>(expense.id ?? expense.branchId + expense.date.toIso8601String()),
            suppliers: suppliersForBranch,
            selectedExpense: expense,
          ),
        ),
      ),
    );

    if (selected == null || expense.id == null) return;

    try {
      await _dbService.updateCreditExpenseSupplier(
        expense.id!,
        selected.name,
        selected.id,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Entry moved to ${selected.name}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to move entry. ${ErrorMessageHelper.getUserFriendlyError(e)}',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold(0.0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Others'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 64,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No entries under Others',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Credit expenses saved with supplier "Others" will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(total),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_authService.isReadOnly())
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Long-press an entry to move it to a supplier.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _expenses.length,
                        itemBuilder: (context, index) {
                          final expense = _expenses[index];
                          final isUnpaid =
                              expense.status == CreditExpenseStatus.unpaid;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onLongPress: _authService.isReadOnly()
                                  ? null
                                  : () => _showMoveToSheet(expense),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                DateFormat('d MMM yyyy')
                                                    .format(expense.date),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                CurrencyFormatter.format(
                                                    expense.amount),
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (expense.branchName != null) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.store,
                                                    size: 14,
                                                    color:
                                                        AppColors.textTertiary),
                                                const SizedBox(width: 4),
                                                Text(
                                                  expense.branchName!,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        AppColors.textTertiary,
                                                  ),
                                                ),
                                                if (expense.branchLocation !=
                                                    null) ...[
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '(${expense.branchLocation!})',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors
                                                          .textTertiary,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Text(
                                                expense.category,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: AppColors.textTertiary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isUnpaid
                                                      ? AppColors.warning
                                                          .withValues(
                                                              alpha: 0.2)
                                                      : AppColors.success
                                                          .withValues(
                                                              alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  isUnpaid ? 'Unpaid' : 'Paid',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: isUnpaid
                                                        ? AppColors.warning
                                                        : AppColors.success,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (expense.note != null &&
                                              expense.note!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              expense.note!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textTertiary,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (!_authService.isReadOnly())
                                      Icon(
                                        Icons.drive_file_move,
                                        color: AppColors.textTertiary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MoveToSupplierSheet extends StatefulWidget {
  final List<Supplier> suppliers;
  final CreditExpense selectedExpense;

  const _MoveToSupplierSheet({
    super.key,
    required this.suppliers,
    required this.selectedExpense,
  });

  @override
  State<_MoveToSupplierSheet> createState() => _MoveToSupplierSheetState();
}

class _MoveToSupplierSheetState extends State<_MoveToSupplierSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Supplier> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.suppliers;
    return widget.suppliers
        .where((s) => s.name.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildSelectedEntryCard(BuildContext context) {
    final expense = widget.selectedExpense;
    final isUnpaid = expense.status == CreditExpenseStatus.unpaid;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected entry',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
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
            if (expense.branchName != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.store, size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    expense.branchName!,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  if (expense.branchLocation != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${expense.branchLocation!})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  expense.category,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            if (expense.note != null && expense.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                expense.note!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _buildSelectedEntryCard(context),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Move to supplier',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search suppliers',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchController.text.trim().isEmpty
                        ? 'No suppliers'
                        : 'No suppliers match',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                )
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final supplier = _filtered[index];
                    return ListTile(
                      leading: const Icon(Icons.business),
                      title: Text(supplier.name),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Move entry?'),
                            content: Text(
                              'Move this entry to ${supplier.name}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Move'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          Navigator.pop(context, supplier);
                        }
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
