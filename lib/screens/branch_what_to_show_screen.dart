import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../models/branch.dart';
import '../utils/branch_visibility_service.dart';

class BranchWhatToShowScreen extends StatefulWidget {
  final Branch branch;

  const BranchWhatToShowScreen({super.key, required this.branch});

  @override
  State<BranchWhatToShowScreen> createState() => _BranchWhatToShowScreenState();
}

class _BranchWhatToShowScreenState extends State<BranchWhatToShowScreen> {
  Map<String, bool> _visibility = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await BranchVisibilityService.getAll(widget.branch.id);
    if (mounted) {
      setState(() {
        _visibility = all;
        _isLoading = false;
      });
    }
  }

  Future<void> _set(String key, bool value) async {
    setState(() {
      _visibility[key] = value;
    });
    await BranchVisibilityService.set(widget.branch.id, key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What to show'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Choose which items to show on the home screen for ${widget.branch.name}. Hidden items are only hidden in the UI, not disabled.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        for (final key in BranchVisibilityKeys.all) ...[
                          if (key != BranchVisibilityKeys.all.first)
                            const Divider(height: 1),
                          _buildVisibilityTile(context, key),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildVisibilityTile(BuildContext context, String key) {
    final isCashClosing = key == BranchVisibilityKeys.cashClosing;
    final bool value = isCashClosing ? true : (_visibility[key] ?? true);

    final iconColor = isCashClosing
        ? AppColors.textTertiary
        : Theme.of(context).colorScheme.primary;

    final titleStyle = isCashClosing
        ? TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          )
        : null;

    return SwitchListTile(
      secondary: Icon(
        _iconFor(key),
        color: iconColor,
      ),
      title: Text(
        BranchVisibilityKeys.label(key),
        style: titleStyle,
      ),
      subtitle: isCashClosing
          ? Text(
              'Always shown (mandatory)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            )
          : null,
      value: value,
      onChanged: isCashClosing ? null : (v) => _set(key, v),
    );
  }

  IconData _iconFor(String key) {
    switch (key) {
      case BranchVisibilityKeys.creditExpense:
        return Icons.credit_card;
      case BranchVisibilityKeys.cashDailyExpense:
        return Icons.receipt_long;
      case BranchVisibilityKeys.onlineDailyExpense:
        return Icons.account_balance;
      case BranchVisibilityKeys.cashBalance:
        return Icons.account_balance_wallet;
      case BranchVisibilityKeys.card:
        return Icons.credit_card;
      case BranchVisibilityKeys.onlineSales:
        return Icons.shopping_cart;
      case BranchVisibilityKeys.upi:
        return Icons.qr_code;
      case BranchVisibilityKeys.due:
        return Icons.pending_actions;
      case BranchVisibilityKeys.cashClosing:
        return Icons.lock_clock;
      case BranchVisibilityKeys.safeManagement:
        return Icons.lock;
      default:
        return Icons.toggle_on;
    }
  }
}
