import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/branch.dart';
import '../models/due.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_range_utils.dart';

class OwnerDashboardDuesDetailScreen extends StatefulWidget {
  final DueType dueType;
  final String title;
  final List<Branch> selectedBranches;
  final DateRangeSelection dateRange;

  const OwnerDashboardDuesDetailScreen({
    super.key,
    required this.dueType,
    required this.title,
    required this.selectedBranches,
    required this.dateRange,
  });

  @override
  State<OwnerDashboardDuesDetailScreen> createState() =>
      _OwnerDashboardDuesDetailScreenState();
}

class _OwnerDashboardDuesDetailScreenState
    extends State<OwnerDashboardDuesDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  bool _isLoading = true;
  List<Due> _items = [];
  double _total = 0.0;

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
      List<Due> allDues = [];
      final typeStr = widget.dueType == DueType.receivable ? 'receivable' : 'payable';

      for (var branch in widget.selectedBranches) {
        DateTime currentDate = widget.dateRange.startDate;
        while (currentDate.isBefore(widget.dateRange.endDate) ||
            currentDate.isAtSameMomentAs(widget.dateRange.endDate)) {
          final dues = await _dbService.getDues(
            currentDate,
            branch.id,
            type: typeStr,
          );
          allDues.addAll(dues);
          currentDate = currentDate.add(const Duration(days: 1));
        }
      }

      allDues.sort((a, b) {
        final dateCompare = b.date.compareTo(a.date);
        if (dateCompare != 0) return dateCompare;
        return a.party.compareTo(b.party);
      });

      final total = allDues.fold(0.0, (sum, d) => sum + d.amount);

      if (mounted) {
        setState(() {
          _items = allDues;
          _total = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                          'No ${widget.title.toLowerCase()} for selected period',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final due = _items[index];
                            final branchMatch = widget.selectedBranches
                                .where((b) => b.id == due.branchId);
                            final branch = branchMatch.isEmpty
                                ? null
                                : branchMatch.first;
                            return _buildDueCard(
                              due,
                              branch?.name ?? due.branchId,
                              branch?.location,
                            );
                          },
                        ),
                      ),
                      _buildTotalCard(),
                    ],
                  ),
      ),
    );
  }

  Future<void> _toggleReceived(Due due) async {
    if (due.id == null) return;
    try {
      await _dbService.updateDueStatus(due.id!, !due.isReceived);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              due.isReceived
                  ? 'Marked as not received'
                  : 'Marked as received',
            ),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  Widget _buildDueCard(Due due, String branchName, String? branchLocation) {
    final isReceived = due.isReceived;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: due.id != null
            ? () => _toggleReceived(due)
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
                        branchName,
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
                  CurrencyFormatter.format(due.amount),
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
              DateFormat('d MMM yyyy').format(due.date),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            _buildField('Party', due.party),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Status: ',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isReceived
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isReceived ? 'Received' : 'Not received',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isReceived ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            if (due.remarks != null && due.remarks!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildField('Remarks', due.remarks!),
            ],
            if (due.id != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tap to toggle received / not received',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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
