import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';
import '../models/card_sale.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class CardMachineManagementScreen extends StatefulWidget {
  const CardMachineManagementScreen({super.key});

  @override
  State<CardMachineManagementScreen> createState() => _CardMachineManagementScreenState();
}

class _CardMachineManagementScreenState extends State<CardMachineManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<CardMachine> _machines = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
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

      final machines = await _dbService.getCardMachines(branch.id);
      setState(() {
        _machines = machines;
      });
    } catch (e) {
      debugPrint('Error loading card machines: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load machines. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditDialog({CardMachine? machine}) async {
    final nameController = TextEditingController(text: machine?.name ?? '');
    final tidController = TextEditingController(text: machine?.tid ?? '');
    final locationController = TextEditingController(text: machine?.location ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(machine == null ? 'Add Card Machine' : 'Edit Card Machine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Machine Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tidController,
              decoration: const InputDecoration(
                labelText: 'TID *',
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
              if (nameController.text.trim().isEmpty || tidController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name and TID are required')),
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

                final updatedMachine = CardMachine(
                  id: machine?.id,
                  name: nameController.text.trim(),
                  tid: tidController.text.trim(),
                  location: locationController.text.trim().isEmpty
                      ? null
                      : locationController.text.trim(),
                  branchId: branch.id,
                );

                await _dbService.saveCardMachine(updatedMachine);
                if (!mounted) return;
                navigator.pop();
                _loadMachines();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(machine == null
                        ? 'Machine added successfully'
                        : 'Machine updated successfully'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Unable to save machine. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
                );
              }
            },
            child: Text(machine == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMachine(CardMachine machine) async {
    if (machine.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Machine'),
        content: Text('Are you sure you want to delete "${machine.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteCardMachine(machine.id!);
        _loadMachines();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Machine deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to delete machine. ${ErrorMessageHelper.getUserFriendlyError(e)}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Machine Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditDialog(),
            tooltip: 'Add Machine',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _machines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.credit_card, size: 64, color: AppColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'No card machines added',
                        style: TextStyle(fontSize: 18, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Machine'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _machines.length,
                  itemBuilder: (context, index) {
                    final machine = _machines[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.credit_card),
                        title: Text(machine.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TID: ${machine.tid}'),
                            if (machine.location != null)
                              Text('Location: ${machine.location}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showAddEditDialog(machine: machine),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppColors.error),
                              onPressed: () => _deleteMachine(machine),
                              tooltip: 'Delete',
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

