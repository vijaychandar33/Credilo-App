import 'package:flutter/material.dart';
import '../models/branch.dart';
import '../models/due.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'owner_dashboard_screen.dart';
import 'home_screen.dart';
import 'add_branch_screen.dart';
import 'settings_screen.dart';
import 'supplier_management_screen.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({super.key});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  Map<String, dynamic>? _todayStats;
  bool _isLoading = true;
  DateTime? _lastRefreshTime;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureBranchData();
    _loadDashboardData();
    _hasLoadedOnce = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      _refreshIfNeeded();
    }
  }

  void _refreshIfNeeded() {
    // Only refresh if it's been more than 1 second since last refresh
    final now = DateTime.now();
    if (_lastRefreshTime == null || 
        now.difference(_lastRefreshTime!).inSeconds > 1) {
      _lastRefreshTime = now;
      if (mounted) {
        _loadDashboardData();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when navigating back to this screen (only after initial load)
    if (_hasLoadedOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final route = ModalRoute.of(context);
          if (route != null && route.isCurrent) {
            _refreshIfNeeded();
          }
        }
      });
    }
  }

  Future<void> _ensureBranchData() async {
    // Ensure branch data is loaded
    if (_authService.currentBranch == null && _authService.currentUser != null) {
      await _authService.refreshBranches();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branches = _authService.userBranches;
      if (branches.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final today = DateTime.now();

      // Aggregate data across all branches
      double totalExpenses = 0.0;
      double totalCardSales = 0.0;
      double totalOnlineSales = 0.0;
      double totalQrPayments = 0.0;
      double totalReceivables = 0.0;
      double totalPayables = 0.0;
      double totalCashClosing = 0.0;
      double totalCashSales = 0.0;

      for (var branch in branches) {
        final cashExpenses = await _dbService.getCashExpenses(today, branch.id);
        final branchCashExpenses = cashExpenses.fold(0.0, (sum, e) => sum + e.amount);
        
        final creditExpenses = await _dbService.getCreditExpenses(today, branch.id);
        final branchCreditExpenses = creditExpenses.fold(0.0, (sum, e) => sum + e.amount);
        
        totalExpenses += branchCashExpenses + branchCreditExpenses;

        final cardSales = await _dbService.getCardSales(today, branch.id);
        totalCardSales += cardSales.fold(0.0, (sum, s) => sum + s.amount);

        final onlineSales = await _dbService.getOnlineSales(today, branch.id);
        totalOnlineSales += onlineSales.fold(0.0, (sum, s) => sum + s.net);

        final qrPayments = await _dbService.getQrPayments(today, branch.id);
        totalQrPayments += qrPayments.fold(0.0, (sum, p) => sum + p.amount);

        final dues = await _dbService.getDues(today, branch.id);
        totalReceivables += dues
            .where((d) => d.type == DueType.receivable)
            .fold(0.0, (sum, d) => sum + d.amount);
        totalPayables += dues
            .where((d) => d.type == DueType.payable)
            .fold(0.0, (sum, d) => sum + d.amount);

        // Calculate cash sales for this branch: (Cash in Hand - Opening Balance) + Total Cash Expenses
        final cashCounts = await _dbService.getCashCounts(today, branch.id);
        final countedCash = cashCounts.fold(0.0, (sum, count) => sum + count.total);
        
        // Get previous day's closing for opening balance
        final previousDate = today.subtract(const Duration(days: 1));
        final previousClosing = await _dbService.getCashClosing(previousDate, branch.id);
        final opening = previousClosing?.nextOpening ?? 0.0;
        
        // Calculate: (Cash in Hand - Opening Balance) + Total Cash Expenses
        final branchCashSales = (countedCash - opening) + branchCashExpenses;
        totalCashSales += branchCashSales;

        final cashClosing = await _dbService.getCashClosing(today, branch.id);
        if (cashClosing != null) {
          totalCashClosing += cashClosing.nextOpening;
        }
      }

      // Total Sales = Cash Sales + Card/Online Sales + QR Payments + Receivables
      final totalCardOnline = totalCardSales + totalOnlineSales;
      final totalSales = totalCashSales + totalCardOnline + totalQrPayments + totalReceivables;
      final netProfit = totalSales - totalExpenses;

      setState(() {
        _todayStats = {
          'totalSales': totalSales,
          'totalCashSales': totalCashSales,
          'totalExpenses': totalExpenses,
          'totalReceivables': totalReceivables,
          'totalPayables': totalPayables,
          'cashClosing': totalCashClosing,
          'netProfit': netProfit,
        };
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = _authService.userBranches;
    final isBusinessOwner = _authService.canManageUsers();
    final isBranchOwner = _authService.isBranchOwner();
    
    // Show owner dashboard icon if user is a business owner OR branch owner
    final canAccessOwnerDashboard = isBusinessOwner || isBranchOwner;
    
    // Debug info
    debugPrint('Dashboard - Branches count: ${branches.length}, IsBusinessOwner: $isBusinessOwner, IsBranchOwner: $isBranchOwner, CurrentRole: ${_authService.currentRole}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (canAccessOwnerDashboard)
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OwnerDashboardScreen(),
                  ),
                );
              },
              tooltip: 'Analytics Dashboard',
            ),
          if (isBusinessOwner)
            IconButton(
              icon: const Icon(Icons.store_mall_directory),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SupplierManagementScreen(),
                  ),
                );
              },
              tooltip: 'Suppliers',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Branch Management - Show for all users, but with different options
                      _buildBranchManagement(branches, isBusinessOwner),
                      const SizedBox(height: 16),

                      // Quick Stats
                      _buildQuickStats(),
                      const SizedBox(height: 16),

                      // Today's Summary
                      if (_todayStats != null) ...[
                        _buildTodaySummary(),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Sales',
            _todayStats?['totalSales'] ?? 0.0,
            Icons.trending_up,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Total Expenses',
            _todayStats?['totalExpenses'] ?? 0.0,
            Icons.trending_down,
            AppColors.error,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, double value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(
                  CurrencyFormatter.format(value, decimalDigits: 0),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Summary",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('Sales', _todayStats!['totalSales'] ?? 0.0, AppColors.success),
            _buildSummaryRow('Expenses', _todayStats!['totalExpenses'] ?? 0.0, AppColors.error),
            const Divider(),
            _buildSummaryRow('Net Profit', _todayStats!['netProfit'] ?? 0.0, 
                (_todayStats!['netProfit'] ?? 0.0) >= 0 ? AppColors.success : AppColors.error),
            const SizedBox(height: 8),
            _buildSummaryRow('Receivables', _todayStats!['totalReceivables'] ?? 0.0, AppColors.warning),
            _buildSummaryRow('Payables', _todayStats!['totalPayables'] ?? 0.0, AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            CurrencyFormatter.format(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchManagement(List<Branch> branches, bool isOwner) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.business, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Branches',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (isOwner)
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddBranchScreen(),
                        ),
                      );
                      if (result != null && mounted) {
                        await _authService.refreshBranches();
                        _loadDashboardData();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Branch'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (branches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No branches yet. Add your first branch!',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ),
              )
            else
              ...branches.map((branch) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: InkWell(
                    onTap: () async {
                      // Set the selected branch and navigate to daily operations
                      _authService.setCurrentBranch(branch);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FinancialEntryScreen(),
                        ),
                      );
                      // Refresh dashboard data when returning
                      if (mounted) {
                        _loadDashboardData();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: const Icon(Icons.store, color: AppColors.primary),
                      title: Text(
                        branch.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(branch.location),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: branch.status == BranchStatus.active
                                  ? AppColors.success.withValues(alpha: 0.2)
                                  : AppColors.textTertiary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              branch.status == BranchStatus.active ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: branch.status == BranchStatus.active
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

}

