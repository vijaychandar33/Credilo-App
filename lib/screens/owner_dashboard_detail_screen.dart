import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_range_utils.dart';

enum DetailScreenType {
  cardSales,
  cashSales,
  onlineSales,
  qrPayments,
  cashExpenses,
  onlineExpenses,
  creditExpenses,
  fixedExpenses,
  totalSales,
  totalExpenses,
  totalProfit,
}

class OwnerDashboardDetailScreen extends StatefulWidget {
  final DetailScreenType type;
  final String title;
  final List<Branch> selectedBranches;
  final DateRangeSelection dateRange;

  const OwnerDashboardDetailScreen({
    super.key,
    required this.type,
    required this.title,
    required this.selectedBranches,
    required this.dateRange,
  });

  @override
  State<OwnerDashboardDetailScreen> createState() => _OwnerDashboardDetailScreenState();
}

class _OwnerDashboardDetailScreenState extends State<OwnerDashboardDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  bool _isLoading = true;
  // Full list of loaded items for the selected branches + date range
  List<Map<String, dynamic>> _allItems = [];
  // Filtered list based on provider / machine / platform filters
  List<Map<String, dynamic>> _items = [];
  double _total = 0.0;

  // Optional in-screen filters for specific sections
  String? _selectedProvider; // For UPI Payments
  String? _selectedMachine; // For Card Sales
  String? _selectedPlatform; // For Online Sales

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
      List<Map<String, dynamic>> items = [];
      double total = 0.0;

      for (var branch in widget.selectedBranches) {
        DateTime currentDate = widget.dateRange.startDate;
        while (currentDate.isBefore(widget.dateRange.endDate) || 
               currentDate.isAtSameMomentAs(widget.dateRange.endDate)) {
          
          switch (widget.type) {
            case DetailScreenType.cardSales:
              final cardSales = await _dbService.getCardSales(currentDate, branch.id);
              for (var sale in cardSales) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'machine': sale.machineName,
                  'tid': sale.tid,
                  'amount': sale.amount,
                  'notes': sale.notes,
                  'type': 'card_sale',
                  'lastEditedEmail': sale.lastEditedEmail,
                });
                total += sale.amount;
              }
              break;

            case DetailScreenType.onlineSales:
              final onlineSales = await _dbService.getOnlineSales(currentDate, branch.id);
              for (var sale in onlineSales) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'platform': sale.platform,
                  'gross': sale.gross,
                  'commission': sale.commission,
                  'net': sale.net,
                  'amount': sale.net,
                  'notes': sale.notes,
                  'type': 'online_sale',
                  'lastEditedEmail': sale.lastEditedEmail,
                });
                total += sale.net;
              }
              break;

            case DetailScreenType.qrPayments:
              final qrPayments = await _dbService.getQrPayments(currentDate, branch.id);
              // Use stored calculated total for the summary
              final calculatedTotal = await _dbService.getQrPaymentCalculatedTotal(currentDate, branch.id);
              
              for (var payment in qrPayments) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'provider': payment.provider,
                  'amount': payment.amount ?? (payment.amountBeforeMidnight ?? 0) + (payment.amountAfterMidnight ?? 0),
                  'notes': payment.notes,
                  'type': 'qr_payment',
                  'lastEditedEmail': payment.lastEditedEmail,
                });
              }
              // Use calculated total instead of summing individual payments
              total += calculatedTotal;
              break;

            case DetailScreenType.cashExpenses:
              final cashExpenses = await _dbService.getCashExpenses(currentDate, branch.id);
              for (var expense in cashExpenses) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'item': expense.item,
                  'category': expense.category,
                  'amount': expense.amount,
                  'note': expense.note,
                  'type': 'cash_expense',
                  'lastEditedEmail': expense.lastEditedEmail,
                });
                total += expense.amount;
              }
              break;

            case DetailScreenType.onlineExpenses:
              final onlineExpenses = await _dbService.getOnlineExpenses(currentDate, branch.id);
              for (var expense in onlineExpenses) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'item': expense.item,
                  'category': expense.category,
                  'amount': expense.amount,
                  'note': expense.note,
                  'type': 'online_expense',
                  'lastEditedEmail': expense.lastEditedEmail,
                });
                total += expense.amount;
              }
              break;

            case DetailScreenType.creditExpenses:
              final creditExpenses = await _dbService.getCreditExpenses(currentDate, branch.id);
              for (var expense in creditExpenses) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'supplier': expense.supplier,
                  'category': expense.category,
                  'amount': expense.amount,
                  'note': expense.note,
                  'status': expense.status.toString(),
                  'type': 'credit_expense',
                  'lastEditedEmail': expense.lastEditedEmail,
                });
                total += expense.amount;
              }
              break;

            case DetailScreenType.fixedExpenses:
              final fixedExpenses = await _dbService.getFixedExpenses(
                branch.id,
                startDate: currentDate,
                endDate: currentDate,
              );
              for (var expense in fixedExpenses) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'category': expense.category,
                  'amount': expense.amount,
                  'note': expense.note,
                  'type': 'fixed_expense',
                  'lastEditedEmail': expense.lastEditedEmail,
                });
                total += expense.amount;
              }
              break;

            case DetailScreenType.cashSales:
              // Cash sales are calculated from cash counts
              final cashCounts = await _dbService.getCashCounts(currentDate, branch.id);
              final countedCash = cashCounts.fold(0.0, (sum, count) => sum + count.total);
              
              final previousDate = currentDate.subtract(const Duration(days: 1));
              final previousClosing = await _dbService.getCashClosing(previousDate, branch.id);
              final opening = previousClosing?.nextOpening ?? 0.0;
              
              final expenses = await _dbService.getCashExpenses(currentDate, branch.id);
              final branchExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
              
              final cashSales = (countedCash - opening) + branchExpenses;
              
              // Get the cash closing record for this date to read last edited email (if any)
              final cashClosing = await _dbService.getCashClosing(currentDate, branch.id);
              
              if (cashSales > 0 || cashCounts.isNotEmpty) {
                items.add({
                  'date': currentDate,
                  'branch': branch.name,
                  'branchLocation': branch.location,
                  'opening': opening,
                  'countedCash': countedCash,
                  'expenses': branchExpenses,
                  'amount': cashSales,
                  'type': 'cash_sale',
                  'lastEditedEmail': cashClosing?.lastEditedEmail,
                });
                total += cashSales;
              }
              break;

            case DetailScreenType.totalSales:
            case DetailScreenType.totalExpenses:
            case DetailScreenType.totalProfit:
              // These are aggregated views - handled separately
              break;
          }

          currentDate = currentDate.add(const Duration(days: 1));
        }
      }

      setState(() {
        // Sort by date descending for stable ordering
        items.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
        _allItems = items;
        _total = total;
        // Apply any active filters to derive the visible list
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No data available',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterSummarySection(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _buildItemCard(item);
                          },
                        ),
                      ),
                      _buildTotalCard(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final date = item['date'] as DateTime;
    final branch = item['branch'] as String;
    final branchLocation = item['branchLocation'] as String?;
    final amount = (item['amount'] ?? item['net'] ?? 0.0) as double;
    final type = item['type'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branch,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (branchLocation != null && branchLocation.isNotEmpty)
                        Text(
                          branchLocation,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(amount),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('d MMM yyyy').format(date),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            ..._buildTypeSpecificFields(item, type),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTypeSpecificFields(Map<String, dynamic> item, String type) {
    List<Widget> fields = [];

    switch (type) {
      case 'card_sale':
        if (item['machine'] != null) {
          fields.add(_buildField('Machine', item['machine']));
        }
        if (item['tid'] != null) {
          fields.add(_buildField('TID', item['tid']));
        }
        if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
          fields.add(_buildField('Notes', item['notes']));
        }
        break;

      case 'online_sale':
        if (item['platform'] != null) {
          fields.add(_buildField('Platform', item['platform']));
        }
        if (item['gross'] != null) {
          fields.add(_buildField('Gross', CurrencyFormatter.format((item['gross'] as num).toDouble())));
        }
        if (item['commission'] != null) {
          fields.add(_buildField('Commission', CurrencyFormatter.format((item['commission'] as num).toDouble())));
        }
        if (item['net'] != null) {
          fields.add(_buildField('Net', CurrencyFormatter.format((item['net'] as num).toDouble())));
        }
        if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
          fields.add(_buildField('Notes', item['notes'].toString()));
        }
        break;

      case 'qr_payment':
        if (item['provider'] != null) {
          fields.add(_buildField('Provider', item['provider']));
        }
        if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
          fields.add(_buildField('Notes', item['notes']));
        }
        break;

      case 'cash_expense':
        if (item['item'] != null) {
          fields.add(_buildField('Item', item['item']));
        }
        if (item['category'] != null) {
          fields.add(_buildField('Category', item['category']));
        }
        if (item['note'] != null && item['note'].toString().isNotEmpty) {
          fields.add(_buildField('Note', item['note']));
        }
        break;

      case 'online_expense':
        if (item['item'] != null) {
          fields.add(_buildField('Item', item['item']));
        }
        if (item['category'] != null) {
          fields.add(_buildField('Category', item['category']));
        }
        if (item['note'] != null && item['note'].toString().isNotEmpty) {
          fields.add(_buildField('Note', item['note']));
        }
        break;

      case 'credit_expense':
        if (item['supplier'] != null) {
          fields.add(_buildField('Supplier', item['supplier']));
        }
        if (item['category'] != null) {
          fields.add(_buildField('Category', item['category']));
        }
        if (item['status'] != null) {
          final status = item['status'].toString().replaceAll('CreditExpenseStatus.', '');
          fields.add(_buildField('Status', status));
        }
        if (item['note'] != null && item['note'].toString().isNotEmpty) {
          fields.add(_buildField('Note', item['note']));
        }
        break;
      case 'fixed_expense':
        if (item['category'] != null) {
          String category = item['category'];
          // Format category display name
          String displayCategory = category;
          switch (category) {
            case 'rent':
              displayCategory = 'Rent';
              break;
            case 'electricity':
              displayCategory = 'Electricity';
              break;
            case 'other':
              displayCategory = 'Other';
              break;
          }
          fields.add(_buildField('Category', displayCategory));
        }
        if (item['note'] != null && item['note'].toString().isNotEmpty) {
          fields.add(_buildField('Note', item['note']));
        }
        break;

      case 'cash_sale':
        if (item['opening'] != null) {
          fields.add(_buildField('Opening Balance', CurrencyFormatter.format(item['opening'])));
        }
        if (item['countedCash'] != null) {
          fields.add(_buildField('Counted Cash', CurrencyFormatter.format(item['countedCash'])));
        }
        if (item['expenses'] != null) {
          fields.add(_buildField('Expenses', CurrencyFormatter.format(item['expenses'])));
        }
        break;
    }

    final lastEdited = item['lastEditedEmail']?.toString();
    if (lastEdited != null && lastEdited.trim().isNotEmpty) {
      fields.add(_buildField('Last Edited', lastEdited.trim()));
    }

    return fields;
  }

  /// Apply provider / machine / platform filters on top of the loaded items.
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allItems);

    switch (widget.type) {
      case DetailScreenType.qrPayments:
        if (_selectedProvider != null && _selectedProvider!.isNotEmpty) {
          filtered = filtered
              .where((item) => item['provider'] == _selectedProvider)
              .toList();
        }
        break;
      case DetailScreenType.cardSales:
        if (_selectedMachine != null && _selectedMachine!.isNotEmpty) {
          filtered = filtered
              .where((item) => item['machine'] == _selectedMachine)
              .toList();
        }
        break;
      case DetailScreenType.onlineSales:
        if (_selectedPlatform != null && _selectedPlatform!.isNotEmpty) {
          filtered = filtered
              .where((item) => item['platform'] == _selectedPlatform)
              .toList();
        }
        break;
      default:
        // Other detail types currently do not have additional in-screen filters.
        break;
    }

    setState(() {
      _items = filtered;
    });
  }

  /// Summary row shown below the app bar with active filters
  /// (branches, date range and any provider/machine/platform filters).
  Widget _buildFilterSummarySection() {
    final branchLabel = _branchLabel();
    final dateLabel = _dateRangeLabel();

    final List<Widget> chips = [
      _buildFilterChip('Branches', branchLabel),
      _buildFilterChip('Date', dateLabel),
    ];

    if (widget.type == DetailScreenType.qrPayments) {
      chips.add(_buildFilterChip(
        'Provider',
        _selectedProvider ?? 'All',
      ));
    } else if (widget.type == DetailScreenType.cardSales) {
      chips.add(_buildFilterChip(
        'Machine',
        _selectedMachine ?? 'All',
      ));
    } else if (widget.type == DetailScreenType.onlineSales) {
      chips.add(_buildFilterChip(
        'Platform',
        _selectedPlatform ?? 'All',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: chips,
          ),
        ),
        if (widget.type == DetailScreenType.qrPayments)
          _buildProviderFilterControls()
        else if (widget.type == DetailScreenType.cardSales)
          _buildMachineFilterControls()
        else if (widget.type == DetailScreenType.onlineSales)
          _buildPlatformFilterControls(),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _branchLabel() {
    if (widget.selectedBranches.isEmpty) return 'No branches';
    if (widget.selectedBranches.length == 1) {
      return widget.selectedBranches.first.name;
    }
    return '${widget.selectedBranches.length} branches';
  }

  String _dateRangeLabel() {
    final start = widget.dateRange.startDate;
    final end = widget.dateRange.endDate;
    final formatter = DateFormat('d MMM yyyy');
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return formatter.format(start);
    }
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  Widget _buildProviderFilterControls() {
    final providers = _allItems
        .map((item) => item['provider'])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    if (providers.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildDropdownFilterRow(
      label: 'Filter by provider',
      value: _selectedProvider,
      items: providers,
      onChanged: (value) {
        _selectedProvider = value;
        _applyFilters();
      },
    );
  }

  Widget _buildMachineFilterControls() {
    final machines = _allItems
        .map((item) => item['machine'])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    if (machines.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildDropdownFilterRow(
      label: 'Filter by machine',
      value: _selectedMachine,
      items: machines,
      onChanged: (value) {
        _selectedMachine = value;
        _applyFilters();
      },
    );
  }

  Widget _buildPlatformFilterControls() {
    final platforms = _allItems
        .map((item) => item['platform'])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    if (platforms.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildDropdownFilterRow(
      label: 'Filter by platform',
      value: _selectedPlatform,
      items: platforms,
      onChanged: (value) {
        _selectedPlatform = value;
        _applyFilters();
      },
    );
  }

  Widget _buildDropdownFilterRow({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All'),
                ),
                ...items.map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                onChanged(null);
              },
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              CurrencyFormatter.format(_total),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

