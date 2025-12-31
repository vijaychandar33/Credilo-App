import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../utils/error_message_helper.dart';

class SupplierEditScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierEditScreen({super.key, required this.supplier});

  @override
  State<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends State<SupplierEditScreen> {
  final DatabaseService _dbService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.supplier.name;
    _contactController.text = widget.supplier.contact ?? '';
    _addressController.text = widget.supplier.address ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedSupplier = Supplier(
        id: widget.supplier.id,
        name: _nameController.text.trim(),
        contact: _contactController.text.trim().isEmpty
            ? null
            : _contactController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        businessId: widget.supplier.businessId,
      );

      await _dbService.updateSupplier(updatedSupplier);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier updated successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update supplier. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            autofocus: false,
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
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
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
                ),
              ],
            ),
    );
  }
}

