import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cash_count.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/error_message_helper.dart';

class CashBalanceScreen extends StatefulWidget {
  final DateTime selectedDate;

  const CashBalanceScreen({super.key, required this.selectedDate});

  @override
  State<CashBalanceScreen> createState() => _CashBalanceScreenState();
}

class _CashBalanceScreenState extends State<CashBalanceScreen> {
  final Map<String, int> _coinCounts = {
    '1': 0,
    '2': 0,
    '5': 0,
    '10': 0,
    '20': 0,
  };

  final Map<String, int> _noteCounts = {
    '10': 0,
    '20': 0,
    '50': 0,
    '100': 0,
    '200': 0,
    '500': 0,
    '2000': 0,
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final cashCounts = await _dbService.getCashCounts(widget.selectedDate, branch.id);
      
      for (var count in cashCounts) {
        final denom = count.denomination;
        final countValue = count.count;
        
        // Parse denomination format: "10_coin" or "10_note" or just "10" (legacy)
        if (denom.endsWith('_coin')) {
          final value = denom.replaceAll('_coin', '');
          if (_coinCounts.containsKey(value)) {
            _coinCounts[value] = countValue;
            _controllers['${value}_coin']?.text =
                countValue == 0 ? '' : countValue.toString();
          }
        } else if (denom.endsWith('_note')) {
          final value = denom.replaceAll('_note', '');
          if (_noteCounts.containsKey(value)) {
            _noteCounts[value] = countValue;
            _controllers['${value}_note']?.text =
                countValue == 0 ? '' : countValue.toString();
          }
        } else {
          // Legacy format - try to determine if it's coin or note
          // If it exists in both, we can't determine, so skip
          // Otherwise assign to the appropriate map
          if (_coinCounts.containsKey(denom) && !_noteCounts.containsKey(denom)) {
            _coinCounts[denom] = countValue;
            _controllers['${denom}_coin']?.text =
                countValue == 0 ? '' : countValue.toString();
          } else if (_noteCounts.containsKey(denom) && !_coinCounts.containsKey(denom)) {
            _noteCounts[denom] = countValue;
            _controllers['${denom}_note']?.text =
                countValue == 0 ? '' : countValue.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading cash balance data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initializeControllers() {
    // Use unique keys for coins and notes to avoid conflicts
    for (var denom in _coinCounts.keys) {
      _createControllerAndFocusNode('${denom}_coin');
    }
    for (var denom in _noteCounts.keys) {
      _createControllerAndFocusNode('${denom}_note');
    }
  }

  void _createControllerAndFocusNode(String key) {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        Future.microtask(() {
          controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
        });
      }
    });
    _controllers[key] = controller;
    _focusNodes[key] = focusNode;
  }

  double _getTotalCoins() {
    return _coinCounts.entries.fold(0.0, (sum, entry) {
      return sum + (int.parse(entry.key) * entry.value);
    });
  }

  double _getTotalNotes() {
    return _noteCounts.entries.fold(0.0, (sum, entry) {
      return sum + (int.parse(entry.key) * entry.value);
    });
  }

  double _getTotalCash() {
    return _getTotalCoins() + _getTotalNotes();
  }

  void _updateCount(String denomination, int count, {required bool isCoin}) {
    setState(() {
      final controllerKey = isCoin ? '${denomination}_coin' : '${denomination}_note';
      if (isCoin && _coinCounts.containsKey(denomination)) {
        _coinCounts[denomination] = count;
      } else if (!isCoin && _noteCounts.containsKey(denomination)) {
        _noteCounts[denomination] = count;
      }
      _controllers[controllerKey]?.text = count == 0 ? '' : count.toString();
    });
  }

  void _increment(String denomination, {required bool isCoin}) {
    final current = isCoin 
        ? (_coinCounts[denomination] ?? 0)
        : (_noteCounts[denomination] ?? 0);
    _updateCount(denomination, current + 1, isCoin: isCoin);
  }

  void _decrement(String denomination, {required bool isCoin}) {
    final current = isCoin 
        ? (_coinCounts[denomination] ?? 0)
        : (_noteCounts[denomination] ?? 0);
    if (current > 0) {
      _updateCount(denomination, current - 1, isCoin: isCoin);
    }
  }

  void _onCountChanged(String denomination, String value, {required bool isCoin}) {
    final count = int.tryParse(value) ?? 0;
    _updateCount(denomination, count, isCoin: isCoin);
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
      List<CashCount> cashCounts = [];

      // Add coin counts with "_coin" suffix
      for (var entry in _coinCounts.entries) {
        if (entry.value > 0) {
          final denomination = '${entry.key}_coin';
          final count = entry.value;
          final total = int.parse(entry.key) * count;

          cashCounts.add(CashCount(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            denomination: denomination,
            count: count,
            total: total.toDouble(),
          ));
        }
      }

      // Add note counts with "_note" suffix
      for (var entry in _noteCounts.entries) {
        if (entry.value > 0) {
          final denomination = '${entry.key}_note';
          final count = entry.value;
          final total = int.parse(entry.key) * count;

          cashCounts.add(CashCount(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            denomination: denomination,
            count: count,
            total: total.toDouble(),
          ));
        }
      }

      await _dbService.saveCashCounts(cashCounts);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash balance saved successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save cash balance. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
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
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Cash Balance - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Cash Balance - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Coins', _coinCounts, isCoin: true),
                  const SizedBox(height: 24),
                  _buildSection('Notes', _noteCounts, isCoin: false),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Total Coins', _getTotalCoins()),
                  const SizedBox(height: 8),
                  _buildSummaryRow('Total Notes', _getTotalNotes()),
                  const Divider(),
                  _buildSummaryRow(
                    'Total Cash in Hand',
                    _getTotalCash(),
                    isTotal: true,
                  ),
                  const SizedBox(height: 12),
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
                          : const Text('Save', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Map<String, int> counts, {required bool isCoin}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...counts.keys.map((denom) => _buildDenominationRow(denom, counts[denom] ?? 0, isCoin: isCoin)),
      ],
    );
  }

  Widget _buildDenominationRow(String denomination, int count, {required bool isCoin}) {
    final value = int.parse(denomination) * count;
    final controllerKey = isCoin ? '${denomination}_coin' : '${denomination}_note';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                CurrencyFormatter.format(
                  int.parse(denomination),
                  decimalDigits: 0,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _decrement(denomination, isCoin: isCoin),
            ),
            Expanded(
              child: TextField(
                controller: _controllers[controllerKey],
                focusNode: _focusNodes[controllerKey],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) => _onCountChanged(denomination, value, isCoin: isCoin),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _increment(denomination, isCoin: isCoin),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: Text(
                CurrencyFormatter.format(value, decimalDigits: 0),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 18 : 16,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          CurrencyFormatter.format(amount),
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: isTotal
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
      ],
    );
  }
}

