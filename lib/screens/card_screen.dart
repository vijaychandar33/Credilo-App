import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/card_sale.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'card_machine_management_screen.dart';
import '../utils/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';

class CardScreen extends StatefulWidget {
  final DateTime selectedDate;

  const CardScreen({super.key, required this.selectedDate});

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  final List<CardMachine> _machines = [];
  final List<CardSaleRow> _sales = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  bool _showValidationErrors = false;
  final List<String> _existingSaleIds = []; // Track existing sale IDs

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _machineKey(CardMachine machine) => machine.id ?? '${machine.tid}__${machine.name}';

  String _machineLabel(CardMachine machine) => '${machine.name} (${machine.tid})';

  CardMachine? _findMachineByKey(String? key) {
    if (key == null) return null;
    try {
      return _machines.firstWhere((m) => _machineKey(m) == key);
    } catch (_) {
      return null;
    }
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
            _isLoading = false;
          });
        }
        return;
      }

      // Load machines from backend for this branch
      final machines = await _dbService.getCardMachines(branch.id);
      
      // Load sales for the date
      final sales = await _dbService.getCardSales(widget.selectedDate, branch.id);
      
      final Map<String, CardMachine> machineMap = {
        for (final machine in machines) _machineKey(machine): machine,
      };

      setState(() {
        _sales.clear();
        _existingSaleIds.clear();
        _machines
          ..clear()
          ..addAll(machines);

        final Set<String> machinesWithEntries = {};

        for (var sale in sales) {
          final row = CardSaleRow();
          row.amountController.text = sale.amount.toStringAsFixed(2);
          row.amount = sale.amount;
          if (sale.notes != null) {
            row.notesController.text = sale.notes!;
          }

          CardMachine? machine;
          String? machineKey;
          try {
            if (sale.cardMachineId != null && sale.cardMachineId!.isNotEmpty) {
              machine = _machines.firstWhere((m) => m.id == sale.cardMachineId);
            } else {
              machine = _machines.firstWhere(
                (m) => m.tid == sale.tid && m.name == sale.machineName,
              );
            }
            machineKey = _machineKey(machine);
            machinesWithEntries.add(machineKey);
          } catch (_) {
            machineKey = sale.machineName == 'Others' ? 'others' : null;
          }

          if (machineKey == null) {
            row.selectedMachineId = 'others';
            row.isMachineLocked = true;
            row.machineLabel = '${sale.machineName} (${sale.tid})';
          } else if (machineKey == 'others') {
            row.selectedMachineId = 'others';
            row.isMachineLocked = true;
            row.machineLabel = 'Others';
          } else {
            row.selectedMachineId = machineKey;
            row.isMachineLocked = true;
            final labelMachine = machine ?? machineMap[machineKey];
            row.machineLabel =
                labelMachine != null ? _machineLabel(labelMachine) : sale.machineName;
          }

          _sales.add(row);
          if (sale.id != null) {
            row.id = sale.id!;
            _existingSaleIds.add(sale.id!);
          }
        }

        for (final machine in _machines) {
          final key = _machineKey(machine);
          if (machinesWithEntries.contains(key)) continue;
          if (_sales.any((row) => row.selectedMachineId == key)) continue;
          final row = CardSaleRow()
            ..selectedMachineId = key
            ..isMachineLocked = true
            ..machineLabel = _machineLabel(machine);
          _sales.add(row);
        }

        if (_sales.isEmpty) {
          _sales.add(CardSaleRow());
        }
      });
    } catch (e) {
      debugPrint('Error loading card sales: $e');
      setState(() {
        _sales.clear();
        _sales.add(CardSaleRow());
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addNewSale() {
    setState(() {
      _sales.add(CardSaleRow());
    });
  }

  Future<void> _removeSale(int index) async {
    final sale = _sales[index];
    final hasValue = sale.amount != null && sale.amount! > 0;
    
    if (hasValue) {
      final confirmed = await showDeleteConfirmationDialog(
        context,
        title: 'Delete Sale',
        message: 'Are you sure you want to delete this sale?',
      );
      if (!confirmed) return;
    }
    
    // If this row was saved to database, delete it
    if (sale.id != null) {
      try {
        await _dbService.deleteCardSale(sale.id!);
        _existingSaleIds.remove(sale.id!);
      } catch (e) {
        debugPrint('Error deleting sale from database: $e');
      }
    }
    
    setState(() {
      _sales.removeAt(index);
      if (_sales.isEmpty) {
        _addNewSale();
      }
    });
  }


  double _getTotalSales() {
    return _sales.fold(0.0, (sum, sale) => sum + (sale.amount ?? 0));
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

    // Validate that at least one sale has amount
    if (!_sales.any((sale) => sale.amount != null && sale.amount! > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one sale with amount')),
      );
      return;
    }

    bool hasValidationErrors = false;
    for (var saleRow in _sales) {
      if (saleRow.amount != null && saleRow.amount! > 0) {
        final missingMachine = saleRow.selectedMachineId == null || saleRow.selectedMachineId!.isEmpty;
        if (missingMachine) {
          hasValidationErrors = true;
        }
      }
    }

    if (hasValidationErrors) {
      setState(() {
        _showValidationErrors = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all required fields to save')),
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
      // Delete existing sales for this date to avoid duplicates
      for (var saleId in _existingSaleIds) {
        await _dbService.deleteCardSale(saleId);
      }
      
      for (var saleRow in _sales) {
        if (saleRow.amount != null && saleRow.amount! > 0) {
          // Find the machine
          CardMachine? machine;
          if (saleRow.selectedMachineId == 'others' || saleRow.selectedMachineId == null) {
            machine = CardMachine(name: 'Others', tid: 'Others');
          } else {
            machine = _findMachineByKey(saleRow.selectedMachineId);
            machine ??= _machines.isNotEmpty
                ? _machines.first
                : CardMachine(name: 'Unknown', tid: 'N/A');
          }

          final sale = CardSale(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            cardMachineId: machine.id,
            tid: machine.tid,
            machineName: machine.name,
            amount: saleRow.amount!,
            notes: saleRow.notesController.text.trim().isEmpty
                ? null
                : saleRow.notesController.text.trim(),
          );

          await _dbService.saveCardSale(sale);
        }
      }

      // Reload data to get fresh IDs
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card sales saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save card sales. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
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
          title: Text('Card Sales - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Card Sales - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        actions: [
          if (_authService.canAccessManagementInCurrentBranch)
            IconButton(
              icon: const Icon(Icons.credit_card),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CardMachineManagementScreen(),
                  ),
                ).then((_) {
                  // Reload machines when returning from management screen
                  _loadData();
                });
              },
              tooltip: 'Manage Machines',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sales.length + 1,
              itemBuilder: (context, index) {
                if (index == _sales.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addNewSale,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Card Sale'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }
                return _buildSaleRow(index);
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
                        'Total Card Sales:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(_getTotalSales()),
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
    );
  }

  Widget _buildSaleRow(int index) {
    final sale = _sales[index];
    final requiresFields = sale.amount != null && sale.amount! > 0;
    final showMachineError = _showValidationErrors &&
        requiresFields &&
        (sale.selectedMachineId == null || sale.selectedMachineId!.isEmpty);
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
                  child: sale.isMachineLocked
                      ? InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Machine',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: showMachineError ? 'Select machine' : null,
                          ),
                          child: Text(sale.machineLabel ?? 'Machine'),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: sale.selectedMachineId,
                          decoration: InputDecoration(
                            labelText: 'Machine',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: showMachineError ? 'Select machine' : null,
                          ),
                          items: [
                            ..._machines.map((machine) {
                              final machineKey = _machineKey(machine);
                              return DropdownMenuItem(
                                value: machineKey,
                                child: Text(_machineLabel(machine)),
                              );
                            }),
                            const DropdownMenuItem(
                              value: 'others',
                              child: Text('Others'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              sale.selectedMachineId = value;
                            });
                          },
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _removeSale(index),
                  tooltip: 'Delete transaction',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
                    controller: sale.amountController,
                    decoration: const InputDecoration(
                      labelText: 'Sale Value',
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
                        sale.amount = value.isEmpty
                            ? null
                            : double.tryParse(value);
                      });
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sale.notesController,
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

class CardSaleRow {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String? selectedMachineId;
  double? amount;
  bool isMachineLocked = false;
  String? machineLabel;
  String? id; // Track if this row is saved in database

  CardSaleRow();

  void dispose() {
    amountController.dispose();
    notesController.dispose();
  }
}

