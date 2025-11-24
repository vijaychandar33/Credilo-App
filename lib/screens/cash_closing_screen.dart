import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cash_closing.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';

class CashClosingScreen extends StatefulWidget {
  final DateTime selectedDate;

  const CashClosingScreen({super.key, required this.selectedDate});

  @override
  State<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends State<CashClosingScreen> {
  final TextEditingController openingController = TextEditingController();
  final TextEditingController totalCashSalesController = TextEditingController();
  final TextEditingController totalExpensesController = TextEditingController();
  final TextEditingController countedCashController = TextEditingController();
  final TextEditingController withdrawnController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isSaving = false;

  double _opening = 0;
  double _totalCashSales = 0;
  double _totalExpenses = 0;
  double _countedCash = 0;
  double _withdrawn = 0;

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
      if (branch == null) return;

      // Load previous day's closing for opening balance
      final previousDate = widget.selectedDate.subtract(const Duration(days: 1));
      final previousClosing = await _dbService.getCashClosing(previousDate, branch.id);
      if (previousClosing != null) {
        _opening = previousClosing.nextOpening;
        openingController.text = _opening.toStringAsFixed(2);
      }

      // Load expenses for the day
      final expenses = await _dbService.getCashExpenses(widget.selectedDate, branch.id);
      _totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
      totalExpensesController.text = _totalExpenses.toStringAsFixed(2);

      // Load cash balance from cash counts
      final cashCounts = await _dbService.getCashCounts(widget.selectedDate, branch.id);
      _countedCash = cashCounts.fold(0.0, (sum, count) => sum + count.total);
      countedCashController.text = _countedCash.toStringAsFixed(2);
      debugPrint(
        'Cash balance from cash counts: ${CurrencyFormatter.format(_countedCash)}',
      );

      // Calculate Total Cash Sales: (Cash in Hand - Opening Balance) + Total Cash Expenses
      _totalCashSales = (_countedCash - _opening) + _totalExpenses;
      totalCashSalesController.text = _totalCashSales.toStringAsFixed(2);
      debugPrint('Total Cash Sales calculated: ($_countedCash - $_opening) + $_totalExpenses = $_totalCashSales');

      // Load existing cash closing if available (for withdrawn)
      final existingClosing = await _dbService.getCashClosing(widget.selectedDate, branch.id);
      if (existingClosing != null) {
        _withdrawn = existingClosing.withdrawn;
        withdrawnController.text = _withdrawn.toStringAsFixed(2);
      }

      _calculateNextOpening();
    } catch (e) {
      debugPrint('Error loading cash closing data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _calculateNextOpening() {
    setState(() {
      // Recalculate Total Cash Sales when values change
      _totalCashSales = (_countedCash - _opening) + _totalExpenses;
      totalCashSalesController.text = _totalCashSales.toStringAsFixed(2);
      // UI will update automatically via _getNextOpening()
    });
  }

  double _getNextOpening() {
    return _opening + _totalCashSales - _totalExpenses - _withdrawn;
  }

  double _getExpectedCash() {
    return _opening + _totalCashSales - _totalExpenses;
  }

  double _getDiscrepancy() {
    return _countedCash - _getExpectedCash();
  }

  Future<void> _save() async {
    final user = _authService.currentUser;
    final branch = _authService.currentBranch;

    if (user == null || branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User or branch not found')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final closing = CashClosing(
        date: widget.selectedDate,
        userId: user.id,
        branchId: branch.id,
        opening: _opening,
        totalCashSales: _totalCashSales,
        totalExpenses: _totalExpenses,
        countedCash: _countedCash,
        withdrawn: _withdrawn,
        adjustments: null,
        nextOpening: _getNextOpening(),
        discrepancy: _getDiscrepancy() == 0 ? null : _getDiscrepancy(),
      );

      await _dbService.saveCashClosing(closing);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash closing saved successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving cash closing: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Cash Closing - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const SafeArea(
          top: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Cash Closing - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildField(
                'Opening Balance',
                openingController,
                _opening,
                (value) {
                  setState(() {
                    _opening = value;
                    _calculateNextOpening();
                  });
                },
                isEditable: false,
                info: 'From previous day\'s closing balance',
              ),
            const SizedBox(height: 16),
            _buildField(
              'Total Cash Sales',
              totalCashSalesController,
              _totalCashSales,
              (value) {
                setState(() {
                  _totalCashSales = value;
                  _calculateNextOpening();
                });
              },
              isEditable: false,
              info: 'Calculated: (Cash in Hand - Opening Balance) + Total Cash Expenses',
            ),
            const SizedBox(height: 16),
            _buildField(
              'Total Cash Expenses',
              totalExpensesController,
              _totalExpenses,
              (value) {
                setState(() {
                  _totalExpenses = value;
                  _calculateNextOpening();
                });
              },
              isEditable: false,
              info: 'From Cash Daily Expense',
            ),
            const SizedBox(height: 16),
            _buildField(
              'Cash in Hand (Counted)',
              countedCashController,
              _countedCash,
              (value) {
                setState(() {
                  _countedCash = value;
                  _calculateNextOpening();
                });
              },
              isEditable: false,
              info: 'Auto-fetched from Cash Balance screen',
            ),
            const SizedBox(height: 16),
            _buildField(
              'Withdrawn to Safe',
              withdrawnController,
              _withdrawn,
              (value) {
                setState(() {
                  _withdrawn = value;
                  _calculateNextOpening();
                });
              },
              isEditable: true,
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next Day Opening Balance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CurrencyFormatter.format(_getNextOpening()),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isLoading || _isSaving) ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Closing', style: TextStyle(fontSize: 16)),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    double value,
    Function(double) onChanged, {
    bool isEditable = false,
    String? info,
  }) {
    if (controller.text.isEmpty && value != 0) {
      controller.text = value.toStringAsFixed(2);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (info != null)
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 18),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(info)),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: '₹',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              readOnly: !isEditable,
              onChanged: (text) {
                final val = double.tryParse(text) ?? 0;
                onChanged(val);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    openingController.dispose();
    totalCashSalesController.dispose();
    totalExpensesController.dispose();
    countedCashController.dispose();
    withdrawnController.dispose();
    super.dispose();
  }
}

