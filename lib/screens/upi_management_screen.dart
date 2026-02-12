import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';
import '../models/upi_provider.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class UpiManagementScreen extends StatefulWidget {
  const UpiManagementScreen({super.key});

  @override
  State<UpiManagementScreen> createState() => _UpiManagementScreenState();
}

class _UpiManagementScreenState extends State<UpiManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<UpiProvider> _providers = [];
  Set<String> _providerIdsWithPayments = {}; // provider_id that have at least one qr_payment (cannot delete)
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!_authService.canAccessManagementInCurrentBranch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final branch = _authService.currentBranch;
      if (branch == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No branch selected')),
          );
        }
        return;
      }

      final providers = await _dbService.getUpiProviders(branch.id);
      final providerIdsWithPayments = await _dbService.getProviderIdsWithQrPayments(branch.id);
      setState(() {
        _providers = providers;
        _providerIdsWithPayments = providerIdsWithPayments;
      });
    } catch (e) {
      debugPrint('Error loading UPI providers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load UPI providers. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditDialog({UpiProvider? provider}) async {
    final nameController = TextEditingController(text: provider?.name ?? '');
    final locationController = TextEditingController(text: provider?.location ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(provider == null ? 'Add UPI Provider' : 'Edit UPI Provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'e.g. Paytm, PhonePe, HDFC Bank QR',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }

              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              try {
                final branch = _authService.currentBranch;
                if (branch == null) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('No branch selected')),
                    );
                  }
                  return;
                }

                final name = nameController.text.trim();
                final location = locationController.text.trim().isEmpty
                    ? null
                    : locationController.text.trim();

                if (provider == null) {
                  await _dbService.saveUpiProvider(UpiProvider(
                    branchId: branch.id,
                    name: name,
                    location: location,
                  ));
                } else {
                  await _dbService.updateUpiProvider(UpiProvider(
                    id: provider.id,
                    branchId: branch.id,
                    name: name,
                    location: location,
                  ));
                }
                if (!mounted) return;
                navigator.pop();
                _loadProviders();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(provider == null
                        ? 'UPI provider added successfully'
                        : 'UPI provider updated successfully'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Unable to save. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
                );
              }
            },
            child: Text(provider == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  bool _canDeleteProvider(UpiProvider provider) {
    return provider.id == null || !_providerIdsWithPayments.contains(provider.id);
  }

  Future<void> _deleteProvider(UpiProvider provider) async {
    if (provider.id == null) return;
    if (!_canDeleteProvider(provider)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete: this provider has payment data. Delete is only allowed when there are no UPI payments for it.'),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete UPI Provider'),
        content: Text('Are you sure you want to delete "${provider.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteUpiProvider(provider.id!);
        _loadProviders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('UPI provider deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().toLowerCase().contains('payment') || e.toString().toLowerCase().contains('cannot delete')
              ? 'Cannot delete: this provider has payment data.'
              : 'Unable to delete. ${ErrorMessageHelper.getUserFriendlyError(e)}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UPI Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditDialog(),
            tooltip: 'Add UPI Provider',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _providers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2, size: 64, color: AppColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'No UPI providers added',
                        style: TextStyle(fontSize: 18, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Provider'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _providers.length,
                  itemBuilder: (context, index) {
                    final provider = _providers[index];
                    final canDelete = _canDeleteProvider(provider);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.qr_code_2),
                        title: Text(provider.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (provider.location != null)
                              Text('Location: ${provider.location}'),
                            if (!canDelete)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Has payment data — cannot delete',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showAddEditDialog(provider: provider),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete,
                                color: canDelete ? AppColors.error : AppColors.textTertiary,
                              ),
                              onPressed: canDelete ? () => _deleteProvider(provider) : null,
                              tooltip: canDelete
                                  ? 'Delete'
                                  : 'Cannot delete: provider has payment data',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
