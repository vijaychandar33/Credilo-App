import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_colors.dart';
import '../models/branch.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/error_message_helper.dart';
import '../utils/closing_cycle_service.dart';
import 'branch_what_to_show_screen.dart';
import 'fixed_expense_screen.dart';

class BranchDetailScreen extends StatefulWidget {
  final Branch branch;

  const BranchDetailScreen({super.key, required this.branch});

  @override
  State<BranchDetailScreen> createState() => _BranchDetailScreenState();
}

class _BranchDetailScreenState extends State<BranchDetailScreen> {
  final _detailsFormKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late Branch _branch;
  late String _savedName;
  late String _savedLocation;
  late BranchStatus _status;
  bool _isSaving = false;
  bool _isEditingDetails = false;
  bool _isSavingStatus = false;
  bool _useCustomClosing = false;
  int _closingHour = 1;
  int _closingMinute = 0;
  bool _closingCycleLoading = true;

  @override
  void initState() {
    super.initState();
    _branch = widget.branch;
    _savedName = widget.branch.name;
    _savedLocation = widget.branch.location;
    _nameController = TextEditingController(text: _savedName);
    _locationController = TextEditingController(text: _savedLocation);
    _status = widget.branch.status;
    _loadClosingCycle();
  }

  Future<void> _loadClosingCycle() async {
    final cycle = await ClosingCycleService.getBranchClosingCycleOrDefault(_branch.id);
    if (mounted) {
      setState(() {
        _useCustomClosing = cycle.useCustomClosing;
        _closingHour = cycle.closingHour == 0 ? 1 : cycle.closingHour;
        _closingMinute = cycle.closingMinute;
        _closingCycleLoading = false;
      });
    }
  }

