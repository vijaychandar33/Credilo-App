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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No ${widget.title.toLowerCase()} for selected period',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterSummarySection(),
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
                              context,
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

  Widget _buildDueCard(BuildContext context, Due due, String branchName, String? branchLocation) {
    final theme = Theme.of(context);
    final isReceived = due.isReceived;
    final isReceivable = widget.dueType == DueType.receivable;
    final statusLabel = isReceivable
        ? (isReceived ? 'Received' : 'Not received')
        : (isReceived ? 'Paid' : 'Not paid');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (branchLocation != null && branchLocation.isNotEmpty)
                        Text(
                          branchLocation,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
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
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('d MMM yyyy').format(due.date),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _buildField(context, 'Party', due.party),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Status: ',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
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
                    statusLabel,
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
              _buildField(context, 'Remarks', due.remarks!),
            ],
            if (due.lastEditedEmail != null &&
                due.lastEditedEmail!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildField(context, 'Last Edited', due.lastEditedEmail!.trim()),
            ],
            if (due.statusLastEditedEmail != null &&
                due.statusLastEditedEmail!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildField(context, 'Status Last Edited', due.statusLastEditedEmail!.trim()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Summary row under the app bar showing which branch and date filters
  /// are currently applied (same wording as Owner Dashboard Overview).
  Widget _buildFilterSummarySection() {
    final theme = Theme.of(context);
    final branchLabel = _branchLabel();
    final dateLabel = _dateRangeLabel();

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _buildFilterChip('Branches', branchLabel),
          _buildFilterChip('Date', dateLabel),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _branchLabel() {
    if (widget.selectedBranches.isEmpty) return 'No branches';
    if (widget.selectedBranches.length == 1) {
      return widget.selectedBranches.first.name;
    }
    return '${widget.selectedBranches.length} branches';
  }

  String _dateRangeLabel() {
    final start = widget.dateRange.startDate;
    final end = widget.dateRange.endDate;
    final formatter = DateFormat('d MMM yyyy');
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return formatter.format(start);
    }
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  Widget _buildTotalCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.3 : 0.08),
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
            Text(
              'Total',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              CurrencyFormatter.format(_total),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
