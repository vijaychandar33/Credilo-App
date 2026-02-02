import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/date_selector.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/branch.dart';
import '../utils/closing_cycle_service.dart';
import 'cash_expense_screen.dart';
import 'online_expense_screen.dart';
import 'credit_expense_screen.dart';
import 'cash_balance_screen.dart';
import 'card_screen.dart';
import 'online_sales_screen.dart';
import 'qr_payment_screen.dart';
import 'due_screen.dart';
import 'cash_closing_screen.dart';
import 'safe_management_screen.dart';
import 'settings_screen.dart';
import '../utils/app_colors.dart';

// Renamed to FinancialEntryScreen - this is for daily financial operations
class FinancialEntryScreen extends StatefulWidget {
  const FinancialEntryScreen({super.key});

  @override
  State<FinancialEntryScreen> createState() => _FinancialEntryScreenState();
}

class _FinancialEntryScreenState extends State<FinancialEntryScreen> {
  DateTime _selectedDate = DateTime.now();
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  bool _canEdit = false;
  bool _canView = false;
  bool _isLoadingPermissions = true;
  /// Whether each section has saved data for the selected date (visual indicator).
  Map<String, bool> _sectionHasData = {};

  @override
  void initState() {
    super.initState();
    _loadInitialDate();
    _ensureBranchData();
  }

  Future<void> _loadInitialDate() async {
    final businessDate = await ClosingCycleService.getBusinessDate();
    if (mounted) {
      setState(() {
        _selectedDate = businessDate;
      });
      await _loadPermissions();
      await _loadSectionData();
    }
  }

  Future<void> _loadPermissions() async {
    final canEdit = await _authService.canEditDate(_selectedDate);
    final canView = await _authService.canViewDate(_selectedDate);
    if (mounted) {
      setState(() {
        _canEdit = canEdit;
        _canView = canView;
        _isLoadingPermissions = false;
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

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isLoadingPermissions = true;
    });
    _loadPermissions().then((_) => _loadSectionData());
  }

  /// Loads whether each section has saved data for the selected date.
  Future<void> _loadSectionData() async {
    final branch = _authService.currentBranch;
    if (branch == null) return;
    final date = _selectedDate;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    try {
      final results = await Future.wait([
        _dbService.getCreditExpenses(date, branch.id),
        _dbService.getCashExpenses(date, branch.id),
        _dbService.getOnlineExpenses(date, branch.id),
        _dbService.getCashCounts(date, branch.id),
        _dbService.getCardSales(date, branch.id),
        _dbService.getOnlineSales(date, branch.id),
        _dbService.getQrPayments(date, branch.id),
        _dbService.getDues(date, branch.id),
        _dbService.getCashClosing(date, branch.id),
        _dbService.getSafeTransactions(branch.id, startDate: dayStart, endDate: dayEnd),
      ]);

      if (!mounted) return;
      setState(() {
        _sectionHasData = {
          'Credit Expense': (results[0] as List).isNotEmpty,
          'Cash Daily Expense': (results[1] as List).isNotEmpty,
          'Online Daily Expense': (results[2] as List).isNotEmpty,
          'Cash Balance': (results[3] as List).isNotEmpty,
          'Card': (results[4] as List).isNotEmpty,
          'Online Sales': (results[5] as List).isNotEmpty,
          'UPI': (results[6] as List).isNotEmpty,
          'Due': (results[7] as List).isNotEmpty,
          'Cash Closing': results[8] != null,
          'Safe Management': (results[9] as List).isNotEmpty,
        };
      });
    } catch (e) {
      debugPrint('Error loading section data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final canView = _canView;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          DateFormat('EEE d MMM yyyy').format(_selectedDate),
          style: const TextStyle(fontSize: 18),
        ),
        elevation: 0,
        actions: [
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
        child: Column(
        children: [
          // Branch Details Card
          if (_authService.currentBranch != null)
            _buildBranchDetailsCard(context, _authService),
          // Date Selector
          DateSelector(
            selectedDate: _selectedDate,
            onDateSelected: _onDateSelected,
          ),
          // Access Warning
          if (!_isLoadingPermissions && !canView)
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.warning.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can only view today and yesterday\'s data',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildQuickActionButton(
                    context,
                    'Credit Expense',
                    Icons.credit_card,
                    AppColors.primary,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreditExpenseScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Credit Expense'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Daily Expense',
                    Icons.receipt_long,
                    AppColors.primary,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashExpenseScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Cash Daily Expense'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Online Daily Expense',
                    Icons.account_balance,
                    AppColors.primary,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OnlineExpenseScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Online Daily Expense'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Balance',
                    Icons.account_balance_wallet,
                    AppColors.warning,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashBalanceScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Cash Balance'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Card',
                    Icons.credit_card,
                    AppColors.warning,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CardScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Card'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Online Sales',
                    Icons.shopping_cart,
                    AppColors.warning,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OnlineSalesScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Online Sales'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'UPI',
                    Icons.qr_code,
                    AppColors.warning,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => QrPaymentScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['UPI'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Due',
                    Icons.pending_actions,
                    AppColors.error,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DueScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Due'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Closing',
                    Icons.lock_clock,
                    AppColors.success,
                    canEdit
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashClosingScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            );
                            if (mounted) _loadSectionData();
                          }
                        : null,
                    disabled: !canEdit,
                    hasData: _sectionHasData['Cash Closing'] ?? false,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Safe Management',
                    Icons.lock,
                    AppColors.success,
                    () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SafeManagementScreen(
                            selectedDate: _selectedDate,
                          ),
                        ),
                      );
                      if (mounted) _loadSectionData();
                    },
                    disabled: false,
                    hasData: _sectionHasData['Safe Management'] ?? false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool disabled = false,
    bool hasData = false,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: disabled ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: disabled ? AppColors.surfaceContainer : color.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasData) ...[
                Icon(Icons.check_circle, color: AppColors.success, size: 22),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: color),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchDetailsCard(BuildContext context, AuthService authService) {
    final branch = authService.currentBranch;
    if (branch == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          branch.location,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: branch.status == BranchStatus.active
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.textTertiary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  branch.status.toString().split('.').last.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: branch.status == BranchStatus.active
                        ? AppColors.success
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