  Future<void> _showClosingTimePicker() async {
    final initialTime = TimeOfDay(hour: _closingHour, minute: _closingMinute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select closing time (1:00 AM - 11:00 PM)',
    );
    if (picked != null && picked.hour != 0) {
      setState(() {
        _closingHour = picked.hour;
        _closingMinute = picked.minute;
      });
      await ClosingCycleService.setClosingTime(_branch.id, _closingHour, _closingMinute);
    } else if (picked != null && picked.hour == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Closing time cannot be 12:00 AM. Use 1:00 AM - 11:00 PM.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _saveDetails() async {
    if (!_detailsFormKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updated = Branch(
        id: _branch.id,
        businessId: _branch.businessId,
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        status: _status,
        createdAt: _branch.createdAt,
      );
      await DatabaseService().updateBranch(updated);

      await AuthService().refreshBranches();
      final current = AuthService().currentBranch;
      if (current?.id == updated.id) {
        AuthService().setCurrentBranch(updated);
      }

      if (mounted) {
        setState(() {
          _branch = updated;
          _savedName = updated.name;
          _savedLocation = updated.location;
          _isEditingDetails = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch details updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageHelper.getUserFriendlyError(e)),
            backgroundColor: AppColors.error,
          ),
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

  Future<void> _saveStatus(BranchStatus nextStatus) async {
    setState(() {
      _isSavingStatus = true;
    });
    try {
      final updated = Branch(
        id: _branch.id,
        businessId: _branch.businessId,
        name: _savedName,
        location: _savedLocation,
        status: nextStatus,
        createdAt: _branch.createdAt,
      );
      await DatabaseService().updateBranch(updated);

      await AuthService().refreshBranches();
      final current = AuthService().currentBranch;
      if (current?.id == updated.id) {
        AuthService().setCurrentBranch(updated);
      }

      if (mounted) {
        setState(() {
          _branch = updated;
          _status = nextStatus;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch status updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageHelper.getUserFriendlyError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingStatus = false;
        });
      }
    }
  }

  Future<void> _copyBranchId() async {
    await Clipboard.setData(ClipboardData(text: _branch.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Branch ID copied to clipboard'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Branch details (editable name/location + editable status + non-editable branch id)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Branch Details',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (!_isEditingDetails)
                              TextButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _isEditingDetails = true;
                                          _nameController.text = _savedName;
                                          _locationController.text = _savedLocation;
                                        });
                                      },
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                              )
                            else ...[
                              TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _isEditingDetails = false;
                                          _nameController.text = _savedName;
                                          _locationController.text = _savedLocation;
                                        });
                                      },
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _isSaving ? null : _saveDetails,
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Save'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_isEditingDetails)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Form(
                            key: _detailsFormKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch Name',
                                    prefixIcon: Icon(Icons.store),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Name is required';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _locationController,
                                  decoration: const InputDecoration(
                                    labelText: 'Location',
                                    prefixIcon: Icon(Icons.location_on),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Location is required';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        ListTile(
                          leading: const Icon(Icons.store),
                          title: const Text('Branch Name'),
                          subtitle: Text(_savedName),
                        ),
                        ListTile(
                          leading: const Icon(Icons.location_on),
                          title: const Text('Location'),
                          subtitle: Text(_savedLocation),
                        ),
                      ],
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: DropdownButtonFormField<BranchStatus>(
                          key: ValueKey(_status),
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            prefixIcon: Icon(Icons.check_circle_outline),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: BranchStatus.active,
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: BranchStatus.inactive,
                              child: Text('Inactive'),
                            ),
                          ],
                          onChanged: (_isSavingStatus || _isSaving)
                              ? null
                              : (v) async {
                                  if (v == null || v == _status) return;
                                  // Save only status using last saved name/location
                                  await _saveStatus(v);
                                },
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.tag, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Branch ID',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _branch.id,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontFamily: 'monospace',
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _copyBranchId,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Fixed Expenditure Card
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: const Text('Fixed Expenditure'),
                  subtitle: const Text(
                    'Manage recurring expenses like rent, electricity, and other fixed costs',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FixedExpenseScreen(
                            selectedDate: DateTime.now(),
                            branch: _branch,
                          ),
                        ),
                      );
                    },
                ),
              ),
              const SizedBox(height: 24),
              // Custom Closing Cycle (per-branch)
              if (_closingCycleLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.access_time),
                        title: const Text('Custom Closing Cycle'),
                        subtitle: const Text(
                          'Set a custom time when this branch\'s business day ends',
                        ),
                        value: _useCustomClosing,
                        onChanged: (value) async {
                          final dialogContext = context;
                          if (value) {
                            setState(() => _useCustomClosing = true);
                            await ClosingCycleService.setCustomClosingEnabled(_branch.id, true);
                            await _loadClosingCycle();
                            return;
                          }
                          final hasData = await _dbService.hasDataAfterMidnight([_branch.id]);
                          if (!mounted) return;
                          if (hasData) {
                            await showDialog(
                              context: dialogContext, // ignore: use_build_context_synchronously
                              builder: (ctx) => AlertDialog(
                                title: const Text('Cannot Disable Custom Closing'),
                                content: const Text(
                                  'You cannot disable custom closing for this branch because there is data recorded between 12:00 AM and the closing time. Disabling would cause data inconsistencies.\n\n'
                                  'Remove or migrate that data before disabling.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                          setState(() => _useCustomClosing = false);
                          await ClosingCycleService.setCustomClosingEnabled(_branch.id, false);
                        },
                      ),
                      if (_useCustomClosing) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Closing Time'),
                          subtitle: Text(
                            'Entries until ${_formatTime(_closingHour, _closingMinute)} are recorded as previous day',
                          ),
                          trailing: TextButton(
                            onPressed: _showClosingTimePicker,
                            child: Text(
                              _formatTime(_closingHour, _closingMinute),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('What to show'),
                  subtitle: const Text(
                    'Choose which items to show on the home screen for this branch',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BranchWhatToShowScreen(
                          branch: _branch,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }
}
