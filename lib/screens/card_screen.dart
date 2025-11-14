import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/card_sale.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'card_machine_management_screen.dart';

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
  final List<String> _existingSaleIds = []; // Track existing sale IDs

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
        _addNewSale();
        return;
      }

      // Load machines from backend for this branch
      final machines = await _dbService.getCardMachines(branch.id);
      
      // Load sales for the date
      final sales = await _dbService.getCardSales(widget.selectedDate, branch.id);
      
      setState(() {
        _sales.clear();
        _existingSaleIds.clear();
        _machines.clear();
        
        // Add machines from backend
        _machines.addAll(machines);
        
        if (sales.isNotEmpty) {
          for (var sale in sales) {
            final row = CardSaleRow();
            row.amountController.text = sale.amount.toStringAsFixed(2);
            row.amount = sale.amount;
            if (sale.txnCount != null) {
              row.txnCountController.text = sale.txnCount.toString();
            }
            if (sale.notes != null) {
              row.notesController.text = sale.notes!;
            }
            
            // Find matching machine
            final machine = _machines.firstWhere(
              (m) => m.tid == sale.tid && m.name == sale.machineName,
              orElse: () => CardMachine(name: sale.machineName, tid: sale.tid),
            );
            if (!_machines.contains(machine)) {
              _machines.add(machine);
            }
            
            // Set machine selection
            row.selectedMachineId = machine.id ?? '${machine.tid}_${machine.name}';
            
            _sales.add(row);
            if (sale.id != null) {
              _existingSaleIds.add(sale.id!);
            }
          }
        } else {
          _addNewSale();
        }
      });
    } catch (e) {
      debugPrint('Error loading card sales: $e');
      _addNewSale();
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

  void _removeSale(int index) {
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
          if (saleRow.selectedMachineId != null) {
            // Try to find by ID first
            try {
              machine = _machines.firstWhere(
                (m) => m.id == saleRow.selectedMachineId,
              );
            } catch (e) {
              // If not found by ID, try to parse the key format: "tid_name"
              final parts = saleRow.selectedMachineId!.split('_');
              if (parts.length >= 2) {
                final tid = parts[0];
                final name = parts.sublist(1).join('_');
                try {
                  machine = _machines.firstWhere(
                    (m) => m.tid == tid && m.name == name,
                  );
                } catch (e) {
                  machine = _machines.isNotEmpty ? _machines.first : CardMachine(name: 'Unknown', tid: 'N/A');
                }
              } else {
                machine = _machines.isNotEmpty ? _machines.first : CardMachine(name: 'Unknown', tid: 'N/A');
              }
            }
          } else if (_machines.isNotEmpty) {
            machine = _machines.first;
          } else {
            // Create a default machine entry if none exists
            machine = CardMachine(name: 'Default', tid: 'N/A');
          }

          final sale = CardSale(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            tid: machine.tid,
            machineName: machine.name,
            amount: saleRow.amount!,
            txnCount: saleRow.txnCountController.text.trim().isEmpty
                ? null
                : int.tryParse(saleRow.txnCountController.text.trim()),
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
          SnackBar(content: Text('Error saving card sales: $e')),
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
          if (_authService.canManageUsers())
            IconButton(
              icon: const Icon(Icons.settings),
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
                      'Total Card Sales:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₹${_getTotalSales().toStringAsFixed(2)}',
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

  Widget _buildSaleRow(int index) {
    final sale = _sales[index];
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
                    initialValue: sale.selectedMachineId,
                    decoration: const InputDecoration(
                      labelText: 'Machine',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _machines.isEmpty
                        ? [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No machines added'),
                            )
                          ]
                        : _machines.map((machine) {
                            final machineKey = machine.id ?? '${machine.tid}_${machine.name}';
                            return DropdownMenuItem(
                              value: machineKey,
                              child: Text('${machine.name} (${machine.tid})'),
                            );
                          }).toList(),
                    onChanged: (value) {
                      setState(() {
                        sale.selectedMachineId = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeSale(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: sale.txnCountController,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Count (optional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
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
  final TextEditingController txnCountController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String? selectedMachineId;
  double? amount;

  CardSaleRow();

  void dispose() {
    amountController.dispose();
    txnCountController.dispose();
    notesController.dispose();
  }
}

