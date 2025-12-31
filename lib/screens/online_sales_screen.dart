import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/online_sale.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';

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
  bool _showValidationErrors = false;
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
            if (sale.notes != null) {
              row.notesController.text = sale.notes!;
            }
            row._calculateNet();
            
            if (sale.id != null) {
              row.id = sale.id!;
              _existingSaleIds.add(sale.id!);
            }
            _sales.add(row);
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

  Future<void> _removeSale(int index) async {
    final sale = _sales[index];
    final hasValue = sale.gross != null && sale.gross! > 0;
    
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
        await _dbService.deleteOnlineSale(sale.id!);
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

    bool hasValidationErrors = false;
    for (var saleRow in _sales) {
      if (saleRow.gross != null && saleRow.gross! > 0) {
        final missingPlatform = saleRow.platform == null || saleRow.platform!.isEmpty;
        if (missingPlatform) {
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
          SnackBar(content: Text('Unable to save online sales. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
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
                        'Total Online Sales:',
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
    final requiresFields = sale.gross != null && sale.gross! > 0;
    final showPlatformError = _showValidationErrors &&
        requiresFields &&
        (sale.platform == null || sale.platform!.isEmpty);
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
                    decoration: InputDecoration(
                      labelText: 'Platform',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: showPlatformError ? 'Select platform' : null,
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
            TextField(
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
  final TextEditingController notesController = TextEditingController();
  String? platform;
  double? gross;
  double? commission;
  String? id; // Track if this row is saved in database

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
    notesController.dispose();
  }
}

