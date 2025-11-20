import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/date_selector.dart';
import '../services/auth_service.dart';
import '../models/branch.dart';
import 'cash_expense_screen.dart';
import 'credit_expense_screen.dart';
import 'cash_balance_screen.dart';
import 'card_screen.dart';
import 'online_sales_screen.dart';
import 'qr_payment_screen.dart';
import 'due_screen.dart';
import 'cash_closing_screen.dart';
import 'settings_screen.dart';
import '../utils/app_colors.dart';

// Renamed to FinancialEntryScreen - this is for daily financial operations
class FinancialEntryScreen extends StatefulWidget {
  const FinancialEntryScreen({super.key});

  @override
  State<FinancialEntryScreen> createState() => _FinancialEntryScreenState();
}

class _FinancialEntryScreenState extends State<FinancialEntryScreen> {
  late DateTime _selectedDate;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _ensureBranchData();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _authService.canEditDate(_selectedDate);
    final canView = _authService.canViewDate(_selectedDate);

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
      body: Column(
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
          if (!canView)
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
                    AppColors.warning,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreditExpenseScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Daily Expense',
                    Icons.receipt_long,
                    AppColors.primary,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashExpenseScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Balance',
                    Icons.account_balance_wallet,
                    AppColors.success,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashBalanceScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Card',
                    Icons.credit_card,
                    AppColors.warning,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CardScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Online Sales',
                    Icons.shopping_cart,
                    AppColors.primary,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OnlineSalesScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'UPI',
                    Icons.qr_code,
                    AppColors.primaryLight,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => QrPaymentScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Due',
                    Icons.pending_actions,
                    AppColors.error,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DueScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    'Cash Closing',
                    Icons.lock_clock,
                    Colors.indigo,
                    canEdit
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CashClosingScreen(
                                  selectedDate: _selectedDate,
                                ),
                              ),
                            )
                        : null,
                    disabled: !canEdit,
                  ),
                ],
              ),
            ),
          ),
        ],
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

