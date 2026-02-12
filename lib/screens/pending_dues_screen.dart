import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/due.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';

class PendingDuesScreen extends StatefulWidget {
  const PendingDuesScreen({super.key});

  @override
  State<PendingDuesScreen> createState() => _PendingDuesScreenState();
}

class _PendingDuesScreenState extends State<PendingDuesScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  List<Due> _pendingDues = [];

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
      final branch = _authService.currentBranch;
      if (branch == null) {
        if (mounted) {
          setState(() {
            _pendingDues = [];
            _isLoading = false;
          });
        }
        return;
      }

      final dues = await _dbService.getPendingDues(branch.id);
      if (mounted) {
        setState(() {
          _pendingDues = dues;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingDues = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load pending dues: $e')),
        );
      }
    }
  }

  Future<void> _markAsReceivedOrPaid(Due due) async {
    if (due.id == null) return;

    final isReceivable = due.type == DueType.receivable;
    final actionLabel = isReceivable ? 'Received' : 'Paid';
    final message = isReceivable
        ? 'Mark this receivable as Received?'
        : 'Mark this payable as Paid?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as $actionLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('d MMM yyyy').format(due.date),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Party: ${due.party}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Amount: ${CurrencyFormatter.format(due.amount)}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Type: ${isReceivable ? 'Receivable' : 'Payable'}',
              style: const TextStyle(fontSize: 13),
            ),
            if (due.remarks != null && due.remarks!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Remarks: ${due.remarks}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _dbService.updateDueStatus(due.id!, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked as $actionLabel'),
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Dues'),
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendingDues.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No pending dues',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All receivables and payables are cleared',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingDues.length,
                    itemBuilder: (context, index) {
                      final due = _pendingDues[index];
                      return _buildDueCard(due);
                    },
                  ),
      ),
    );
  }

  Widget _buildDueCard(Due due) {
    final isReceivable = due.type == DueType.receivable;
    final typeLabel = isReceivable ? 'Receivable' : 'Payable';
    final typeColor = isReceivable ? AppColors.primary : AppColors.warning;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onLongPress: due.id != null
            ? () => _markAsReceivedOrPaid(due)
            : null,
        borderRadius: BorderRadius.circular(12),
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
                          due.party,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d MMM yyyy').format(due.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(due.amount),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (due.remarks != null && due.remarks!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  due.remarks!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              if (due.lastEditedEmail != null &&
                  due.lastEditedEmail!.trim().isNotEmpty) ...[
                Text(
                  'Last Edited: ${due.lastEditedEmail!.trim()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (due.statusLastEditedEmail != null &&
                  due.statusLastEditedEmail!.trim().isNotEmpty) ...[
                Text(
                  'Status Last Edited: ${due.statusLastEditedEmail!.trim()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                'Long press to mark as ${isReceivable ? 'Received' : 'Paid'}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
