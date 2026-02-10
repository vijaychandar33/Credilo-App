import 'package:flutter/material.dart';
import '../models/branch.dart';
import '../models/supplier.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';

class SupplierEditScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierEditScreen({super.key, required this.supplier});

  @override
  State<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends State<SupplierEditScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;
  late List<Branch> _branches;
  Set<String> _supplyingToBranchIds = {};

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.supplier.name;
    _contactController.text = widget.supplier.contact ?? '';
    _addressController.text = widget.supplier.address ?? '';
    _branches = _getBranches();
    _supplyingToBranchIds = widget.supplier.supplyingBranchIds != null
        ? Set.from(widget.supplier.supplyingBranchIds!)
        : {};
  }

  List<Branch> _getBranches() {
    final owner = _authService.ownerBranches;
    if (owner.isNotEmpty) return List.from(owner);
    if (_authService.userBranches.isNotEmpty) return List.from(_authService.userBranches);
    final cur = _authService.currentBranch;
    return cur != null ? [cur] : [];
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
        supplyingBranchIds: _supplyingToBranchIds.isEmpty
            ? null
            : _supplyingToBranchIds.toList(),
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

  Future<void> _showSupplyingToSheet() async {
    if (_branches.isEmpty) return;
    final current = Set<String>.from(_supplyingToBranchIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        Set<String> temp = Set<String>.from(current);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final allSelected = temp.length == _branches.length;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Supplying to',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('All branches'),
                        value: allSelected,
                        onChanged: (v) {
                          setModalState(() {
                            temp = v == true
                                ? _branches.map((b) => b.id).toSet()
                                : {};
                          });
                        },
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          children: _branches.map((b) {
                            return CheckboxListTile(
                              title: Text(b.name),
                              subtitle: b.location.isNotEmpty ? Text(b.location) : null,
                              value: temp.contains(b.id),
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    temp.add(b.id);
                                  } else {
                                    temp.remove(b.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, current),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context, temp),
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    if (result != null) {
      setState(() => _supplyingToBranchIds = result);
    }
  }

  String _supplyingToLabel() {
    if (_supplyingToBranchIds.isEmpty) return 'All branches';
    if (_supplyingToBranchIds.length == _branches.length) return 'All branches';
    if (_supplyingToBranchIds.length == 1) {
      try {
        final b = _branches.firstWhere((b) => b.id == _supplyingToBranchIds.first);
        return b.name;
      } catch (_) {
        return '1 branch';
      }
    }
    return '${_supplyingToBranchIds.length} branches';
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
                          GestureDetector(
                            onTap: _branches.isEmpty ? null : _showSupplyingToSheet,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Supplying to',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                suffixIcon: _branches.isNotEmpty
                                    ? const Icon(Icons.arrow_drop_down)
                                    : null,
                              ),
                              child: Text(
                                _branches.isEmpty ? 'No branches' : _supplyingToLabel(),
                                style: TextStyle(
                                  color: _branches.isEmpty
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
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

