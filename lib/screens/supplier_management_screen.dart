import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_range_utils.dart';
import '../utils/error_message_helper.dart';
import 'supplier_detail_screen.dart';
import 'supplier_edit_screen.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key});

  @override
  State<SupplierManagementScreen> createState() => _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<Supplier> _suppliers = [];
  Map<String, double> _supplierTotals = {}; // supplier name -> total unpaid
  List<Branch> _availableBranches = [];
  Set<String> _selectedBranchIds = {};
  DateRangeOption _selectedRangeOption = DateRangeOption.allTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  final Set<CreditExpenseStatus> _selectedStatuses = {};
  double _totalFilteredAmount = 0.0;
  final DateFormat _dateFormat = DateFormat('d MMM yyyy');
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeFilters();
    _loadSuppliers();
  }

  void _initializeFilters() {
    final ownerBranches = _authService.ownerBranches;
    if (ownerBranches.isNotEmpty) {
      _availableBranches = List<Branch>.from(ownerBranches);
    } else if (_authService.userBranches.isNotEmpty) {
      _availableBranches = List<Branch>.from(_authService.userBranches);
    } else if (_authService.currentBranch != null) {
      _availableBranches = [_authService.currentBranch!];
    }

    if (_availableBranches.isEmpty && _authService.currentBranch != null) {
      _availableBranches = [_authService.currentBranch!];
    }

    if (_selectedBranchIds.isEmpty && _availableBranches.isNotEmpty) {
      _selectedBranchIds = _availableBranches.map((b) => b.id).toSet();
    }
  }

  List<String> _getActiveBranchIds() {
    if (_selectedBranchIds.isNotEmpty) {
      return _selectedBranchIds.toList();
    }
    if (_availableBranches.isNotEmpty) {
      return _availableBranches.map((b) => b.id).toList();
    }
    final branch = _authService.currentBranch;
    if (branch != null) {
      return [branch.id];
    }
    return [];
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch ?? (_availableBranches.isNotEmpty ? _availableBranches.first : null);
      if (branch == null) {
        setState(() {
          _suppliers = [];
          _supplierTotals = {};
          _totalFilteredAmount = 0.0;
        });
        return;
      }

      final suppliers = await _dbService.getSuppliers(branch.businessId);
      final activeBranchIds = _getActiveBranchIds();
      final selectedStatuses = _selectedStatuses.isEmpty
          ? [CreditExpenseStatus.unpaid]
          : _selectedStatuses.toList();
      
      // Get date range
      final dateRange = await resolveDateRange(
        _selectedRangeOption,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
      );

      // Calculate total unpaid for each supplier
      Map<String, double> totals = {};
      double aggregate = 0.0;
      for (var supplier in suppliers) {
        final expenses = await _dbService.getCreditExpensesBySupplier(
          supplier.name,
          branch.businessId,
          branchIds: activeBranchIds,
          startDate: dateRange?.startDate,
          endDate: dateRange?.endDate,
          statuses: selectedStatuses,
        );
        final filteredTotal = expenses.fold(0.0, (sum, e) => sum + e.amount);
        totals[supplier.name] = filteredTotal;
        aggregate += filteredTotal;
      }
      
      List<Supplier> filteredSuppliers = suppliers;
      if (_selectedStatuses.length == 1 &&
          _selectedStatuses.contains(CreditExpenseStatus.unpaid)) {
        filteredSuppliers = suppliers
            .where((supplier) => (totals[supplier.name] ?? 0) > 0)
            .toList();
      }

      setState(() {
        _suppliers = filteredSuppliers;
        _supplierTotals = totals;
        _totalFilteredAmount = aggregate;
      });
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load suppliers. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addSupplier() async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (context) => _AddSupplierDialog(),
    );

    if (result != null) {
      try {
        await _dbService.saveSupplier(result);
        _loadSuppliers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Supplier added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to add supplier. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
          );
        }
      }
    }
  }

  Future<void> _showBranchSelectionSheet() async {
    if (_availableBranches.length <= 1) return;

    final currentSelection = _selectedBranchIds.isNotEmpty
        ? Set<String>.from(_selectedBranchIds)
        : _availableBranches.map((b) => b.id).toSet();

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        Set<String> tempSelection = Set<String>.from(currentSelection);

        bool isAllSelected() => tempSelection.length == _availableBranches.length;

        void toggleAll(bool value) {
          tempSelection = value
              ? _availableBranches.map((b) => b.id).toSet()
              : <String>{};
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Branches',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                toggleAll(true);
                              });
                            },
                            child: const Text('Select All'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: [
                            CheckboxListTile(
                              title: const Text('All Branches'),
                              value: isAllSelected(),
                              onChanged: (value) {
                                setModalState(() {
                                  toggleAll(value ?? false);
                                });
                              },
                            ),
                            const Divider(),
                            ..._availableBranches.map(
                              (branch) => CheckboxListTile(
                                title: Text(branch.name),
                                subtitle: branch.location.isNotEmpty ? Text(branch.location) : null,
                                value: tempSelection.contains(branch.id),
                                onChanged: (value) {
                                  setModalState(() {
                                    if (value == true) {
                                      tempSelection.add(branch.id);
                                    } else {
                                      tempSelection.remove(branch.id);
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  toggleAll(true);
                                });
                              },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (tempSelection.isEmpty) {
                                  toggleAll(true);
                                }
                                Navigator.pop(context, tempSelection);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedBranchIds = result;
      });
      _loadSuppliers();
    }
  }

  Future<void> _showCustomDatePicker() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => _SupplierDatePickerDialog(
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
        _loadSuppliers();
      }
    }
  }

  void _toggleStatusFilter(CreditExpenseStatus status) {
    setState(() {
      if (_selectedStatuses.contains(status)) {
        _selectedStatuses.remove(status);
      } else {
        _selectedStatuses.clear();
        _selectedStatuses.add(status);
      }
    });
    _loadSuppliers();
  }

  String _branchFilterLabel() {
    if (_availableBranches.isEmpty) return 'No branches';
    if (_availableBranches.length == 1) return _availableBranches.first.name;
    if (_selectedBranchIds.isEmpty || _selectedBranchIds.length == _availableBranches.length) {
      return 'All Branches';
    }
    if (_selectedBranchIds.length == 1) {
      final branch = _availableBranches.firstWhere(
        (b) => b.id == _selectedBranchIds.first,
        orElse: () => _availableBranches.first,
      );
      return branch.name;
    }
    return '${_selectedBranchIds.length} selected';
  }

  Widget _buildBranchSelectorField() {
    final canEdit = _availableBranches.length > 1;
    return GestureDetector(
      onTap: canEdit ? _showBranchSelectionSheet : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Branches',
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: canEdit ? const Icon(Icons.arrow_drop_down) : null,
          enabled: canEdit,
        ),
        child: Text(
          _branchFilterLabel(),
          style: TextStyle(
            color: canEdit ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
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

  Widget _buildDateRangeSelector() {
    return DropdownButtonFormField<DateRangeOption>(
      initialValue: _selectedRangeOption,
      decoration: const InputDecoration(
        labelText: 'Date Range',
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
          });
          _loadSuppliers();
        }
      },
    );
  }

  Widget _buildFiltersSection() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 2, child: _buildBranchSelectorField()),
              const SizedBox(width: 12),
              Expanded(child: _buildDateRangeSelector()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _selectedStatuses.contains(CreditExpenseStatus.unpaid),
                onChanged: (_) => _toggleStatusFilter(CreditExpenseStatus.unpaid),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Show only suppliers with pending',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierList() {
    if (_suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No suppliers yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a supplier to get started',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _suppliers.length,
      itemBuilder: (context, index) {
        final supplier = _suppliers[index];
        final totalRemaining = _supplierTotals[supplier.name] ?? 0.0;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SupplierDetailScreen(supplier: supplier),
                ),
              ).then((_) => _loadSuppliers()); // Reload to refresh totals
            },
            onLongPress: !_authService.isReadOnly() ? () {
              // Long press to edit (only if not read-only)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SupplierEditScreen(supplier: supplier),
                ),
              ).then((result) {
                if (result == true) {
                  _loadSuppliers(); // Reload if edited or deleted
                }
              });
            } : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          supplier.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(totalRemaining),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: totalRemaining > 0 ? AppColors.warning : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pending Amount',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  if (supplier.contact != null && supplier.contact!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          supplier.contact!,
                          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                  if (supplier.address != null && supplier.address!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            supplier.address!,
                            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _totalLabel() => 'Total Pending';

  Widget _buildTotalFooter() {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          border: Border(
            top: BorderSide(color: theme.dividerColor),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _totalLabel(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              CurrencyFormatter.format(_totalFilteredAmount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _totalFilteredAmount > 0 ? AppColors.warning : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          if (!_authService.isReadOnly())
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Supplier',
              onPressed: _addSupplier,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFiltersSection(),
                Expanded(child: _buildSupplierList()),
                _buildTotalFooter(),
              ],
            ),
    );
  }
}

class _AddSupplierDialog extends StatefulWidget {
  @override
  State<_AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<_AddSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _authService = AuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Supplier'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter supplier name';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact (optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final branch = _authService.currentBranch;
              if (branch == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No branch selected')),
                );
                return;
              }
              final supplier = Supplier(
                name: _nameController.text.trim(),
                contact: _contactController.text.trim().isEmpty
                    ? null
                    : _contactController.text.trim(),
                address: _addressController.text.trim().isEmpty
                    ? null
                    : _addressController.text.trim(),
                businessId: branch.businessId,
              );
              Navigator.pop(context, supplier);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _SupplierDatePickerDialog extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;

  const _SupplierDatePickerDialog({
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  State<_SupplierDatePickerDialog> createState() => _SupplierDatePickerDialogState();
}

class _SupplierDatePickerDialogState extends State<_SupplierDatePickerDialog> {
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

