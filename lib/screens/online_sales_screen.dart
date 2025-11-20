import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/online_sale.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class OnlineSalesScreen extends StatefulWidget {
  final DateTime selectedDate;

  const OnlineSalesScreen({super.key, required this.selectedDate});

  @override
  State<OnlineSalesScreen> createState() => _OnlineSalesScreenState();
}

class _OnlineSalesScreenState extends State<OnlineSalesScreen> {
  final List<OnlineSaleRow> _sales = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  final List<String> _existingSaleIds = []; // Track existing sale IDs
  final List<String> _platforms = [
    'Swiggy',
    'Zomato',
    'Own Delivery',
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
        _addNewSale();
        return;
      }

      final sales = await _dbService.getOnlineSales(widget.selectedDate, branch.id);
      
      if (sales.isNotEmpty) {
        setState(() {
          _sales.clear();
          _existingSaleIds.clear();
          
          for (var sale in sales) {
            final row = OnlineSaleRow();
            row.platform = sale.platform;
            row.grossController.text = sale.gross.toStringAsFixed(2);
            row.gross = sale.gross;
            if (sale.commission != null) {
              row.commissionController.text = sale.commission!.toStringAsFixed(2);
              row.commission = sale.commission;
            }
            row.netController.text = sale.net.toStringAsFixed(2);
            if (sale.settlementDate != null) {
              row.settlementDate = sale.settlementDate;
              row.settlementDateController.text = DateFormat('d MMM yyyy').format(sale.settlementDate!);
            }
            // Note: ordersCount is not stored in the model, so we skip it
            if (sale.notes != null) {
              row.notesController.text = sale.notes!;
            }
            // Settlement status is not in the model, default to 'Pending'
            row._calculateNet();
            
            _sales.add(row);
            if (sale.id != null) {
              _existingSaleIds.add(sale.id!);
            }
          }
        });
      } else {
        _addNewSale();
      }
    } catch (e) {
      debugPrint('Error loading online sales: $e');
      _addNewSale();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addNewSale() {
    setState(() {
      _sales.add(OnlineSaleRow());
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
    return _sales.fold(0.0, (sum, sale) => sum + (sale.gross ?? 0));
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

    // Validate that at least one sale has gross amount
    if (!_sales.any((sale) => sale.gross != null && sale.gross! > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one sale with gross amount')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Delete existing sales for this date to avoid duplicates
      for (var saleId in _existingSaleIds) {
        await _dbService.deleteOnlineSale(saleId);
      }
      
      for (var saleRow in _sales) {
        if (saleRow.gross != null && saleRow.gross! > 0) {
          if (saleRow.platform == null || saleRow.platform!.isEmpty) {
            continue; // Skip if platform is not selected
          }

          final sale = OnlineSale(
            date: widget.selectedDate,
            userId: user.id,
            branchId: branch.id,
            platform: saleRow.platform!,
            gross: saleRow.gross!,
            commission: saleRow.commission,
            net: double.parse(saleRow.netController.text),
            settlementDate: saleRow.settlementDate,
            notes: saleRow.notesController.text.trim().isEmpty
                ? null
                : saleRow.notesController.text.trim(),
          );

          await _dbService.saveOnlineSale(sale);
        }
      }

      // Reload data to get fresh IDs
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Online sales saved successfully')),
        );
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving online sales: $e')),
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
          title: Text('Online Sales - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Online Sales - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
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
                      label: const Text('Add Online Sale'),
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
                      'Total Online Sales:',
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
                    initialValue: sale.platform,
                    decoration: const InputDecoration(
                      labelText: 'Platform',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _platforms.map((platform) {
                      return DropdownMenuItem(value: platform, child: Text(platform));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        sale.platform = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _removeSale(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sale.grossController,
                    decoration: const InputDecoration(
                      labelText: 'Gross Sales',
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
                        sale.gross = value.isEmpty
                            ? null
                            : double.tryParse(value);
                        sale._calculateNet();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: sale.commissionController,
                    decoration: const InputDecoration(
                      labelText: 'Commission',
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
                        sale.commission = value.isEmpty
                            ? null
                            : double.tryParse(value);
                        sale._calculateNet();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sale.netController,
                    decoration: const InputDecoration(
                      labelText: 'Net Settlement',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '₹',
                      filled: true,
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: sale.ordersCountController,
                    decoration: const InputDecoration(
                      labelText: 'Orders Count (optional)',
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
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: sale.settlementStatus,
                    decoration: const InputDecoration(
                      labelText: 'Settlement Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: ['Pending', 'Settled'].map((status) {
                      return DropdownMenuItem(value: status, child: Text(status));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        sale.settlementStatus = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: sale.settlementDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          sale.settlementDate = date;
                          sale.settlementDateController.text =
                              DateFormat('d MMM yyyy').format(date);
                        });
                      }
                    },
                    child: Text(
                      sale.settlementDateController.text.isEmpty
                          ? 'Select Settlement Date'
                          : sale.settlementDateController.text,
                    ),
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

class OnlineSaleRow {
  final TextEditingController grossController = TextEditingController();
  final TextEditingController commissionController = TextEditingController();
  final TextEditingController netController = TextEditingController();
  final TextEditingController ordersCountController = TextEditingController();
  final TextEditingController settlementDateController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String? platform;
  double? gross;
  double? commission;
  DateTime? settlementDate;
  String? settlementStatus = 'Pending';

  OnlineSaleRow();

  void _calculateNet() {
    final grossValue = gross ?? 0;
    final commissionValue = commission ?? 0;
    final net = grossValue - commissionValue;
    netController.text = net.toStringAsFixed(2);
  }

  void dispose() {
    grossController.dispose();
    commissionController.dispose();
    netController.dispose();
    ordersCountController.dispose();
    settlementDateController.dispose();
    notesController.dispose();
  }
}

