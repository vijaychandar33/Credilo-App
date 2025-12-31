import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/due.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/delete_confirmation_dialog.dart';
import '../utils/error_message_helper.dart';

class DueScreen extends StatefulWidget {
  final DateTime selectedDate;

  const DueScreen({super.key, required this.selectedDate});

  @override
  State<DueScreen> createState() => _DueScreenState();
}

class _DueScreenState extends State<DueScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<DueRow> _receivables = [];
  final List<DueRow> _payables = [];
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;
  bool _isLoading = false;
  final List<String> _existingDueIds = []; // Track existing due IDs

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        _addNewReceivable();
        _addNewPayable();
        return;
      }

      final dues = await _dbService.getDues(widget.selectedDate, branch.id);
      
      debugPrint('Loading dues for date ${widget.selectedDate} and branch ${branch.id}: ${dues.length} found');
      
      if (dues.isNotEmpty) {
        setState(() {
          _receivables.clear();
          _payables.clear();
          _existingDueIds.clear();
          
          for (var due in dues) {
            debugPrint('Loading due: ${due.party}, ${due.amount}, type: ${due.type}');
            
            final row = DueRow(type: due.type);
            row.partyController.text = due.party;
            row.amountController.text = due.amount.toStringAsFixed(2);
            row.amount = due.amount;
            if (due.remarks != null) {
              row.remarksController.text = due.remarks!;
            }
            
            if (due.id != null) {
              row.id = due.id!;
              _existingDueIds.add(due.id!);
            }
            
            if (due.type == DueType.receivable) {
              _receivables.add(row);
              debugPrint('Added receivable: ${row.partyController.text}');
            } else {
              _payables.add(row);
              debugPrint('Added payable: ${row.partyController.text}');
            }
          }
          
          debugPrint('Loaded ${_receivables.length} receivables and ${_payables.length} payables');
          
          // If no data loaded, add empty rows
          if (_receivables.isEmpty) {
            _addNewReceivable();
          }
          if (_payables.isEmpty) {
            _addNewPayable();
          }
        });
      } else {
        debugPrint('No dues found for this date');
        _addNewReceivable();
        _addNewPayable();
      }
    } catch (e) {
      debugPrint('Error loading dues: $e');
      _addNewReceivable();
      _addNewPayable();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addNewReceivable() {
    setState(() {
      _receivables.add(DueRow(type: DueType.receivable));
    });
  }

  void _addNewPayable() {
    setState(() {
      _payables.add(DueRow(type: DueType.payable));
    });
  }

  Future<void> _removeReceivable(int index) async {
    final due = _receivables[index];
    final hasValue = due.amount != null && due.amount! > 0;
    
    if (hasValue) {
      final confirmed = await showDeleteConfirmationDialog(
        context,
        title: 'Delete Receivable',
        message: 'Are you sure you want to delete this receivable?',
      );
      if (!confirmed) return;
    }
    
    // If this row was saved to database, delete it
    if (due.id != null) {
      try {
        await _dbService.deleteDue(due.id!);
        _existingDueIds.remove(due.id!);
      } catch (e) {
        debugPrint('Error deleting due from database: $e');
      }
    }
    
    setState(() {
      _receivables.removeAt(index);
      if (_receivables.isEmpty) {
        _addNewReceivable();
      }
    });
  }

  Future<void> _removePayable(int index) async {
    final due = _payables[index];
    final hasValue = due.amount != null && due.amount! > 0;
    
    if (hasValue) {
      final confirmed = await showDeleteConfirmationDialog(
        context,
        title: 'Delete Payable',
        message: 'Are you sure you want to delete this payable?',
      );
      if (!confirmed) return;
    }
    
    // If this row was saved to database, delete it
    if (due.id != null) {
      try {
        await _dbService.deleteDue(due.id!);
        _existingDueIds.remove(due.id!);
      } catch (e) {
        debugPrint('Error deleting due from database: $e');
      }
    }
    
    setState(() {
      _payables.removeAt(index);
      if (_payables.isEmpty) {
        _addNewPayable();
      }
    });
  }

  double _getTotalReceivables() {
    return _receivables.fold(0.0, (sum, due) => sum + (due.amount ?? 0));
  }

  double _getTotalPayables() {
    return _payables.fold(0.0, (sum, due) => sum + (due.amount ?? 0));
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

    setState(() {
      _isSaving = true;
    });

    try {
      int savedCount = 0;
      List<String> errors = [];

      // Delete existing dues for this date to avoid duplicates
      for (var dueId in _existingDueIds) {
        try {
          await _dbService.deleteDue(dueId);
          debugPrint('Deleted existing due: $dueId');
        } catch (e) {
          debugPrint('Error deleting existing due: $e');
        }
      }

      // Save receivables
      for (var dueRow in _receivables) {
        if (dueRow.amount != null && dueRow.amount! > 0) {
          if (dueRow.partyController.text.trim().isEmpty) {
            errors.add('Receivable: Party name is required');
            continue; // Skip if party name is empty
          }

          try {
            final due = Due(
              date: widget.selectedDate,
              userId: user.id,
              branchId: branch.id,
              party: dueRow.partyController.text.trim(),
              amount: dueRow.amount!,
              type: DueType.receivable,
              remarks: dueRow.remarksController.text.trim().isEmpty
                  ? null
                  : dueRow.remarksController.text.trim(),
            );

            debugPrint('Saving receivable: ${due.toJson()}');
            await _dbService.saveDue(due);
            savedCount++;
            debugPrint('Receivable saved successfully');
          } catch (e) {
            debugPrint('Error saving receivable: $e');
            errors.add('Receivable: ${ErrorMessageHelper.getUserFriendlyError(e)}');
          }
        }
      }

      // Save payables
      for (var dueRow in _payables) {
        if (dueRow.amount != null && dueRow.amount! > 0) {
          if (dueRow.partyController.text.trim().isEmpty) {
            errors.add('Payable: Party name is required');
            continue; // Skip if party name is empty
          }

          try {
            final due = Due(
              date: widget.selectedDate,
              userId: user.id,
              branchId: branch.id,
              party: dueRow.partyController.text.trim(),
              amount: dueRow.amount!,
              type: DueType.payable,
              remarks: dueRow.remarksController.text.trim().isEmpty
                  ? null
                  : dueRow.remarksController.text.trim(),
            );

            debugPrint('Saving payable: ${due.toJson()}');
            await _dbService.saveDue(due);
            savedCount++;
            debugPrint('Payable saved successfully');
          } catch (e) {
            debugPrint('Error saving payable: $e');
            errors.add('Payable: ${ErrorMessageHelper.getUserFriendlyError(e)}');
          }
        }
      }

      // Reload data to get fresh IDs
      await _loadData();

      if (mounted) {
        if (savedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$savedCount due(s) saved successfully${errors.isNotEmpty ? '. ${errors.length} error(s)' : ''}'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (errors.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No dues saved. Errors: ${errors.join(", ")}'),
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No dues to save. Please add at least one due with amount and party name')),
          );
        }
        // Don't navigate away - let user continue editing if needed
      }
    } catch (e) {
      debugPrint('Error in save function: $e');
      if (mounted) {
        final errorMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save dues. $errorMessage')),
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
          title: Text('Due - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Due - ${DateFormat('d MMM yyyy').format(widget.selectedDate)}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Receivable'),
            Tab(text: 'Payable'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDueList(_receivables, _removeReceivable, _addNewReceivable, _getTotalReceivables, 'Receivables'),
          _buildDueList(_payables, _removePayable, _addNewPayable, _getTotalPayables, 'Payables'),
        ],
      ),
    );
  }

  Widget _buildDueList(
    List<DueRow> dues,
    Function(int) onRemove,
    VoidCallback onAdd,
    double Function() getTotal,
    String title,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: dues.length + 1, // +1 for the Add button
            itemBuilder: (context, index) {
              if (index == dues.length) {
                // Add button as the last item
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FloatingActionButton.extended(
                    onPressed: onAdd,
                    label: const Text('Add'),
                    icon: const Icon(Icons.add),
                  ),
                );
              }
              return _buildDueRow(index, dues[index], () => onRemove(index));
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
                    Text(
                      'Total $title:',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(getTotal()),
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
    );
  }

  Widget _buildDueRow(int index, DueRow due, VoidCallback onRemove) {
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
                  child: TextField(
                    controller: due.partyController,
                    decoration: const InputDecoration(
                      labelText: 'Party Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
                    controller: due.amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
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
                        due.amount = value.isEmpty
                            ? null
                            : double.tryParse(value);
                      });
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: due.remarksController,
              decoration: const InputDecoration(
                labelText: 'Reference / Remarks (optional)',
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

  @override
  void dispose() {
    _tabController.dispose();
    for (var due in _receivables) {
      due.dispose();
    }
    for (var due in _payables) {
      due.dispose();
    }
    super.dispose();
  }
}

class DueRow {
  final TextEditingController partyController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();
  final DueType type;
  double? amount;
  String? id; // Track if this row is saved in database

  DueRow({required this.type});

  void dispose() {
    partyController.dispose();
    amountController.dispose();
    remarksController.dispose();
  }
}

