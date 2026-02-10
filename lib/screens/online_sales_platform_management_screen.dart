import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';
import '../models/online_sales_platform.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class OnlineSalesPlatformManagementScreen extends StatefulWidget {
  const OnlineSalesPlatformManagementScreen({super.key});

  @override
  State<OnlineSalesPlatformManagementScreen> createState() => _OnlineSalesPlatformManagementScreenState();
}

class _OnlineSalesPlatformManagementScreenState extends State<OnlineSalesPlatformManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<OnlineSalesPlatform> _platforms = [];
  Set<String> _namesWithSales = {}; // Platform names that have at least one online_sale (cannot delete)
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!_authService.canAccessCardOrUpiManagement()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
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

      final platforms = await _dbService.getOnlineSalesPlatforms(branch.id);
      final namesWithSales = await _dbService.getPlatformNamesWithOnlineSales(branch.id);
      setState(() {
        // "Others" is a fallback option in the app (like Card/UPI), not shown or deletable here
        _platforms = platforms.where((p) => p.name != 'Others').toList();
        _namesWithSales = namesWithSales;
      });
    } catch (e) {
      debugPrint('Error loading online sales platforms: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load platforms. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditDialog({OnlineSalesPlatform? platform}) async {
    final nameController = TextEditingController(text: platform?.name ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(platform == null ? 'Add Platform' : 'Edit Platform'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name *',
            hintText: 'e.g. Swiggy, Zomato, Own Delivery',
            border: OutlineInputBorder(),
          ),
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

                if (platform == null) {
                  await _dbService.saveOnlineSalesPlatform(OnlineSalesPlatform(
                    branchId: branch.id,
                    name: name,
                  ));
                } else {
                  await _dbService.updateOnlineSalesPlatform(OnlineSalesPlatform(
                    id: platform.id,
                    branchId: branch.id,
                    name: name,
                  ));
                }
                if (!mounted) return;
                navigator.pop();
                _loadPlatforms();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(platform == null
                        ? 'Platform added successfully'
                        : 'Platform updated successfully'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Unable to save. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
                );
              }
            },
            child: Text(platform == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  bool _canDeletePlatform(OnlineSalesPlatform platform) {
    return !_namesWithSales.contains(platform.name);
  }

  Future<void> _deletePlatform(OnlineSalesPlatform platform) async {
    if (platform.id == null) return;
    if (!_canDeletePlatform(platform)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete: this platform has sales data. Delete is only allowed when there are no online sales for it.'),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Platform'),
        content: Text('Are you sure you want to delete "${platform.name}"?'),
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
        await _dbService.deleteOnlineSalesPlatform(platform.id!);
        _loadPlatforms();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Platform deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().toLowerCase().contains('sales') || e.toString().toLowerCase().contains('cannot delete')
              ? 'Cannot delete: this platform has sales data.'
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
        title: const Text('Online Sales Platform Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditDialog(),
            tooltip: 'Add Platform',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _platforms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_bag, size: 64, color: AppColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'No platforms added',
                        style: TextStyle(fontSize: 18, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Platform'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _platforms.length,
                  itemBuilder: (context, index) {
                    final platform = _platforms[index];
                    final canDelete = _canDeletePlatform(platform);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.shopping_bag),
                        title: Text(platform.name),
                        subtitle: !canDelete
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Has sales data — cannot delete',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showAddEditDialog(platform: platform),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete,
                                color: canDelete ? AppColors.error : AppColors.textTertiary,
                              ),
                              onPressed: canDelete ? () => _deletePlatform(platform) : null,
                              tooltip: canDelete
                                  ? 'Delete'
                                  : 'Cannot delete: platform has sales data',
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
