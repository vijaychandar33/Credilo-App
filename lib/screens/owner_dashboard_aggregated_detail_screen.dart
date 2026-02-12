import 'package:flutter/material.dart';
import '../models/branch.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_range_utils.dart';
import 'owner_dashboard_detail_screen.dart';

class OwnerDashboardAggregatedDetailScreen extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final double totalSales;
  final double totalExpenses;
  final double totalProfit;
  final List<Branch> selectedBranches;
  final DateRangeSelection dateRange;

  const OwnerDashboardAggregatedDetailScreen({
    super.key,
    required this.title,
    required this.data,
    required this.totalSales,
    required this.totalExpenses,
    required this.totalProfit,
    required this.selectedBranches,
    required this.dateRange,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          if (title == 'Total Sales') ...[
            _buildSectionCard(
              context,
              'Total Cash Sales',
              CurrencyFormatter.format(data['totalCashSales'] ?? 0.0),
              Icons.money,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.cashSales, 'Total Cash Sales'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Card Sales',
              CurrencyFormatter.format(data['totalCardSales'] ?? 0.0),
              Icons.credit_card,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.cardSales, 'Card Sales'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Online Sales',
              CurrencyFormatter.format(data['totalOnlineSales'] ?? 0.0),
              Icons.shopping_cart,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.onlineSales, 'Online Sales'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'UPI Payments',
              CurrencyFormatter.format(data['totalQrPayments'] ?? 0.0),
              Icons.qr_code,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.qrPayments, 'UPI Payments'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Receivables',
              CurrencyFormatter.format(data['totalReceivables'] ?? 0.0),
              Icons.arrow_downward,
              AppColors.warning,
              null,
            ),
            const SizedBox(height: 24),
            _buildTotalCard('Total Sales', totalSales, AppColors.success),
          ] else if (title == 'Total Expenses') ...[
            _buildSectionCard(
              context,
              'Total Cash Expenses',
              CurrencyFormatter.format(data['totalCashExpenses'] ?? 0.0),
              Icons.receipt_long,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.cashExpenses, 'Total Cash Expenses'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Total Online Expenses',
              CurrencyFormatter.format(data['totalOnlineExpenses'] ?? 0.0),
              Icons.account_balance,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.onlineExpenses, 'Total Online Expenses'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Total Credit Expenses',
              CurrencyFormatter.format(data['totalCreditExpenses'] ?? 0.0),
              Icons.credit_card_outlined,
              AppColors.textPrimary,
              () => _navigateToDetail(context, DetailScreenType.creditExpenses, 'Total Credit Expenses'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Payables',
              CurrencyFormatter.format(data['totalPayables'] ?? 0.0),
              Icons.arrow_upward,
              AppColors.warning,
              null,
            ),
            const SizedBox(height: 24),
            _buildTotalCard('Total Expenses', totalExpenses, AppColors.error),
          ] else if (title == 'Total Profit') ...[
            _buildSectionCard(
              context,
              'Total Sales',
              CurrencyFormatter.format(totalSales),
              Icons.trending_up,
              AppColors.success,
              () => _navigateToAggregated(context, 'Total Sales'),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              'Total Expenses',
              CurrencyFormatter.format(totalExpenses),
              Icons.trending_down,
              AppColors.error,
              () => _navigateToAggregated(context, 'Total Expenses'),
            ),
            const SizedBox(height: 24),
            _buildTotalCard(
              totalProfit >= 0 ? 'Total Profit' : 'Total Loss',
              totalProfit,
              totalProfit >= 0 ? AppColors.success : AppColors.error,
            ),
            const SizedBox(height: 8),
            if (totalSales > 0)
              Center(
                child: Text(
                  '${totalProfit >= 0 ? '+' : ''}${((totalProfit / totalSales) * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: totalProfit >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
          ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, String title, String value, IconData icon, Color color, VoidCallback? onTap) {
    final card = Card(
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
            if (onTap != null)
              Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }

  Widget _buildTotalCard(String title, double value, Color color) {
    return Card(
      elevation: 3,
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              CurrencyFormatter.format(value),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, DetailScreenType type, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerDashboardDetailScreen(
          type: type,
          title: title,
          selectedBranches: selectedBranches,
          dateRange: dateRange,
        ),
      ),
    );
  }

  void _navigateToAggregated(BuildContext context, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnerDashboardAggregatedDetailScreen(
          title: title,
          data: data,
          totalSales: totalSales,
          totalExpenses: totalExpenses,
          totalProfit: totalProfit,
          selectedBranches: selectedBranches,
          dateRange: dateRange,
        ),
      ),
    );
  }
}

