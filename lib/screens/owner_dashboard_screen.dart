import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/due.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_range_utils.dart';
import '../utils/closing_cycle_service.dart';
import 'owner_dashboard_detail_screen.dart';
import 'owner_dashboard_aggregated_detail_screen.dart';
import 'owner_dashboard_dues_detail_screen.dart';

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
  List<Branch> _availableBranches = [];
  Set<String> _selectedBranchIds = {};
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  Map<String, dynamic>? _overviewData;
  List<Due>? _duesData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _availableBranches = _authService.ownerBranches;
    if (_availableBranches.isNotEmpty) {
      _selectedBranchIds = _availableBranches.map((b) => b.id).toSet();
    }
    _loadDashboardData();
  }

  List<Branch> _getSelectedBranches() {
    if (_selectedBranchIds.isNotEmpty && _availableBranches.isNotEmpty) {
      return _availableBranches
          .where((b) => _selectedBranchIds.contains(b.id))
          .toList();
    }
    final ownerBranches = _authService.ownerBranches;
    if (ownerBranches.isNotEmpty) {
        _selectedBranchIds = ownerBranches.map((b) => b.id).toSet();
        return ownerBranches;
    }
    return [];
  }

  Future<void> _showBranchSelectionSheet() async {
    final branches = _authService.ownerBranches;
    if (branches.isEmpty) return;

    final currentSelection =
        _selectedBranchIds.isEmpty ? branches.map((b) => b.id).toSet() : _selectedBranchIds;

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        Set<String> tempSelection = Set<String>.from(currentSelection);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                bool allSelected = tempSelection.length == branches.length;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                tempSelection = branches.map((b) => b.id).toSet();
                              });
                            },
                            child: const Text('Select All'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            CheckboxListTile(
                              title: const Text('All Branches'),
                              value: allSelected,
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    tempSelection = branches.map((b) => b.id).toSet();
                                  } else {
                                    tempSelection.clear();
                                  }
                                });
                              },
                            ),
                            const Divider(),
                            ...branches.map(
                              (branch) => CheckboxListTile(
                                title: Text(branch.name),
                                subtitle:
                                    branch.location.isNotEmpty ? Text(branch.location) : null,
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempSelection = branches.map((b) => b.id).toSet();
                                });
                                Navigator.pop(context, tempSelection);
                              },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                if (tempSelection.isEmpty) {
                                  tempSelection = branches.map((b) => b.id).toSet();
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
        _availableBranches = branches;
        _selectedBranchIds = result;
      });
      _loadDashboardData();
    }
  }

  String _branchFilterLabel() {
    if (_availableBranches.isEmpty) return 'No branches';
    if (_selectedBranchIds.isEmpty ||
        _selectedBranchIds.length == _availableBranches.length) {
      return 'All Branches';
    }
    if (_selectedBranchIds.length == 1) {
      final branch = _availableBranches.firstWhere(
        (b) => _selectedBranchIds.contains(b.id),
        orElse: () => _availableBranches.first,
      );
      return branch.name;
    }
    return '${_selectedBranchIds.length} selected';
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

  Future<DateRangeSelection> _getDateRange() async {
    final branchId = _authService.currentBranch?.id;
    final result = await resolveDateRange(
      _selectedRangeOption,
      customStartDate: _selectedStartDate,
      customEndDate: _selectedEndDate,
      branchId: branchId,
    );
    // If null (all time), return today as default for owner dashboard
    if (result == null) {
      final branchId = _authService.currentBranch?.id ?? '';
      final businessDate = branchId.isEmpty
          ? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
          : await ClosingCycleService.getBusinessDate(branchId);
      return DateRangeSelection(
        startDate: DateTime(businessDate.year, businessDate.month, businessDate.day),
        endDate: DateTime(businessDate.year, businessDate.month, businessDate.day),
      );
    }
    return result;
  }

  Future<void> _loadOverviewData() async {
    try {
      _availableBranches = _authService.ownerBranches;
      if (_selectedBranchIds.isEmpty && _availableBranches.isNotEmpty) {
        _selectedBranchIds = _availableBranches.map((b) => b.id).toSet();
      }
      final branches = _getSelectedBranches();

      if (branches.isEmpty) {
        setState(() {
          _overviewData = {
            'totalSales': 0.0,
            'totalCashSales': 0.0,
            'totalCardSales': 0.0,
            'totalOnlineSales': 0.0,
          'totalExpenses': 0.0,
          'totalCashExpenses': 0.0,
          'totalOnlineExpenses': 0.0,
          'totalCreditExpenses': 0.0,
          'totalFixedExpenses': 0.0,
          'totalQrPayments': 0.0,
            'totalDues': 0.0,
            'totalReceivables': 0.0,
            'totalPayables': 0.0,
            'totalClosingCash': 0.0,
          };
        });
        return;
      }

      final dateRange = await _getDateRange();
      double totalExpenses = 0.0;
      double totalCashExpenses = 0.0;
      double totalOnlineExpenses = 0.0;
      double totalCreditExpenses = 0.0;
      double totalFixedExpenses = 0.0;
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
          totalCashExpenses += branchExpenses;

          final onlineExpenses = await _dbService.getOnlineExpenses(currentDate, branch.id);
          final branchOnlineExpenses = onlineExpenses.fold(0.0, (sum, e) => sum + e.amount);
          totalOnlineExpenses += branchOnlineExpenses;

          final creditExpenses = await _dbService.getCreditExpenses(currentDate, branch.id);
          final branchCreditExpenses = creditExpenses.fold(0.0, (sum, e) => sum + e.amount);
          totalCreditExpenses += branchCreditExpenses;
          
          // Fixed expenses for this date
          final fixedExpenses = await _dbService.getFixedExpenses(
            branch.id,
            startDate: currentDate,
            endDate: currentDate,
          );
          final branchFixedExpenses = fixedExpenses.fold(0.0, (sum, e) => sum + e.amount);
          totalFixedExpenses += branchFixedExpenses;
          
          totalExpenses += branchExpenses + branchOnlineExpenses + branchCreditExpenses + branchFixedExpenses;

          final cardSales = await _dbService.getCardSales(currentDate, branch.id);
          final branchCardSales = cardSales.fold(0.0, (sum, s) => sum + s.amount);
          totalCardSales += branchCardSales;

          final onlineSales = await _dbService.getOnlineSales(currentDate, branch.id);
          final branchOnlineSales = onlineSales.fold(0.0, (sum, s) => sum + s.net);
          totalOnlineSales += branchOnlineSales;

          // Use stored calculated total instead of calculating on the fly
          final qrTotal = await _dbService.getQrPaymentCalculatedTotal(currentDate, branch.id);
          totalQrPayments += qrTotal;

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

      // Total Sales = Cash Sales + Card Sales + Online Sales + QR Payments + Receivables
      final totalSales = totalCashSales + totalCardSales + totalOnlineSales + totalQrPayments + totalReceivables;
      // Total Due Amounts = Receivables - Payables
      final totalDues = totalReceivables - totalPayables;
      
      setState(() {
        _overviewData = {
          'totalSales': totalSales,
          'totalCashSales': totalCashSales,
          'totalCardSales': totalCardSales,
          'totalOnlineSales': totalOnlineSales,
          'totalExpenses': totalExpenses,
          'totalCashExpenses': totalCashExpenses,
          'totalOnlineExpenses': totalOnlineExpenses,
          'totalCreditExpenses': totalCreditExpenses,
          'totalFixedExpenses': totalFixedExpenses,
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
      _availableBranches = _authService.ownerBranches;
      if (_selectedBranchIds.isEmpty && _availableBranches.isNotEmpty) {
        _selectedBranchIds = _availableBranches.map((b) => b.id).toSet();
      }
      final branchList = _getSelectedBranches();
      if (branchList.isEmpty) {
        setState(() {
          _duesData = [];
        });
        return;
      }
      final dateRange = await _getDateRange();
      
      List<Due> allDues = [];
      for (var branch in branchList) {
        DateTime currentDate = dateRange.startDate;
        while (currentDate.isBefore(dateRange.endDate) || 
               currentDate.isAtSameMomentAs(dateRange.endDate)) {
          final dues = await _dbService.getDues(currentDate, branch.id);
          allDues.addAll(dues);
          currentDate = currentDate.add(const Duration(days: 1));
        }
      }
      setState(() {
        _duesData = allDues;
      });
    } catch (e) {
      // Error loading dues data
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchLabel = _branchFilterLabel();

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
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _availableBranches.isEmpty ? null : _showBranchSelectionSheet,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Branches',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          suffixIcon: Icon(
                            Icons.arrow_drop_down,
                            color: _availableBranches.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        child: Text(
                          branchLabel,
                          style: TextStyle(
                            color: _availableBranches.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
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
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _overviewData ?? {};
    
    // Calculate totals
    final totalSalesAmount = (data['totalSales'] ?? 0.0) as double;
    final totalExpensesAmount = (data['totalExpenses'] ?? 0.0) as double;
    final totalProfit = totalSalesAmount - totalExpensesAmount;
    final profitPercentage = totalSalesAmount > 0 
        ? (totalProfit / totalSalesAmount) * 100 
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sales Section
          _buildSectionHeader('Sales'),
          const SizedBox(height: 8),
          _buildTappableSummaryCard(
            'Total Cash Sales',
            CurrencyFormatter.format(data['totalCashSales'] ?? 0.0),
            Icons.money,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.cashSales, 'Total Cash Sales'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'Card Sales',
            CurrencyFormatter.format(data['totalCardSales'] ?? 0.0),
            Icons.credit_card,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.cardSales, 'Card Sales'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'Online Sales',
            CurrencyFormatter.format(data['totalOnlineSales'] ?? 0.0),
            Icons.shopping_cart,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.onlineSales, 'Online Sales'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'UPI Payments',
            CurrencyFormatter.format(data['totalQrPayments'] ?? 0.0),
            Icons.qr_code,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.qrPayments, 'UPI Payments'),
          ),
          const SizedBox(height: 12),
          _buildTappableTotalCard(
            'Total Sales',
            CurrencyFormatter.format(totalSalesAmount),
            Icons.trending_up,
            AppColors.success,
            () => _navigateToAggregatedDetail('Total Sales', data, totalSalesAmount, totalExpensesAmount, totalProfit),
          ),
          const SizedBox(height: 24),
          // Expenses Section
          _buildSectionHeader('Expenses'),
          const SizedBox(height: 8),
          _buildTappableSummaryCard(
            'Total Cash Expenses',
            CurrencyFormatter.format(data['totalCashExpenses'] ?? 0.0),
            Icons.receipt_long,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.cashExpenses, 'Total Cash Expenses'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'Total Online Expenses',
            CurrencyFormatter.format(data['totalOnlineExpenses'] ?? 0.0),
            Icons.account_balance,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.onlineExpenses, 'Total Online Expenses'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'Total Credit Expenses',
            CurrencyFormatter.format(data['totalCreditExpenses'] ?? 0.0),
            Icons.credit_card_outlined,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.creditExpenses, 'Total Credit Expenses'),
          ),
          const SizedBox(height: 12),
          _buildTappableSummaryCard(
            'Total Fixed Expenses',
            CurrencyFormatter.format(data['totalFixedExpenses'] ?? 0.0),
            Icons.receipt_long,
            AppColors.textPrimary,
            () => _navigateToDetail(DetailScreenType.fixedExpenses, 'Total Fixed Expenses'),
          ),
          const SizedBox(height: 12),
          _buildTappableTotalCard(
            'Total Expenses',
            CurrencyFormatter.format(totalExpensesAmount),
            Icons.account_balance,
            AppColors.error,
            () => _navigateToAggregatedDetail('Total Expenses', data, totalSalesAmount, totalExpensesAmount, totalProfit),
          ),
          const SizedBox(height: 12),
          _buildTappableProfitCard(
            totalProfit >= 0 ? 'Total Profit' : 'Total Loss',
            CurrencyFormatter.format(totalProfit),
            profitPercentage,
            totalProfit >= 0 ? Icons.trending_up : Icons.trending_down,
            totalProfit >= 0 ? AppColors.success : AppColors.error,
            () => _navigateToAggregatedDetail('Total Profit', data, totalSalesAmount, totalExpensesAmount, totalProfit),
          ),
          const SizedBox(height: 24),
          // Others Section
          _buildSectionHeader('Others'),
          const SizedBox(height: 8),
          _buildSummaryCard(
            'Total Due Amounts',
            CurrencyFormatter.format(data['totalDues'] ?? 0.0),
            Icons.pending_actions,
            AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Total Closing Cash',
            CurrencyFormatter.format(data['totalClosingCash'] ?? 0.0),
            Icons.account_balance_wallet,
            AppColors.primary,
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
                      due,
                      () => _navigateToDuesDetail(DueType.receivable, 'Receivables'),
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
                      due,
                      () => _navigateToDuesDetail(DueType.payable, 'Payables'),
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
                      color: AppColors.textTertiary,
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

  Widget _buildTappableSummaryCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
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
                        color: AppColors.textTertiary,
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
              Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTappableTotalCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
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
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTappableProfitCard(String title, String value, double percentage, IconData icon, Color color, VoidCallback onTap) {
    final percentageText = '${percentage >= 0 ? '+' : ''}${percentage.toStringAsFixed(1)}%';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
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
                    const SizedBox(height: 4),
                    Text(
                      percentageText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToDetail(DetailScreenType type, String title) async {
    final branches = _getSelectedBranches();
    final dateRange = await _getDateRange();
    
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerDashboardDetailScreen(
          type: type,
          title: title,
          selectedBranches: branches,
          dateRange: dateRange,
        ),
      ),
    );
  }

  Future<void> _navigateToAggregatedDetail(String title, Map<String, dynamic> data, double totalSales, double totalExpenses, double totalProfit) async {
    final branches = _getSelectedBranches();
    final dateRange = await _getDateRange();
    
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerDashboardAggregatedDetailScreen(
          title: title,
          data: data,
          totalSales: totalSales,
          totalExpenses: totalExpenses,
          totalProfit: totalProfit,
          selectedBranches: branches,
          dateRange: dateRange,
        ),
      ),
    );
  }

  Future<void> _navigateToDuesDetail(DueType dueType, String title) async {
    final branches = _getSelectedBranches();
    final dateRange = await _getDateRange();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerDashboardDuesDetailScreen(
          dueType: dueType,
          title: title,
          selectedBranches: branches,
          dateRange: dateRange,
        ),
      ),
    );
  }

  Widget _buildDueRow(Due due, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                due.party,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Text(
              CurrencyFormatter.format(due.amount, decimalDigits: 0),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    String getDisplayText() {
      switch (_selectedRangeOption) {
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


