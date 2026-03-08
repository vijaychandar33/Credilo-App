import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/qr_payment.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/closing_cycle_service.dart';
import '../utils/error_message_helper.dart';
import '../utils/unsaved_changes_dialog.dart';
import 'upi_management_screen.dart';

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
  bool _showValidationErrors = false;
  bool _isDirty = false;
  final List<String> _existingPaymentIds = []; // Track existing payment IDs
  List<String> _providers = []; // Names for dropdown: configured + "Others"
  Map<String, String> _providerIdByName = {}; // name -> id for saving with provider_id
  bool _useCustomClosing = false;
  int _closingHour = 0;
  int _closingMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadClosingCycleSettings() async {
    final branchId = _authService.currentBranch?.id ?? '';
    if (branchId.isEmpty) return;
    final useCustom = await ClosingCycleService.isCustomClosingEnabled(branchId);
    final hour = await ClosingCycleService.getClosingHour(branchId);
    final minute = await ClosingCycleService.getClosingMinute(branchId);
    if (mounted) {
      setState(() {
        _useCustomClosing = useCustom;
        _closingHour = hour;
        _closingMinute = minute;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadClosingCycleSettings();
      final branch = _authService.currentBranch;
      if (branch == null) {
        setState(() {
          _isLoading = false;
          _isDirty = false;
          _providers = ['Others'];
          _providerIdByName = {};
          _payments.clear();
          _payments.add(QrPaymentRow());
        });
        return;
      }

      final payments = await _dbService.getQrPayments(widget.selectedDate, branch.id);
      final upiProviders = await _dbService.getUpiProviders(branch.id);
      final providerIdByName = {
        for (var p in upiProviders) if (p.id != null) p.name: p.id!,
      };
      final providerIdToName = {
        for (var p in upiProviders) if (p.id != null) p.id!: p.name,
      };
      final providerNames = upiProviders.map((p) => p.name).where((n) => n.toLowerCase() != 'others').toList();
      providerNames.add('Others');

      // Migrate payments if needed (outside setState for async operations)
      for (var payment in payments) {
        if (_useCustomClosing &&
            payment.amount != null &&
            payment.amountBeforeMidnight == null &&
            payment.amountAfterMidnight == null &&
            payment.id != null) {
          try {
            final updatedPayment = QrPayment(
              id: payment.id,
              date: payment.date,
              userId: payment.userId,
              branchId: payment.branchId,
              providerId: payment.providerId,
              provider: payment.provider,
              amount: null,
              amountBeforeMidnight: payment.amount,
              amountAfterMidnight: null,
              notes: payment.notes,
              createdAt: payment.createdAt,
            );
            await _dbService.updateQrPayment(updatedPayment);
          } catch (e) {
            debugPrint('Error migrating payment amount: $e');
          }
        }
      }
      final updatedPayments = payments.isNotEmpty
          ? await _dbService.getQrPayments(widget.selectedDate, branch.id)
          : <QrPayment>[];

      setState(() {
        _isDirty = false;
        _payments.clear();
        _existingPaymentIds.clear();
        _providers = List.from(providerNames);
        _providerIdByName = providerIdByName;

        for (var payment in updatedPayments) {
          final row = QrPaymentRow();
          row.provider = (payment.providerId != null &&
                  providerIdToName.containsKey(payment.providerId))
              ? providerIdToName[payment.providerId]!
              : payment.provider;
          row.isProviderLocked = true;
          row.providerLabel = row.provider;

          if (_useCustomClosing) {
            if (payment.amountBeforeMidnight != null) {
              row.amountBeforeMidnightController.text = payment.amountBeforeMidnight!.toStringAsFixed(2);
              row.amountBeforeMidnight = payment.amountBeforeMidnight;
            }
            if (payment.amountAfterMidnight != null) {
              row.amountAfterMidnightController.text = payment.amountAfterMidnight!.toStringAsFixed(2);
              row.amountAfterMidnight = payment.amountAfterMidnight;
            }
            if (payment.amount != null &&
                payment.amountBeforeMidnight == null &&
                payment.amountAfterMidnight == null) {
              row.amountBeforeMidnightController.text = payment.amount!.toStringAsFixed(2);
              row.amountBeforeMidnight = payment.amount;
            }
          } else {
            if (payment.amount != null) {
              row.amountController.text = payment.amount!.toStringAsFixed(2);
              row.amount = payment.amount;
            } else if (payment.amountBeforeMidnight != null || payment.amountAfterMidnight != null) {
              final total = (payment.amountBeforeMidnight ?? 0) + (payment.amountAfterMidnight ?? 0);
              row.amountController.text = total.toStringAsFixed(2);
              row.amount = total;
            }
          }
          if (payment.notes != null) {
            row.notesController.text = payment.notes!;
          }
          if (payment.id != null) {
            row.id = payment.id!;
            _existingPaymentIds.add(payment.id!);
          }
          _payments.add(row);
        }

        // Add one empty row per configured provider that has no entry yet (like Card Sales)
        for (var p in upiProviders) {
          final hasEntry = _payments.any((row) => row.provider == p.name);
          if (hasEntry) continue;
          final row = QrPaymentRow()
            ..provider = p.name
            ..isProviderLocked = true
            ..providerLabel = p.name;
          _payments.add(row);
        }

        if (_payments.isEmpty) {
          _payments.add(QrPaymentRow());
        }
      });
    } catch (e) {
      debugPrint('Error loading QR payments: $e');
      setState(() {
        _isDirty = false;
        _providers = _providers.isEmpty ? ['Others'] : _providers;
        _providerIdByName = {};
        _payments.clear();
        _payments.add(QrPaymentRow());
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isDirty = false;
      });
    }
  }

  void _addNewPayment() {
    setState(() {
      _isDirty = true;
      _payments.add(QrPaymentRow());
    });
  }

  Future<void> _removePayment(int index) async {
    final payment = _payments[index];
    final hasValue = _useCustomClosing
        ? ((payment.amountBeforeMidnight != null && payment.amountBeforeMidnight! > 0) ||
           (payment.amountAfterMidnight != null && payment.amountAfterMidnight! > 0))
        : (payment.amount != null && payment.amount! > 0);
    
    if (hasValue) {
      final confirmed = await showDeleteConfirmationDialog(
        context,
        title: 'Delete Payment',
        message: 'Are you sure you want to delete this payment?',
      );
      if (!confirmed) return;
    }
    
    // If this row was saved to database, delete it
    final branch = _authService.currentBranch;
    if (payment.id != null) {
      try {
        await _dbService.deleteQrPayment(payment.id!);
        _existingPaymentIds.remove(payment.id!);
        
        // Recalculate and update the total after deletion
        if (branch != null) {
          final calculatedTotal = await _getTotalPayments();
          await _dbService.upsertQrPaymentCalculatedTotal(
            widget.selectedDate,
            branch.id,
            calculatedTotal,
          );
        }
      } catch (e) {
        debugPrint('Error deleting payment from database: $e');
      }
    }
    
    setState(() {
      _isDirty = true;
      _payments.removeAt(index);
      if (_payments.isEmpty) {
        _addNewPayment();
      }
    });
  }

  double _getTotalPaymentsSync() {
    if (!_useCustomClosing) {
      // Simple sum when custom closing is disabled
    return _payments.fold(0.0, (sum, payment) => sum + (payment.amount ?? 0));
    }
    
    // When custom closing is enabled, calculate current day's amounts
    double currentDayBeforeMidnight = 0.0;
    double currentDayAfterMidnight = 0.0;
    
    // Sum current day's amounts
    for (var payment in _payments) {
      currentDayBeforeMidnight += payment.amountBeforeMidnight ?? 0;
      currentDayAfterMidnight += payment.amountAfterMidnight ?? 0;
    }
    
    // For now, return the sum of current day's amounts
    // The previous day's after-midnight will be loaded separately
    return currentDayBeforeMidnight + currentDayAfterMidnight;
  }

  Future<double> _getPreviousDayAfterMidnight() async {
    if (!_useCustomClosing) {
      return 0.0;
    }
    
    final branch = _authService.currentBranch;
    if (branch == null) {
      return 0.0;
    }
    
    final previousDate = widget.selectedDate.subtract(const Duration(days: 1));
    final previousDayPayments = await _dbService.getQrPayments(previousDate, branch.id);
    
    double previousDayAfterMidnight = 0.0;
    for (var payment in previousDayPayments) {
      previousDayAfterMidnight += payment.amountAfterMidnight ?? 0;
    }
    
    return previousDayAfterMidnight;
  }

  Future<double> _getTotalPayments() async {
    if (!_useCustomClosing) {
      // Simple sum when custom closing is disabled
      return _getTotalPaymentsSync();
    }
    
    // When custom closing is enabled, calculate using the formula:
    // Total = (Before 12 AM sales of current day) - (After 12 AM sales of previous day) + (After 12 AM sales of current day)
    
    double currentDayBeforeMidnight = 0.0;
    double currentDayAfterMidnight = 0.0;
    
    // Sum current day's amounts
    for (var payment in _payments) {
      currentDayBeforeMidnight += payment.amountBeforeMidnight ?? 0;
      currentDayAfterMidnight += payment.amountAfterMidnight ?? 0;
    }
    
    // Get previous day's after-midnight sales
    final previousDayAfterMidnight = await _getPreviousDayAfterMidnight();
    
    // Formula: (Before 12 AM of current day) - (After 12 AM of previous day) + (After 12 AM of current day)
    return currentDayBeforeMidnight - previousDayAfterMidnight + currentDayAfterMidnight;
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
    final hasAmount = _useCustomClosing
        ? _payments.any((payment) => 
            (payment.amountBeforeMidnight != null && payment.amountBeforeMidnight! > 0) ||
            (payment.amountAfterMidnight != null && payment.amountAfterMidnight! > 0))
        : _payments.any((payment) => payment.amount != null && payment.amount! > 0);
    
    if (!hasAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one payment with amount')),
      );
      return;
    }

    // Validate all payments with amounts have providers
    bool hasValidationErrors = false;
    for (var paymentRow in _payments) {
      final hasAmountValue = _useCustomClosing
          ? ((paymentRow.amountBeforeMidnight != null && paymentRow.amountBeforeMidnight! > 0) ||
             (paymentRow.amountAfterMidnight != null && paymentRow.amountAfterMidnight! > 0))
          : (paymentRow.amount != null && paymentRow.amount! > 0);
      
      if (hasAmountValue) {
        final missingProvider = paymentRow.provider == null || paymentRow.provider!.isEmpty;
        if (missingProvider) {
          hasValidationErrors = true;
        }
      }
    }

    if (hasValidationErrors) {
      setState(() {
        _showValidationErrors = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment provider is required for all entries with amounts')),
      );
      return;
    } else if (_showValidationErrors) {
      setState(() {
        _showValidationErrors = false;
      });
    }

    setState(() {
      _isSaving = true;
    });

    try {
      int savedCount = 0;
      List<String> errors = [];

      // Delete existing payments for this date to avoid duplicates
      for (var paymentId in _existingPaymentIds) {
        try {
          await _dbService.deleteQrPayment(paymentId);
          debugPrint('Deleted existing QR payment: $paymentId');
        } catch (e) {
          debugPrint('Error deleting existing QR payment: $e');
        }
      }

      // Save payments
      for (var paymentRow in _payments) {
        final hasAmount = _useCustomClosing
            ? (paymentRow.amountBeforeMidnight != null && paymentRow.amountBeforeMidnight! > 0) ||
              (paymentRow.amountAfterMidnight != null && paymentRow.amountAfterMidnight! > 0)
            : (paymentRow.amount != null && paymentRow.amount! > 0);
        
        if (hasAmount) {
          if (paymentRow.provider == null || paymentRow.provider!.isEmpty) {
            errors.add('Payment provider is required');
            continue; // Skip if provider is not selected
          }

          try {
            final providerId = _providerIdByName[paymentRow.provider!];
            final payment = QrPayment(
              date: widget.selectedDate,
              userId: user.id,
              branchId: branch.id,
              providerId: providerId,
              provider: paymentRow.provider!,
              amount: _useCustomClosing ? null : paymentRow.amount,
              amountBeforeMidnight: _useCustomClosing ? paymentRow.amountBeforeMidnight : null,
              amountAfterMidnight: _useCustomClosing ? paymentRow.amountAfterMidnight : null,
              notes: paymentRow.notesController.text.trim().isEmpty
                  ? null
                  : paymentRow.notesController.text.trim(),
            );

            debugPrint('Saving QR payment: ${payment.toJson()}');
            await _dbService.saveQrPayment(payment);
            savedCount++;
            debugPrint('QR payment saved successfully');
          } catch (e) {
            debugPrint('Error saving QR payment: $e');
            errors.add(ErrorMessageHelper.getUserFriendlyError(e));
          }
        }
      }

      // Only reload data if we successfully saved at least one payment
      if (savedCount > 0) {
      await _loadData();
        
        // Calculate and store the total in the database
        final calculatedTotal = await _getTotalPayments();
        await _dbService.upsertQrPaymentCalculatedTotal(
          widget.selectedDate,
          branch.id,
          calculatedTotal,
        );
      }

      if (mounted) {
        if (savedCount > 0) setState(() => _isDirty = false);
        if (savedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$savedCount payment(s) saved successfully${errors.isNotEmpty ? '. ${errors.length} error(s)' : ''}'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (errors.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No payments saved. Errors: ${errors.join(", ")}'),
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No payments to save. Please add at least one payment with amount and provider')),
          );
        }
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save UPI payments. $errorMessage')),
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
          title: Text('UPI - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await showUnsavedChangesDialog(context);
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('UPI - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        actions: [
          if (_authService.canAccessManagementInCurrentBranch)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UpiManagementScreen(),
                  ),
                ).then((_) {
                  _loadData();
                });
              },
              tooltip: 'Manage UPI Providers',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _payments.length + (_useCustomClosing ? 2 : 1),
              itemBuilder: (context, index) {
                // Show reference card for yesterday's closing at the top
                if (_useCustomClosing && index == 0) {
                  return _buildYesterdayReferenceCard();
                }
                
                // Adjust index for payment rows
                final paymentIndex = _useCustomClosing ? index - 1 : index;
                
                if (paymentIndex == _payments.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addNewPayment,
                      icon: const Icon(Icons.add),
                      label: const Text('Add UPI Payment'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }
                return _buildPaymentRow(paymentIndex);
              },
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
                    color: AppColors.overlay,
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
                        'Total UPI Payments:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _useCustomClosing
                          ? FutureBuilder<double>(
                              future: _getTotalPayments(),
                              builder: (context, snapshot) {
                                final total = snapshot.data ?? _getTotalPaymentsSync();
                                return Text(
                                  CurrencyFormatter.format(total),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                );
                              },
                            )
                          : Text(
                              CurrencyFormatter.format(_getTotalPaymentsSync()),
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
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildYesterdayReferenceCard() {
    String closingTimeText = '';
    if (_useCustomClosing) {
      final time = TimeOfDay(hour: _closingHour, minute: _closingMinute);
      closingTimeText = time.format(context);
    }
    
    final previousDate = widget.selectedDate.subtract(const Duration(days: 1));
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yesterday closing before $closingTimeText',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  DateFormat('d MMM yyyy').format(previousDate),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            FutureBuilder<double>(
              future: _getPreviousDayAfterMidnight(),
              builder: (context, snapshot) {
                final amount = snapshot.data ?? 0.0;
                return Text(
                  CurrencyFormatter.format(amount),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildProviderDropdownItems(String? selectedProvider) {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    for (final name in _providers) {
      if (seen.add(name)) {
        items.add(DropdownMenuItem(value: name, child: Text(name)));
      }
    }
    if (selectedProvider != null &&
        selectedProvider.isNotEmpty &&
        !seen.contains(selectedProvider)) {
      items.add(DropdownMenuItem(value: selectedProvider, child: Text(selectedProvider)));
    }
    return items;
  }

  Widget _buildPaymentRow(int index) {
    final payment = _payments[index];
    final requiresFields = _useCustomClosing
        ? ((payment.amountBeforeMidnight != null && payment.amountBeforeMidnight! > 0) ||
           (payment.amountAfterMidnight != null && payment.amountAfterMidnight! > 0))
        : (payment.amount != null && payment.amount! > 0);
    final showProviderError = _showValidationErrors &&
        requiresFields &&
        (payment.provider == null || payment.provider!.isEmpty);
    
    String closingTimeText = '';
    if (_useCustomClosing) {
      final time = TimeOfDay(hour: _closingHour, minute: _closingMinute);
      closingTimeText = time.format(context);
    }
    
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
                  child: payment.isProviderLocked
                      ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Payment Provider',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(payment.providerLabel ?? payment.provider ?? 'Provider'),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: payment.provider != null && payment.provider!.isNotEmpty
                              ? payment.provider
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Payment Provider',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: showProviderError ? 'Select provider' : null,
                            errorBorder: showProviderError
                                ? OutlineInputBorder(
                                    borderSide: const BorderSide(color: AppColors.error, width: 2),
                                  )
                                : null,
                            focusedErrorBorder: showProviderError
                                ? OutlineInputBorder(
                                    borderSide: const BorderSide(color: AppColors.error, width: 2),
                                  )
                                : null,
                          ),
                          items: _buildProviderDropdownItems(payment.provider),
                          onChanged: (value) {
                            setState(() {
                              _isDirty = true;
                              payment.provider = value;
                              if (value != null && value.isNotEmpty && _showValidationErrors) {
                                bool allValid = true;
                                for (var p in _payments) {
                                  final hasAmountValue = _useCustomClosing
                                      ? ((p.amountBeforeMidnight != null && p.amountBeforeMidnight! > 0) ||
                                         (p.amountAfterMidnight != null && p.amountAfterMidnight! > 0))
                                      : (p.amount != null && p.amount! > 0);
                                  if (hasAmountValue && (p.provider == null || p.provider!.isEmpty)) {
                                    allValid = false;
                                    break;
                                  }
                                }
                                if (allValid) _showValidationErrors = false;
                              }
                            });
                          },
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _removePayment(index),
                  tooltip: 'Delete',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_useCustomClosing) ...[
              TextField(
                controller: payment.amountBeforeMidnightController,
                decoration: const InputDecoration(
                  labelText: 'Sales until 12 AM',
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
                    _isDirty = true;
                    payment.amountBeforeMidnight = value.isEmpty
                        ? null
                        : double.tryParse(value);
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: payment.amountAfterMidnightController,
                decoration: InputDecoration(
                  labelText: 'Sales until $closingTimeText',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixText: '₹',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                    payment.amountAfterMidnight = value.isEmpty
                        ? null
                        : double.tryParse(value);
                  });
                },
              ),
            ] else ...[
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
                  _isDirty = true;
                  payment.amount = value.isEmpty
                      ? null
                      : double.tryParse(value);
                });
              },
            ),
              ],
            const SizedBox(height: 8),
            TextField(
              controller: payment.notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _isDirty = true),
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
  final TextEditingController amountBeforeMidnightController = TextEditingController();
  final TextEditingController amountAfterMidnightController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String? provider;
  bool isProviderLocked = false;
  String? providerLabel;
  double? amount; // Used when custom closing is disabled
  double? amountBeforeMidnight; // Sales before 12 AM
  double? amountAfterMidnight; // Sales after 12 AM until closing time
  String? id; // Track if this row is saved in database

  QrPaymentRow();

  void dispose() {
    amountController.dispose();
    amountBeforeMidnightController.dispose();
    amountAfterMidnightController.dispose();
    notesController.dispose();
  }
}

