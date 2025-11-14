import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/due.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
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

  Future<void> _loadOverviewData() async {
    try {
      final branches = _selectedBranch != null 
          ? [_selectedBranch!]
          : _authService.userBranches;

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
        final expenses = await _dbService.getCashExpenses(_selectedDate, branch.id);
        final branchExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
        totalExpenses += branchExpenses;

        final creditExpenses = await _dbService.getCreditExpenses(_selectedDate, branch.id);
        final branchCreditExpenses = creditExpenses.fold(0.0, (sum, e) => sum + e.amount);
        totalCreditExpenses += branchCreditExpenses;

        final cardSales = await _dbService.getCardSales(_selectedDate, branch.id);
        final branchCardSales = cardSales.fold(0.0, (sum, s) => sum + s.amount);
        totalCardSales += branchCardSales;

        final onlineSales = await _dbService.getOnlineSales(_selectedDate, branch.id);
        final branchOnlineSales = onlineSales.fold(0.0, (sum, s) => sum + s.net);
        totalOnlineSales += branchOnlineSales;

        final qrPayments = await _dbService.getQrPayments(_selectedDate, branch.id);
        totalQrPayments += qrPayments.fold(0.0, (sum, p) => sum + p.amount);

        final dues = await _dbService.getDues(_selectedDate, branch.id);
        // Calculate receivables and payables separately
        totalReceivables += dues
            .where((d) => d.type == DueType.receivable)
            .fold(0.0, (sum, d) => sum + d.amount);
        totalPayables += dues
            .where((d) => d.type == DueType.payable)
            .fold(0.0, (sum, d) => sum + d.amount);

        // Calculate cash sales for this branch: (Cash in Hand - Opening Balance) + Total Cash Expenses
        final cashCounts = await _dbService.getCashCounts(_selectedDate, branch.id);
        final countedCash = cashCounts.fold(0.0, (sum, count) => sum + count.total);
        
        // Get previous day's closing for opening balance
        final previousDate = _selectedDate.subtract(const Duration(days: 1));
        final previousClosing = await _dbService.getCashClosing(previousDate, branch.id);
        final opening = previousClosing?.nextOpening ?? 0.0;
        
        // Calculate: (Cash in Hand - Opening Balance) + Total Cash Expenses
        final branchCashSales = (countedCash - opening) + branchExpenses;
        totalCashSales += branchCashSales;

        final cashClosing = await _dbService.getCashClosing(_selectedDate, branch.id);
        if (cashClosing != null) {
          totalClosingCash += cashClosing.nextOpening;
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
      
      // If no branch selected, get dues from all branches
      if (branchId == null) {
        final branches = _authService.userBranches;
        List<Due> allDues = [];
        for (var branch in branches) {
          final branchDues = await _dbService.getDues(_selectedDate, branch.id);
          allDues.addAll(branchDues);
        }
        setState(() {
          _duesData = allDues;
        });
      } else {
        final dues = await _dbService.getDues(_selectedDate, branchId);
        setState(() {
          _duesData = dues;
        });
      }
    } catch (e) {
      // Error loading dues data
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final branches = authService.userBranches;

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
                  child: TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          _selectedDate = date;
                        });
                        _loadDashboardData();
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('d MMM yyyy').format(_selectedDate)),
                  ),
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

