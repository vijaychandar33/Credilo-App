import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/qr_payment.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class QrPaymentScreen extends StatefulWidget {
  final DateTime selectedDate;

  const QrPaymentScreen({super.key, required this.selectedDate});

  @override
  State<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends State<QrPaymentScreen> {
  final List<QrPaymentRow> _payments = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  List<String> _existingPaymentIds = []; // Track existing payment IDs
  final List<String> _providers = [
    'Paytm',
    'PhonePe',
    'GooglePay',
    'Others',
  ];

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
        setState(() {
          _isLoading = false;
        });
        _addNewPayment();
        return;
      }

      final payments = await _dbService.getQrPayments(widget.selectedDate, branch.id);
      
      if (payments.isNotEmpty) {
        setState(() {
          _payments.clear();
          _existingPaymentIds.clear();
          
          for (var payment in payments) {
            final row = QrPaymentRow();
            row.provider = payment.provider;
            row.amountController.text = payment.amount.toStringAsFixed(2);
            row.amount = payment.amount;
            if (payment.txnId != null) {
              row.txnIdController.text = payment.txnId!;
            }
            if (payment.settlementDate != null) {
              row.settlementDate = payment.settlementDate;
              row.settlementDateController.text = DateFormat('d MMM yyyy').format(payment.settlementDate!);
            }
            if (payment.notes != null) {
              row.notesController.text = payment.notes!;
            }
            
            _payments.add(row);
            if (payment.id != null) {
              _existingPaymentIds.add(payment.id!);
            }
          }
        });
      } else {
        _addNewPayment();
      }
    } catch (e) {
      debugPrint('Error loading QR payments: $e');
      _addNewPayment();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addNewPayment() {
    setState(() {
      _payments.add(QrPaymentRow());
    });
  }

  void _removePayment(int index) {
    setState(() {
      _payments.removeAt(index);
      if (_payments.isEmpty) {
        _addNewPayment();
      }
    });
  }

  double _getTotalPayments() {
    return _payments.fold(0.0, (sum, payment) => sum + (payment.amount ?? 0));
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

    // Validate that at least one payment has amount
    if (!_payments.any((payment) => payment.amount != null && payment.amount! > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one payment with amount')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      for (var paymentRow in _payments) {
        if (paymentRow.amount != null && paymentRow.amount! > 0) {
          if (paymentRow.provider == null || paymentRow.provider!.isEmpty) {
            continue; // Skip if provider is not selected
          }

          final payment = QrPayment(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            provider: paymentRow.provider!,
            amount: paymentRow.amount!,
            txnId: paymentRow.txnIdController.text.trim().isEmpty
                ? null
                : paymentRow.txnIdController.text.trim(),
            settlementDate: paymentRow.settlementDate,
            notes: paymentRow.notesController.text.trim().isEmpty
                ? null
                : paymentRow.notesController.text.trim(),
          );

          await _dbService.saveQrPayment(payment);
        }
      }

      // Reload data to get fresh IDs
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR payments saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving QR payments: $e')),
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
          title: Text('Paytm / QR - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Paytm / QR - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _payments.length + 1,
              itemBuilder: (context, index) {
                if (index == _payments.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addNewPayment,
                      icon: const Icon(Icons.add),
                      label: const Text('Add QR Payment'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }
                return _buildPaymentRow(index);
              },
            ),
          ),
          Container(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total QR Payments:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₹${_getTotalPayments().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
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
        ],
      ),
    );
  }

  Widget _buildPaymentRow(int index) {
    final payment = _payments[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: payment.provider,
                    decoration: const InputDecoration(
                      labelText: 'Payment Provider',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _providers.map((provider) {
                      return DropdownMenuItem(value: provider, child: Text(provider));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        payment.provider = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removePayment(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: payment.amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: '₹',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (value) {
                setState(() {
                  payment.amount = value.isEmpty
                      ? null
                      : double.tryParse(value);
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: payment.txnIdController,
              decoration: const InputDecoration(
                labelText: 'Transaction ID (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: payment.settlementDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          payment.settlementDate = date;
                          payment.settlementDateController.text =
                              DateFormat('d MMM yyyy').format(date);
                        });
                      }
                    },
                    child: Text(
                      payment.settlementDateController.text.isEmpty
                          ? 'Select Settlement Date'
                          : payment.settlementDateController.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: payment.notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class QrPaymentRow {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController txnIdController = TextEditingController();
  final TextEditingController settlementDateController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String? provider;
  double? amount;
  DateTime? settlementDate;

  QrPaymentRow();

  void dispose() {
    amountController.dispose();
    txnIdController.dispose();
    settlementDateController.dispose();
    notesController.dispose();
  }
}

