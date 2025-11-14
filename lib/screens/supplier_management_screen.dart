import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../models/credit_expense.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'supplier_detail_screen.dart';
import 'supplier_edit_screen.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key});

  @override
  State<SupplierManagementScreen> createState() => _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<Supplier> _suppliers = [];
  Map<String, double> _supplierTotals = {}; // supplier name -> total unpaid
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) {
        setState(() {
          _suppliers = [];
          _supplierTotals = {};
        });
        return;
      }

      final suppliers = await _dbService.getSuppliers(branch.businessId);
      
      // Calculate total unpaid for each supplier
      Map<String, double> totals = {};
      for (var supplier in suppliers) {
        final expenses = await _dbService.getCreditExpensesBySupplier(
          supplier.name,
          branch.businessId,
        );
        final unpaidTotal = expenses
            .where((e) => e.status == CreditExpenseStatus.unpaid)
            .fold(0.0, (sum, e) => sum + e.amount);
        totals[supplier.name] = unpaidTotal;
      }
      
      setState(() {
        _suppliers = suppliers;
        _supplierTotals = totals;
      });
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading suppliers: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addSupplier() async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (context) => _AddSupplierDialog(),
    );

    if (result != null) {
      try {
        await _dbService.saveSupplier(result);
        _loadSuppliers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Supplier added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding supplier: $e')),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _suppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.business, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No suppliers yet',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add a supplier to get started',
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _suppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = _suppliers[index];
                            final totalRemaining = _supplierTotals[supplier.name] ?? 0.0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SupplierDetailScreen(supplier: supplier),
                                    ),
                                  ).then((_) => _loadSuppliers()); // Reload to refresh totals
                                },
                                onLongPress: () {
                                  // Long press to edit
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SupplierEditScreen(supplier: supplier),
                                    ),
                                  ).then((result) {
                                    if (result == true) {
                                      _loadSuppliers(); // Reload if edited or deleted
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              supplier.name,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '₹${totalRemaining.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: totalRemaining > 0
                                                  ? Colors.orange
                                                  : Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Total Remaining',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      if (supplier.contact != null && supplier.contact!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              supplier.contact!,
                                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (supplier.address != null && supplier.address!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                supplier.address!,
                                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
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
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addSupplier,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Supplier'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AddSupplierDialog extends StatefulWidget {
  @override
  State<_AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<_AddSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _authService = AuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Supplier'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter supplier name';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact (optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final branch = _authService.currentBranch;
              if (branch == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No branch selected')),
                );
                return;
              }
              final supplier = Supplier(
                name: _nameController.text.trim(),
                contact: _contactController.text.trim().isEmpty
                    ? null
                    : _contactController.text.trim(),
                address: _addressController.text.trim().isEmpty
                    ? null
                    : _addressController.text.trim(),
                businessId: branch.businessId,
              );
              Navigator.pop(context, supplier);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

