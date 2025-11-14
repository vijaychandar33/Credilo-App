import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/due.dart';

enum DateRangeOption {
  today,
  yesterday,
  last7Days,
  last2Weeks,
  lastMonth,
  custom,
}

class _DateRange {
  final DateTime startDate;
  final DateTime endDate;

  _DateRange({required this.startDate, required this.endDate});
}

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  DateRangeOption _selectedRangeOption = DateRangeOption.today;
  Branch? _selectedBranch;
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  Map<String, dynamic>? _overviewData;
  List<Due>? _duesData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadOverviewData();
      await _loadDuesData();
    } catch (e) {
      // Error loading dashboard data
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  _DateRange _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (_selectedRangeOption) {
      case DateRangeOption.today:
        return _DateRange(startDate: today, endDate: today);
      case DateRangeOption.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return _DateRange(startDate: yesterday, endDate: yesterday);
      case DateRangeOption.last7Days:
        return _DateRange(
          startDate: today.subtract(const Duration(days: 6)),
          endDate: today,
        );
      case DateRangeOption.last2Weeks:
        return _DateRange(
          startDate: today.subtract(const Duration(days: 13)),
          endDate: today,
        );
      case DateRangeOption.lastMonth:
        return _DateRange(
          startDate: today.subtract(const Duration(days: 29)),
          endDate: today,
        );
      case DateRangeOption.custom:
        if (_selectedStartDate != null && _selectedEndDate != null) {
          return _DateRange(
            startDate: _selectedStartDate!,
            endDate: _selectedEndDate!,
          );
        }
        return _DateRange(startDate: today, endDate: today);
    }
  }

  Future<void> _loadOverviewData() async {
    try {
      // Only show branches where user is an owner
      final ownerBranches = _authService.ownerBranches;
      final branches = _selectedBranch != null 
          ? [_selectedBranch!]
          : ownerBranches;

      if (branches.isEmpty) {
        setState(() {
          _overviewData = {
            'totalSales': 0.0,
            'totalCashSales': 0.0,
            'totalExpenses': 0.0,
            'totalCreditExpenses': 0.0,
            'totalCardOnlineSales': 0.0,
            'totalQrPayments': 0.0,
            'totalDues': 0.0,
            'totalReceivables': 0.0,
            'totalPayables': 0.0,
            'totalClosingCash': 0.0,
          };
        });
        return;
      }

      final dateRange = _getDateRange();
      double totalExpenses = 0.0;
      double totalCreditExpenses = 0.0;
      double totalCardSales = 0.0;
      double totalOnlineSales = 0.0;
      double totalQrPayments = 0.0;
      double totalReceivables = 0.0; // Only receivables for total sales
      double totalPayables = 0.0;
      double totalClosingCash = 0.0;
      double totalCashSales = 0.0;

      for (var branch in branches) {
        // Aggregate data for the date range
        DateTime currentDate = dateRange.startDate;
        while (currentDate.isBefore(dateRange.endDate) || 
               currentDate.isAtSameMomentAs(dateRange.endDate)) {
          final expenses = await _dbService.getCashExpenses(currentDate, branch.id);
          final branchExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
          totalExpenses += branchExpenses;

          final creditExpenses = await _dbService.getCreditExpenses(currentDate, branch.id);
          final branchCreditExpenses = creditExpenses.fold(0.0, (sum, e) => sum + e.amount);
          totalCreditExpenses += branchCreditExpenses;

          final cardSales = await _dbService.getCardSales(currentDate, branch.id);
          final branchCardSales = cardSales.fold(0.0, (sum, s) => sum + s.amount);
          totalCardSales += branchCardSales;

          final onlineSales = await _dbService.getOnlineSales(currentDate, branch.id);
          final branchOnlineSales = onlineSales.fold(0.0, (sum, s) => sum + s.net);
          totalOnlineSales += branchOnlineSales;

          final qrPayments = await _dbService.getQrPayments(currentDate, branch.id);
          totalQrPayments += qrPayments.fold(0.0, (sum, p) => sum + p.amount);

          final dues = await _dbService.getDues(currentDate, branch.id);
          // Calculate receivables and payables separately
          totalReceivables += dues
              .where((d) => d.type == DueType.receivable)
              .fold(0.0, (sum, d) => sum + d.amount);
          totalPayables += dues
              .where((d) => d.type == DueType.payable)
              .fold(0.0, (sum, d) => sum + d.amount);

          // Calculate cash sales for this branch: (Cash in Hand - Opening Balance) + Total Cash Expenses
          final cashCounts = await _dbService.getCashCounts(currentDate, branch.id);
          final countedCash = cashCounts.fold(0.0, (sum, count) => sum + count.total);
          
          // Get previous day's closing for opening balance
          final previousDate = currentDate.subtract(const Duration(days: 1));
          final previousClosing = await _dbService.getCashClosing(previousDate, branch.id);
          final opening = previousClosing?.nextOpening ?? 0.0;
          
          // Calculate: (Cash in Hand - Opening Balance) + Total Cash Expenses
          final branchCashSales = (countedCash - opening) + branchExpenses;
          totalCashSales += branchCashSales;

          final cashClosing = await _dbService.getCashClosing(currentDate, branch.id);
          if (cashClosing != null) {
            totalClosingCash += cashClosing.nextOpening;
          }

          currentDate = currentDate.add(const Duration(days: 1));
        }
      }

      final totalCardOnline = totalCardSales + totalOnlineSales;
      // Total Sales = Cash Sales + Card/Online Sales + QR Payments + Receivables
      final totalSales = totalCashSales + totalCardOnline + totalQrPayments + totalReceivables;
      // Total Due Amounts = Receivables - Payables
      final totalDues = totalReceivables - totalPayables;
      
      setState(() {
        _overviewData = {
          'totalSales': totalSales,
          'totalCashSales': totalCashSales,
          'totalExpenses': totalExpenses,
          'totalCreditExpenses': totalCreditExpenses,
          'totalCardOnlineSales': totalCardOnline,
          'totalQrPayments': totalQrPayments,
          'totalDues': totalDues,
          'totalReceivables': totalReceivables,
          'totalPayables': totalPayables,
          'totalClosingCash': totalClosingCash,
        };
      });
    } catch (e) {
      // Error loading overview data
    }
  }

  Future<void> _loadDuesData() async {
    try {
      String? branchId = _selectedBranch?.id;
      final dateRange = _getDateRange();
      
      // If no branch selected, get dues from all owner branches
      if (branchId == null) {
        final branches = _authService.ownerBranches;
        List<Due> allDues = [];
        for (var branch in branches) {
          DateTime currentDate = dateRange.startDate;
          while (currentDate.isBefore(dateRange.endDate) || 
                 currentDate.isAtSameMomentAs(dateRange.endDate)) {
            final branchDues = await _dbService.getDues(currentDate, branch.id);
            allDues.addAll(branchDues);
            currentDate = currentDate.add(const Duration(days: 1));
          }
        }
        setState(() {
          _duesData = allDues;
        });
      } else {
        List<Due> allDues = [];
        DateTime currentDate = dateRange.startDate;
        while (currentDate.isBefore(dateRange.endDate) || 
               currentDate.isAtSameMomentAs(dateRange.endDate)) {
          final dues = await _dbService.getDues(currentDate, branchId);
          allDues.addAll(dues);
          currentDate = currentDate.add(const Duration(days: 1));
        }
        setState(() {
          _duesData = allDues;
        });
      }
    } catch (e) {
      // Error loading dues data
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    // Only show branches where user is an owner
    final branches = authService.ownerBranches;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Dues'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<Branch?>(
                    initialValue: _selectedBranch,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Branch',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<Branch?>(
                        value: null,
                        child: Text(
                          'All Branches',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...branches.map((branch) {
                        return DropdownMenuItem<Branch?>(
                          value: branch,
                          child: Text(
                            branch.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    selectedItemBuilder: (context) {
                      return [
                        const Text(
                          'All Branches',
                          overflow: TextOverflow.ellipsis,
                        ),
                        ...branches.map((branch) {
                          return Text(
                            branch.name,
                            overflow: TextOverflow.ellipsis,
                          );
                        }),
                      ];
                    },
                    onChanged: (branch) {
                      setState(() {
                        _selectedBranch = branch;
                      });
                      _loadDashboardData();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _buildDateRangeSelector(),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildDueSettlementsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _overviewData ?? {};
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    
    // Calculate totals
    final totalSalesAmount = (data['totalSales'] ?? 0.0) as double;
    final totalExpensesAmount = ((data['totalExpenses'] ?? 0.0) as double) + 
                                 ((data['totalCreditExpenses'] ?? 0.0) as double);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sales Section
          _buildSectionHeader('Sales'),
          const SizedBox(height: 8),
          _buildSummaryCard(
            'Total Cash Sales',
            format.format(data['totalCashSales'] ?? 0.0),
            Icons.money,
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Total Card + Online Sales',
            format.format(data['totalCardOnlineSales'] ?? 0.0),
            Icons.credit_card,
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'UPI Payments',
            format.format(data['totalQrPayments'] ?? 0.0),
            Icons.qr_code,
            Colors.teal,
          ),
          const SizedBox(height: 12),
          _buildTotalCard(
            'Total Sales',
            format.format(totalSalesAmount),
            Icons.trending_up,
            Colors.green,
          ),
          const SizedBox(height: 24),
          // Expenses Section
          _buildSectionHeader('Expenses'),
          const SizedBox(height: 8),
          _buildSummaryCard(
            'Total Cash Expenses',
            format.format(data['totalExpenses'] ?? 0.0),
            Icons.receipt_long,
            Colors.red,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Total Credit Expenses',
            format.format(data['totalCreditExpenses'] ?? 0.0),
            Icons.credit_card_outlined,
            Colors.amber,
          ),
          const SizedBox(height: 12),
          _buildTotalCard(
            'Total Expenses',
            format.format(totalExpensesAmount),
            Icons.account_balance,
            Colors.deepOrange,
          ),
          const SizedBox(height: 24),
          // Others Section
          _buildSectionHeader('Others'),
          const SizedBox(height: 8),
          _buildSummaryCard(
            'Total Due Amounts',
            format.format(data['totalDues'] ?? 0.0),
            Icons.pending_actions,
            Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Total Closing Cash',
            format.format(data['totalClosingCash'] ?? 0.0),
            Icons.account_balance_wallet,
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildDueSettlementsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final dues = _duesData ?? [];
    final receivables = dues.where((d) => d.type == DueType.receivable).toList();
    final payables = dues.where((d) => d.type == DueType.payable).toList();
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    String getStatusText(DueStatus status) {
      switch (status) {
        case DueStatus.open:
          return 'Open';
        case DueStatus.partiallyPaid:
          return 'Partially Paid';
        case DueStatus.paid:
          return 'Paid';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Receivables',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (receivables.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No receivables for selected date'),
                    )
                  else
                    ...receivables.map((due) => _buildDueRow(
                      due.party,
                      format.format(due.amount),
                      getStatusText(due.status),
                    )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payables',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (payables.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No payables for selected date'),
                    )
                  else
                    ...payables.map((due) => _buildDueRow(
                      due.party,
                      format.format(due.amount),
                      getStatusText(due.status),
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueRow(String party, String amount, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(party)),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'Open' ? Colors.orange.shade100 : Colors.green.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: status == 'Open' ? Colors.orange.shade700 : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    String getDisplayText() {
      switch (_selectedRangeOption) {
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
          if (_selectedStartDate != null && _selectedEndDate != null) {
            if (_selectedStartDate!.isAtSameMomentAs(_selectedEndDate!)) {
              return DateFormat('d MMM yyyy').format(_selectedStartDate!);
            }
            return '${DateFormat('d MMM').format(_selectedStartDate!)} - ${DateFormat('d MMM yyyy').format(_selectedEndDate!)}';
          }
          return 'Custom';
      }
    }

    return DropdownButtonFormField<DateRangeOption>(
      initialValue: _selectedRangeOption,
      decoration: const InputDecoration(
        labelText: 'Date Range',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isExpanded: true,
      items: [
        const DropdownMenuItem(
          value: DateRangeOption.today,
          child: Text('Today'),
        ),
        const DropdownMenuItem(
          value: DateRangeOption.yesterday,
          child: Text('Yesterday'),
        ),
        const DropdownMenuItem(
          value: DateRangeOption.last7Days,
          child: Text('Last 7 Days'),
        ),
        const DropdownMenuItem(
          value: DateRangeOption.last2Weeks,
          child: Text('Last 2 Weeks'),
        ),
        const DropdownMenuItem(
          value: DateRangeOption.lastMonth,
          child: Text('Last Month'),
        ),
        const DropdownMenuItem(
          value: DateRangeOption.custom,
          child: Text('Custom'),
        ),
      ],
      onChanged: (option) async {
        if (option == null) return;

        if (option == DateRangeOption.custom) {
          await _showCustomDatePicker();
        } else {
          setState(() {
            _selectedRangeOption = option;
          });
          _loadDashboardData();
        }
      },
      selectedItemBuilder: (context) {
        return [
          const Text('Today', overflow: TextOverflow.ellipsis),
          const Text('Yesterday', overflow: TextOverflow.ellipsis),
          const Text('Last 7 Days', overflow: TextOverflow.ellipsis),
          const Text('Last 2 Weeks', overflow: TextOverflow.ellipsis),
          const Text('Last Month', overflow: TextOverflow.ellipsis),
          Text(getDisplayText(), overflow: TextOverflow.ellipsis),
        ];
      },
    );
  }

  Future<void> _showCustomDatePicker() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => _CustomDatePickerDialog(
        initialStartDate: _selectedStartDate ?? DateTime.now(),
        initialEndDate: _selectedEndDate ?? DateTime.now(),
      ),
    );

    if (result != null) {
      final startDate = result['start'];
      final endDate = result['end'];

      if (startDate != null && endDate != null) {
        setState(() {
          _selectedStartDate = DateTime(startDate.year, startDate.month, startDate.day);
          _selectedEndDate = DateTime(endDate.year, endDate.month, endDate.day);
          _selectedRangeOption = DateRangeOption.custom;
        });
        _loadDashboardData();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _CustomDatePickerDialog extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;

  const _CustomDatePickerDialog({
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  State<_CustomDatePickerDialog> createState() => _CustomDatePickerDialogState();
}

class _CustomDatePickerDialogState extends State<_CustomDatePickerDialog> {
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
        if (!_isRangeMode) {
          _endDate = picked;
        } else if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
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

  int _getDaysDifference() {
    return _endDate.difference(_startDate).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysDiff = _getDaysDifference();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
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
            // Toggle for Range Mode
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
                        if (!_isRangeMode) {
                          _endDate = _startDate;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Date Selection Cards
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
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
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
            // Action Buttons
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

  Widget _buildDateCard({
    required BuildContext context,
    required String label,
    required DateTime date,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isToday = _isSameDay(date, DateTime.now());
    final isYesterday = _isSameDay(date, DateTime.now().subtract(const Duration(days: 1)));

    String getDateLabel() {
      if (isToday) return 'Today';
      if (isYesterday) return 'Yesterday';
      return DateFormat('EEEE').format(date); // Day name
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onPrimaryContainer,
                size: 20,
              ),
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
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMM yyyy').format(date),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (isToday || isYesterday)
                    Text(
                      getDateLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

