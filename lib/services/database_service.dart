import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_expense.dart';
import '../models/online_expense.dart';
import '../models/cash_count.dart';
import '../models/card_sale.dart';
import '../models/online_sale.dart';
import '../models/online_sales_platform.dart';
import '../models/qr_payment.dart';
import '../models/upi_provider.dart';
import '../models/due.dart';
import '../models/cash_closing.dart';
import '../models/branch.dart';
import '../models/branch_closing_cycle.dart';
import '../models/credit_expense.dart';
import '../models/supplier.dart';
import '../models/safe_transaction.dart';
import '../models/fixed_expense.dart';
import '../utils/closing_cycle_service.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  // Cash Expenses
  Future<List<CashExpense>> getCashExpenses(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('cash_expenses')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => CashExpense.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching cash expenses: $e');
      return [];
    }
  }

  Future<void> saveCashExpense(CashExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('cash_expenses').insert(data);
    } catch (e) {
      debugPrint('Error saving cash expense: $e');
      rethrow;
    }
  }

  Future<void> updateCashExpense(CashExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client
          .from('cash_expenses')
          .update(data)
          .eq('id', expense.id!);
    } catch (e) {
      debugPrint('Error updating cash expense: $e');
      rethrow;
    }
  }

  Future<void> deleteCashExpense(String id) async {
    try {
      await _client.from('cash_expenses').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting cash expense: $e');
      rethrow;
    }
  }

  // Online Expenses
  Future<List<OnlineExpense>> getOnlineExpenses(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('online_expenses')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => OnlineExpense.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching online expenses: $e');
      return [];
    }
  }

  Future<void> saveOnlineExpense(OnlineExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('online_expenses').insert(data);
    } catch (e) {
      debugPrint('Error saving online expense: $e');
      rethrow;
    }
  }

  Future<void> updateOnlineExpense(OnlineExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client
          .from('online_expenses')
          .update(data)
          .eq('id', expense.id!);
    } catch (e) {
      debugPrint('Error updating online expense: $e');
      rethrow;
    }
  }

  Future<void> deleteOnlineExpense(String id) async {
    try {
      await _client.from('online_expenses').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting online expense: $e');
      rethrow;
    }
  }

  // Credit Expenses
  Future<List<CreditExpense>> getCreditExpenses(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('credit_expenses')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => CreditExpense.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching credit expenses: $e');
      return [];
    }
  }

  Future<void> saveCreditExpense(CreditExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('credit_expenses').insert(data);
    } catch (e) {
      debugPrint('Error saving credit expense: $e');
      rethrow;
    }
  }

  Future<void> deleteCreditExpense(String id) async {
    try {
      await _client.from('credit_expenses').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting credit expense: $e');
      rethrow;
    }
  }

  /// Fetches credit expenses by supplier UUID (rename-safe). Use this for supplier detail.
  Future<List<CreditExpense>> getCreditExpensesBySupplierId(
    String supplierId,
    String businessId, {
    List<String>? branchIds,
    DateTime? startDate,
    DateTime? endDate,
    List<CreditExpenseStatus>? statuses,
  }) async {
    String formatDate(DateTime date) {
      final onlyDate = DateTime(date.year, date.month, date.day);
      return onlyDate.toIso8601String().split('T').first;
    }

    String buildInClause(List<String> values) {
      final sanitized = values.map((value) => '"$value"').join(',');
      return '($sanitized)';
    }

    List<String> statusFilters = [];
    if (statuses != null && statuses.isNotEmpty) {
      statusFilters = statuses
          .map((status) => status == CreditExpenseStatus.paid ? 'paid' : 'unpaid')
          .toSet()
          .toList();
    }

    Future<List<String>> resolveBranchIds() async {
      if (branchIds != null && branchIds.isNotEmpty) {
        return branchIds;
      }
      return _fetchBranchIdsForBusiness(businessId);
    }

    try {
      final effectiveBranchIds = await resolveBranchIds();
      if (effectiveBranchIds.isEmpty) {
        return [];
      }

      var query = _client
          .from('credit_expenses')
          .select('''
            *,
            branches!credit_expenses_branch_id_fkey (
              id,
              name,
              location
            )
          ''')
          .eq('supplier_id', supplierId);

      if (effectiveBranchIds.length == 1) {
        query = query.eq('branch_id', effectiveBranchIds.first);
      } else {
        query = query.filter('branch_id', 'in', buildInClause(effectiveBranchIds));
      }

      if (startDate != null) {
        query = query.gte('date', formatDate(startDate));
      }
      if (endDate != null) {
        query = query.lte('date', formatDate(endDate));
      }
      if (statusFilters.isNotEmpty) {
        if (statusFilters.length == 1) {
          query = query.eq('status', statusFilters.first);
        } else {
          query = query.filter('status', 'in', buildInClause(statusFilters));
        }
      }

      final response = await query.order('date', ascending: false);

      return (response as List)
          .map((json) => CreditExpense.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching credit expenses by supplier id: $e');
      try {
        final effectiveBranchIds = await resolveBranchIds();
        if (effectiveBranchIds.isEmpty) {
          return [];
        }
        var simpleQuery = _client
            .from('credit_expenses')
            .select()
            .eq('supplier_id', supplierId);
        if (effectiveBranchIds.length == 1) {
          simpleQuery = simpleQuery.eq('branch_id', effectiveBranchIds.first);
        } else {
          simpleQuery = simpleQuery.filter('branch_id', 'in', buildInClause(effectiveBranchIds));
        }
        if (startDate != null) {
          simpleQuery = simpleQuery.gte('date', formatDate(startDate));
        }
        if (endDate != null) {
          simpleQuery = simpleQuery.lte('date', formatDate(endDate));
        }
        if (statusFilters.isNotEmpty) {
          if (statusFilters.length == 1) {
            simpleQuery = simpleQuery.eq('status', statusFilters.first);
          } else {
            simpleQuery = simpleQuery.filter('status', 'in', buildInClause(statusFilters));
          }
        }
        final simpleResponse = await simpleQuery.order('date', ascending: false);
        return (simpleResponse as List)
            .map((json) => CreditExpense.fromJson(json))
            .toList();
      } catch (e2) {
        debugPrint('Error in fallback query: $e2');
        return [];
      }
    }
  }

  Future<List<CreditExpense>> getCreditExpensesBySupplier(
    String supplierName,
    String businessId, {
    List<String>? branchIds,
    DateTime? startDate,
    DateTime? endDate,
    List<CreditExpenseStatus>? statuses,
  }) async {
    String formatDate(DateTime date) {
      final onlyDate = DateTime(date.year, date.month, date.day);
      return onlyDate.toIso8601String().split('T').first;
    }

    String buildInClause(List<String> values) {
      final sanitized = values.map((value) => '"$value"').join(',');
      return '($sanitized)';
    }

    List<String> statusFilters = [];
    if (statuses != null && statuses.isNotEmpty) {
      statusFilters = statuses
          .map((status) => status == CreditExpenseStatus.paid ? 'paid' : 'unpaid')
          .toSet()
          .toList();
    }

    Future<List<String>> resolveBranchIds() async {
      if (branchIds != null && branchIds.isNotEmpty) {
        return branchIds;
      }
      return _fetchBranchIdsForBusiness(businessId);
    }

    try {
      final effectiveBranchIds = await resolveBranchIds();
      if (effectiveBranchIds.isEmpty) {
        return [];
      }

      var query = _client
          .from('credit_expenses')
          .select('''
            *,
            branches!credit_expenses_branch_id_fkey (
              id,
              name,
              location
            )
          ''')
          .eq('supplier', supplierName);

      if (effectiveBranchIds.length == 1) {
        query = query.eq('branch_id', effectiveBranchIds.first);
      } else {
        query = query.filter('branch_id', 'in', buildInClause(effectiveBranchIds));
      }

      if (startDate != null) {
        query = query.gte('date', formatDate(startDate));
      }
      if (endDate != null) {
        query = query.lte('date', formatDate(endDate));
      }
      if (statusFilters.isNotEmpty) {
        if (statusFilters.length == 1) {
          query = query.eq('status', statusFilters.first);
        } else {
          query = query.filter('status', 'in', buildInClause(statusFilters));
        }
      }

      final response = await query.order('date', ascending: false);

      return (response as List)
          .map((json) => CreditExpense.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching credit expenses by supplier: $e');
      try {
        final effectiveBranchIds = await resolveBranchIds();
        if (effectiveBranchIds.isEmpty) {
          return [];
        }

        var simpleQuery = _client
            .from('credit_expenses')
            .select()
            .eq('supplier', supplierName);

        if (effectiveBranchIds.length == 1) {
          simpleQuery = simpleQuery.eq('branch_id', effectiveBranchIds.first);
        } else {
          simpleQuery = simpleQuery.filter('branch_id', 'in', buildInClause(effectiveBranchIds));
        }

        if (startDate != null) {
          simpleQuery = simpleQuery.gte('date', formatDate(startDate));
        }
        if (endDate != null) {
          simpleQuery = simpleQuery.lte('date', formatDate(endDate));
        }
        if (statusFilters.isNotEmpty) {
          if (statusFilters.length == 1) {
            simpleQuery = simpleQuery.eq('status', statusFilters.first);
          } else {
            simpleQuery = simpleQuery.filter('status', 'in', buildInClause(statusFilters));
          }
        }

        final simpleResponse = await simpleQuery.order('date', ascending: false);
        return (simpleResponse as List)
            .map((json) => CreditExpense.fromJson(json))
            .toList();
      } catch (e2) {
        debugPrint('Error in fallback query: $e2');
        return [];
      }
    }
  }

  Future<void> updateCreditExpenseStatus(
    String id,
    CreditExpenseStatus status, {
    String? paymentMethod,
    String? paymentNote,
  }) async {
    try {
      final Map<String, dynamic> payload = {
        'status': status == CreditExpenseStatus.paid ? 'paid' : 'unpaid',
        'payment_method': status == CreditExpenseStatus.paid ? paymentMethod : null,
        'payment_note': status == CreditExpenseStatus.paid ? paymentNote : null,
      };
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        payload['last_edited_email'] = email;
      }
      await _client.from('credit_expenses').update(payload).eq('id', id);
    } catch (e) {
      debugPrint('Error updating credit expense status: $e');
      rethrow;
    }
  }

  Future<void> updateCreditExpensesStatus(
    List<String> ids,
    CreditExpenseStatus status, {
    String? paymentMethod,
    String? paymentNote,
  }) async {
    try {
      final Map<String, dynamic> payload = {
        'status': status == CreditExpenseStatus.paid ? 'paid' : 'unpaid',
        'payment_method': status == CreditExpenseStatus.paid ? paymentMethod : null,
        'payment_note': status == CreditExpenseStatus.paid ? paymentNote : null,
      };
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        payload['last_edited_email'] = email;
      }
      for (var id in ids) {
        await _client.from('credit_expenses').update(payload).eq('id', id);
      }
    } catch (e) {
      debugPrint('Error updating credit expenses status: $e');
      rethrow;
    }
  }

  /// Updates the supplier (and optional supplier_id) for a credit expense. Used when moving an "Others" entry to a real supplier.
  Future<void> updateCreditExpenseSupplier(String id, String supplierName, String? supplierId) async {
    try {
      final Map<String, dynamic> payload = {
        'supplier': supplierName,
        'supplier_id': (supplierId != null && supplierId.isNotEmpty) ? supplierId : null,
      };
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        payload['last_edited_email'] = email;
      }
      await _client.from('credit_expenses').update(payload).eq('id', id);
    } catch (e) {
      debugPrint('Error updating credit expense supplier: $e');
      rethrow;
    }
  }

  // Suppliers
  Future<List<String>> _fetchBranchIdsForBusiness(String businessId) async {
    final branchesResponse = await _client
        .from('branches')
        .select('id')
        .eq('business_id', businessId);

    return (branchesResponse as List)
        .map((b) => b['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<List<Supplier>> getSuppliers(String businessId) async {
    try {
      final response = await _client
          .from('suppliers')
          .select()
          .eq('business_id', businessId)
          .order('name', ascending: true);

      return (response as List)
          .map((json) => Supplier.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching suppliers: $e');
      return [];
    }
  }

  Future<void> saveSupplier(Supplier supplier) async {
    try {
      await _client.from('suppliers').insert(supplier.toJson());
    } catch (e) {
      debugPrint('Error saving supplier: $e');
      rethrow;
    }
  }

  Future<void> updateSupplier(Supplier supplier) async {
    if (supplier.id == null) {
      throw Exception('Supplier ID is required for update');
    }
    try {
      await _client
          .from('suppliers')
          .update({
            'name': supplier.name,
            'contact': supplier.contact,
            'address': supplier.address,
            'supplying_branch_ids': supplier.supplyingBranchIds != null &&
                    supplier.supplyingBranchIds!.isNotEmpty
                ? supplier.supplyingBranchIds
                : null,
          })
          .eq('id', supplier.id!);
    } catch (e) {
      debugPrint('Error updating supplier: $e');
      rethrow;
    }
  }

  /// Checks if any credit expenses exist for this supplier (by UUID). Use for delete guard.
  Future<bool> hasCreditExpensesBySupplierId(String supplierId) async {
    try {
      final response = await _client
          .from('credit_expenses')
          .select('id')
          .eq('supplier_id', supplierId)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking credit expenses by supplier id: $e');
      return true; // Return true to be safe (prevent deletion if check fails)
    }
  }

  Future<bool> hasCreditExpenses(String supplierName, String businessId) async {
    try {
      final branchesResponse = await _client
          .from('branches')
          .select('id')
          .eq('business_id', businessId);
      final branchIds = (branchesResponse as List)
          .map((b) => b['id'] as String)
          .toList();
      if (branchIds.isEmpty) {
        return false;
      }
      var query = _client
          .from('credit_expenses')
          .select('id')
          .eq('supplier', supplierName);
      if (branchIds.length == 1) {
        query = query.eq('branch_id', branchIds[0]);
      } else if (branchIds.length > 1) {
        query = query.or(branchIds.map((id) => 'branch_id.eq.$id').join(','));
      }
      final response = await query.limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking credit expenses: $e');
      return true;
    }
  }

  Future<void> deleteSupplier(String id) async {
    try {
      await _client.from('suppliers').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting supplier: $e');
      rethrow;
    }
  }

  // Cash Counts
  Future<List<CashCount>> getCashCounts(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('cash_counts')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId);

      return (response as List)
          .map((json) => CashCount.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching cash counts: $e');
      return [];
    }
  }

  Future<void> saveCashCounts(List<CashCount> counts) async {
    try {
      // Delete existing counts for the date
      if (counts.isNotEmpty) {
        await _client
            .from('cash_counts')
            .delete()
            .eq('date', counts.first.date.toIso8601String().split('T')[0])
            .eq('branch_id', counts.first.branchId);
      }

      // Insert new counts
      await _client.from('cash_counts').insert(
          counts.map((count) => count.toJson()).toList());
    } catch (e) {
      debugPrint('Error saving cash counts: $e');
      rethrow;
    }
  }

  // Card Sales
  Future<List<CardSale>> getCardSales(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('card_sales')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => CardSale.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching card sales: $e');
      return [];
    }
  }

  Future<void> saveCardSale(CardSale sale) async {
    try {
      final data = sale.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('card_sales').insert(data);
    } catch (e) {
      debugPrint('Error saving card sale: $e');
      rethrow;
    }
  }

  Future<void> deleteCardSale(String id) async {
    try {
      await _client.from('card_sales').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting card sale: $e');
      rethrow;
    }
  }

  // Card Machines
  Future<List<CardMachine>> getCardMachines(String branchId) async {
    try {
      final response = await _client
          .from('card_machines')
          .select()
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => CardMachine.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching card machines: $e');
      return [];
    }
  }

  Future<void> saveCardMachine(CardMachine machine) async {
    try {
      if (machine.id == null) {
        // Insert new machine
        await _client.from('card_machines').insert(machine.toJson());
      } else {
        // Update existing machine
        await _client
            .from('card_machines')
            .update(machine.toJson())
            .eq('id', machine.id!);
      }
    } catch (e) {
      debugPrint('Error saving card machine: $e');
      rethrow;
    }
  }

  /// Card machine IDs (for this branch) that have at least one card_sale. Used to disable delete.
  Future<Set<String>> getCardMachineIdsWithCardSales(String branchId) async {
    try {
      final response = await _client
          .from('card_sales')
          .select('card_machine_id')
          .eq('branch_id', branchId)
          .not('card_machine_id', 'is', null);
      return (response as List)
          .map((r) => r['card_machine_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('Error fetching card machine ids with sales: $e');
      return {};
    }
  }

  Future<void> deleteCardMachine(String machineId) async {
    try {
      await _client.from('card_machines').delete().eq('id', machineId);
    } catch (e) {
      debugPrint('Error deleting card machine: $e');
      rethrow;
    }
  }

  // Online Sales
  Future<List<OnlineSale>> getOnlineSales(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('online_sales')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => OnlineSale.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching online sales: $e');
      return [];
    }
  }

  Future<void> saveOnlineSale(OnlineSale sale) async {
    try {
      final data = sale.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('online_sales').insert(data);
    } catch (e) {
      debugPrint('Error saving online sale: $e');
      rethrow;
    }
  }

  Future<void> deleteOnlineSale(String id) async {
    try {
      await _client.from('online_sales').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting online sale: $e');
      rethrow;
    }
  }

  // QR Payments
  Future<List<QrPayment>> getQrPayments(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('qr_payments')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => QrPayment.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching QR payments: $e');
      return [];
    }
  }

  Future<void> saveQrPayment(QrPayment payment) async {
    try {
      final data = payment.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('qr_payments').insert(data);
    } catch (e) {
      debugPrint('Error saving QR payment: $e');
      rethrow;
    }
  }

  Future<void> updateQrPayment(QrPayment payment) async {
    try {
      if (payment.id == null) {
        throw Exception('Payment ID is required for update');
      }
      final data = payment.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client
          .from('qr_payments')
          .update(data)
          .eq('id', payment.id!);
    } catch (e) {
      debugPrint('Error updating QR payment: $e');
      rethrow;
    }
  }

  Future<void> deleteQrPayment(String paymentId) async {
    try {
      await _client.from('qr_payments').delete().eq('id', paymentId);
    } catch (e) {
      debugPrint('Error deleting QR payment: $e');
      rethrow;
    }
  }

  // UPI Providers (branch-specific, like card machines)
  Future<List<UpiProvider>> getUpiProviders(String branchId) async {
    try {
      final response = await _client
          .from('upi_providers')
          .select()
          .eq('branch_id', branchId)
          .order('name', ascending: true);
      return (response as List).map((json) => UpiProvider.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching UPI providers: $e');
      return [];
    }
  }

  Future<void> saveUpiProvider(UpiProvider provider) async {
    try {
      await _client.from('upi_providers').insert(provider.toJson());
    } catch (e) {
      debugPrint('Error saving UPI provider: $e');
      rethrow;
    }
  }

  Future<void> updateUpiProvider(UpiProvider provider) async {
    if (provider.id == null) throw Exception('UpiProvider id required for update');
    try {
      await _client
          .from('upi_providers')
          .update({'name': provider.name, 'location': provider.location})
          .eq('id', provider.id!);
    } catch (e) {
      debugPrint('Error updating UPI provider: $e');
      rethrow;
    }
  }

  /// Provider IDs (for this branch) that have at least one qr_payment. Used to disable delete.
  Future<Set<String>> getProviderIdsWithQrPayments(String branchId) async {
    try {
      final response = await _client
          .from('qr_payments')
          .select('provider_id')
          .eq('branch_id', branchId)
          .not('provider_id', 'is', null);
      return (response as List)
          .map((r) => r['provider_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('Error fetching provider ids with payments: $e');
      return {};
    }
  }

  Future<void> deleteUpiProvider(String providerId) async {
    try {
      await _client.from('upi_providers').delete().eq('id', providerId);
    } catch (e) {
      debugPrint('Error deleting UPI provider: $e');
      rethrow;
    }
  }

  // Online Sales Platforms (branch-specific, like card machines / UPI providers)
  Future<List<OnlineSalesPlatform>> getOnlineSalesPlatforms(String branchId) async {
    try {
      final response = await _client
          .from('online_sales_platforms')
          .select()
          .eq('branch_id', branchId)
          .order('name', ascending: true);
      return (response as List).map((json) => OnlineSalesPlatform.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching online sales platforms: $e');
      return [];
    }
  }

  Future<void> saveOnlineSalesPlatform(OnlineSalesPlatform platform) async {
    try {
      await _client.from('online_sales_platforms').insert(platform.toJson());
    } catch (e) {
      debugPrint('Error saving online sales platform: $e');
      rethrow;
    }
  }

  Future<void> updateOnlineSalesPlatform(OnlineSalesPlatform platform) async {
    if (platform.id == null) throw Exception('OnlineSalesPlatform id required for update');
    try {
      await _client
          .from('online_sales_platforms')
          .update({'name': platform.name})
          .eq('id', platform.id!);
    } catch (e) {
      debugPrint('Error updating online sales platform: $e');
      rethrow;
    }
  }

  /// Platform IDs (for this branch) that have at least one online_sale. Used to disable delete.
  Future<Set<String>> getPlatformIdsWithOnlineSales(String branchId) async {
    try {
      final response = await _client
          .from('online_sales')
          .select('platform_id')
          .eq('branch_id', branchId)
          .not('platform_id', 'is', null);
      return (response as List)
          .map((r) => r['platform_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('Error fetching platform ids with sales: $e');
      return {};
    }
  }

  Future<void> deleteOnlineSalesPlatform(String platformId) async {
    try {
      await _client.from('online_sales_platforms').delete().eq('id', platformId);
    } catch (e) {
      debugPrint('Error deleting online sales platform: $e');
      rethrow;
    }
  }

  // Get calculated total for QR payments for a specific date and branch
  // If not stored, calculates it on the fly and stores it for future use
  Future<double> getQrPaymentCalculatedTotal(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('daily_qr_totals')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .maybeSingle();

      if (response != null && response['calculated_total'] != null) {
        return (response['calculated_total'] as num).toDouble();
      }
      
      // If not stored, calculate it on the fly (for backward compatibility)
      // This happens for old data that was created before this feature
      final payments = await getQrPayments(date, branchId);
      final useCustomClosing = await ClosingCycleService.isCustomClosingEnabled(branchId);
      
      double calculatedTotal = 0.0;
      
      if (useCustomClosing) {
        // Calculate using the formula: (Before 12 AM of current day) - (After 12 AM of previous day) + (After 12 AM of current day)
        double currentDayBeforeMidnight = 0.0;
        double currentDayAfterMidnight = 0.0;
        
        for (var payment in payments) {
          currentDayBeforeMidnight += payment.amountBeforeMidnight ?? 0;
          currentDayAfterMidnight += payment.amountAfterMidnight ?? 0;
        }
        
        // Get previous day's after-midnight sales
        final previousDate = date.subtract(const Duration(days: 1));
        final previousPayments = await getQrPayments(previousDate, branchId);
        double previousDayAfterMidnight = 0.0;
        for (var payment in previousPayments) {
          previousDayAfterMidnight += payment.amountAfterMidnight ?? 0;
        }
        
        calculatedTotal = currentDayBeforeMidnight - previousDayAfterMidnight + currentDayAfterMidnight;
      } else {
        // Simple sum when custom closing is disabled
        for (var payment in payments) {
          if (payment.amount != null) {
            calculatedTotal += payment.amount!;
          } else {
            calculatedTotal += (payment.amountBeforeMidnight ?? 0) + (payment.amountAfterMidnight ?? 0);
          }
        }
      }
      
      // Store the calculated total for future use
      await upsertQrPaymentCalculatedTotal(date, branchId, calculatedTotal);
      
      return calculatedTotal;
    } catch (e) {
      debugPrint('Error fetching QR payment calculated total: $e');
      return 0.0;
    }
  }
  
  // Update or insert calculated total for QR payments
  Future<void> upsertQrPaymentCalculatedTotal(
    DateTime date,
    String branchId,
    double calculatedTotal,
  ) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      
      // Check if record exists
      final existing = await _client
          .from('daily_qr_totals')
          .select()
          .eq('date', dateStr)
          .eq('branch_id', branchId)
          .maybeSingle();
      
      if (existing != null) {
        // Record exists, update it
        await _client
            .from('daily_qr_totals')
            .update({
              'calculated_total': calculatedTotal,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('date', dateStr)
            .eq('branch_id', branchId);
      } else {
        // Record doesn't exist, insert it
        await _client.from('daily_qr_totals').insert({
          'date': dateStr,
          'branch_id': branchId,
          'calculated_total': calculatedTotal,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error upserting QR payment calculated total: $e');
      rethrow;
    }
  }

  // Dues
  Future<List<Due>> getDues(DateTime date, String branchId, {String? type}) async {
    try {
      var query = _client
          .from('dues')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId);

      if (type != null) {
        query = query.eq('type', type);
      }

      final response = await query.order('created_at', ascending: true);

      return (response as List).map((json) => Due.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching dues: $e');
      return [];
    }
  }

  Future<void> saveDue(Due due) async {
    try {
      final data = due.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('dues').insert(data);
    } catch (e) {
      debugPrint('Error saving due: $e');
      rethrow;
    }
  }

  Future<void> deleteDue(String dueId) async {
    try {
      await _client.from('dues').delete().eq('id', dueId);
    } catch (e) {
      debugPrint('Error deleting due: $e');
      rethrow;
    }
  }

  Future<void> updateDueStatus(String dueId, bool isReceived) async {
    try {
      final Map<String, dynamic> payload = {
        'status': isReceived ? 'received' : 'not_received',
      };
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        payload['last_edited_email'] = email;
        payload['status_last_edited_email'] = email;
      }
      await _client.from('dues').update(payload).eq('id', dueId);
    } catch (e) {
      debugPrint('Error updating due status: $e');
      rethrow;
    }
  }

  /// All dues for the branch that are not yet received (receivables) or paid (payables).
  Future<List<Due>> getPendingDues(String branchId) async {
    try {
      final response = await _client
          .from('dues')
          .select()
          .eq('branch_id', branchId)
          .eq('status', 'not_received')
          .order('date', ascending: false)
          .order('created_at', ascending: true);
      return (response as List).map((json) => Due.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching pending dues: $e');
      return [];
    }
  }

  // Cash Closings
  Future<CashClosing?> getCashClosing(DateTime date, String branchId) async {
    try {
      final response = await _client
          .from('cash_closings')
          .select()
          .eq('date', date.toIso8601String().split('T')[0])
          .eq('branch_id', branchId)
          .maybeSingle();

      if (response == null) return null;
      return CashClosing.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching cash closing: $e');
      return null;
    }
  }

  Future<void> saveCashClosing(CashClosing closing) async {
    try {
      // First, fetch existing record to get its ID (if it exists)
      // This ensures we update instead of creating duplicates
      final existing = await getCashClosing(closing.date, closing.branchId);
      
      // Prepare the data with ID if it exists
      final closingData = closing.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        closingData['last_edited_email'] = email;
      }
      String? closingId;
      if (existing != null && existing.id != null) {
        closingData['id'] = existing.id;
        closingId = existing.id;
      }
      
      // Upsert with conflict resolution on (date, branch_id)
      final upsertResult = await _client.from('cash_closings').upsert(
        closingData,
        onConflict: 'date,branch_id',
      ).select();
      
      // Get the ID of the saved cash closing
      if (upsertResult.isNotEmpty) {
        closingId = upsertResult[0]['id']?.toString();
      }
      
      // Handle safe transaction for withdrawn amount
      if (closingId != null) {
        // Check if there's an existing transaction for this cash closing
        final existingTransactions = await _client
            .from('safe_transactions')
            .select()
            .eq('cash_closing_id', closingId);
        
        final existingTransactionList = existingTransactions as List;
        
        if (closing.withdrawn > 0) {
          // Create or update safe transaction
          if (existingTransactionList.isNotEmpty) {
            // Update existing transaction
            final existingTransaction = existingTransactionList.first;
            final oldAmount = (existingTransaction['amount'] as num).toDouble();
            
            final existingNote = existingTransaction['note']?.toString();
            final newNote = closing.withdrawnNotes;

            // Update in-place (DB trigger handles balance adjustment on UPDATE)
            if (oldAmount != closing.withdrawn || existingNote != newNote) {
              await _client.from('safe_transactions').update({
                'amount': closing.withdrawn,
                'note': newNote,
                'date': closing.date.toIso8601String().split('T')[0],
                'user_id': closing.userId,
                'type': 'deposit',
              }).eq('cash_closing_id', closingId);
            }
          } else {
            // Create new transaction
            await saveSafeTransaction(SafeTransaction(
              date: closing.date,
              userId: closing.userId,
              branchId: closing.branchId,
              type: SafeTransactionType.deposit,
              amount: closing.withdrawn,
              note: closing.withdrawnNotes,
              cashClosingId: closingId,
            ));
          }
        } else if (existingTransactionList.isNotEmpty) {
          // Withdrawn is now 0: keep the record but zero it out (avoids needing DELETE rights)
          // DB trigger handles balance adjustment on UPDATE.
          await _client.from('safe_transactions').update({
            'amount': 0,
            'note': closing.withdrawnNotes,
            'date': closing.date.toIso8601String().split('T')[0],
            'user_id': closing.userId,
            'type': 'deposit',
          }).eq('cash_closing_id', closingId);
        }
      }
      
      // Update next day's opening balance and recalculate its values if it exists
      final nextDate = closing.date.add(const Duration(days: 1));
      final nextDayClosing = await getCashClosing(nextDate, closing.branchId);
      
      if (nextDayClosing != null) {
        // Fetch next day's actual data to recalculate
        final nextDayExpenses = await getCashExpenses(nextDate, closing.branchId);
        final nextDayTotalExpenses = nextDayExpenses.fold(0.0, (sum, e) => sum + e.amount);
        
        final nextDayCashCounts = await getCashCounts(nextDate, closing.branchId);
        final nextDayCountedCash = nextDayCashCounts.fold(0.0, (sum, count) => sum + count.total);
        
        // Recalculate total cash sales with new opening balance
        final newOpening = closing.nextOpening;
        final newTotalCashSales = (nextDayCountedCash - newOpening) + nextDayTotalExpenses;
        
        // Recalculate next opening for the next day
        final newNextOpening = newOpening + newTotalCashSales - nextDayTotalExpenses - nextDayClosing.withdrawn;
        
        // Calculate discrepancy
        final expectedCash = newOpening + newTotalCashSales - nextDayTotalExpenses;
        final discrepancy = nextDayCountedCash - expectedCash;
        
        // Prepare update data with ID to ensure we update the correct record
        final Map<String, dynamic> updateData = <String, dynamic>{
          'date': nextDate.toIso8601String().split('T')[0],
          'branch_id': closing.branchId,
          'user_id': closing.userId,
          'opening': newOpening,
          'total_cash_sales': newTotalCashSales,
          'total_expenses': nextDayTotalExpenses,
          'counted_cash': nextDayCountedCash,
          'withdrawn': nextDayClosing.withdrawn,
          if (nextDayClosing.withdrawnNotes != null) 'withdrawn_notes': nextDayClosing.withdrawnNotes,
          'next_opening': newNextOpening,
          if (discrepancy != 0) 'discrepancy': discrepancy,
          if (nextDayClosing.id != null) 'id': nextDayClosing.id!,
        };
        
        // Update the next day's cash closing with recalculated values
        await _client
            .from('cash_closings')
            .upsert(
              updateData,
              onConflict: 'date,branch_id',
            );
      }
    } catch (e) {
      debugPrint('Error saving cash closing: $e');
      rethrow;
    }
  }

  // Branches
  Future<List<Branch>> getUserBranches(String userId) async {
    try {
      final response = await _client
          .from('branch_users')
          .select('branches(*)')
          .eq('user_id', userId);

      return (response as List)
          .map((item) => Branch.fromJson(item['branches']))
          .toList();
    } catch (e) {
      debugPrint('Error fetching user branches: $e');
      return [];
    }
  }

  /// Update branch name, location, and status. Requires RLS policy allowing UPDATE on branches.
  Future<void> updateBranch(Branch branch) async {
    try {
      await _client
          .from('branches')
          .update({
            'name': branch.name,
            'location': branch.location,
            'status': branch.status == BranchStatus.active ? 'active' : 'inactive',
          })
          .eq('id', branch.id);
    } catch (e) {
      debugPrint('Error updating branch: $e');
      rethrow;
    }
  }

  // Branch visibility (what to show on home screen per branch)
  /// Fetches all visibility rows for a branch. Returns map of item_key -> visible.
  Future<Map<String, bool>> getBranchVisibility(String branchId) async {
    try {
      final response = await _client
          .from('branch_visibility')
          .select('item_key, visible')
          .eq('branch_id', branchId);
      final map = <String, bool>{};
      for (final row in response as List) {
        final key = row['item_key'] as String?;
        if (key != null) {
          map[key] = row['visible'] as bool? ?? true;
        }
      }
      return map;
    } catch (e) {
      debugPrint('Error fetching branch visibility: $e');
      return {};
    }
  }

  /// Sets one visibility item for a branch (upsert).
  Future<void> setBranchVisibility(String branchId, String itemKey, bool visible) async {
    try {
      await _client.from('branch_visibility').upsert(
        {
          'branch_id': branchId,
          'item_key': itemKey,
          'visible': visible,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'branch_id,item_key',
      );
    } catch (e) {
      debugPrint('Error setting branch visibility: $e');
      rethrow;
    }
  }

  /// Sets all visibility items for a branch (upserts). Keys not in [visibility] are not changed in DB; omit or true = visible.
  Future<void> setAllBranchVisibility(String branchId, Map<String, bool> visibility) async {
    try {
      for (final entry in visibility.entries) {
        await setBranchVisibility(branchId, entry.key, entry.value);
      }
    } catch (e) {
      debugPrint('Error setting all branch visibility: $e');
      rethrow;
    }
  }

  // Branch closing cycle (per-branch custom closing time)
  Future<BranchClosingCycle?> getBranchClosingCycle(String branchId) async {
    try {
      final response = await _client
          .from('branch_closing_cycle')
          .select()
          .eq('branch_id', branchId)
          .maybeSingle();
      if (response == null) return null;
      return BranchClosingCycle.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching branch closing cycle: $e');
      return null;
    }
  }

  /// Gets closing cycle for branch; returns defaults if no row exists.
  Future<BranchClosingCycle> getBranchClosingCycleOrDefault(String branchId) async {
    final row = await getBranchClosingCycle(branchId);
    return row ?? BranchClosingCycle(branchId: branchId);
  }

  Future<void> upsertBranchClosingCycle(BranchClosingCycle cycle) async {
    try {
      await _client.from('branch_closing_cycle').upsert(
        {
          ...cycle.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'branch_id',
      );
    } catch (e) {
      debugPrint('Error upserting branch closing cycle: $e');
      rethrow;
    }
  }

  // Check if there's any data that would be affected by disabling custom closing
  // Returns true if there's any UPI payment with amountAfterMidnight > 0
  // This means data exists between 12:00 AM and the custom closing time
  // If only data exists before 12:00 AM (amountBeforeMidnight), this returns false (allows disabling)
  Future<bool> hasDataAfterMidnight(List<String> branchIds) async {
    try {
      if (branchIds.isEmpty) return false;

      // Query for any payments with amount_after_midnight > 0
      // NULL and 0 values are excluded, which is correct - they don't block disabling
      var query = _client
          .from('qr_payments')
          .select('id')
          .gt('amount_after_midnight', 0);

      if (branchIds.length == 1) {
        query = query.eq('branch_id', branchIds.first);
      } else {
        query = query.or(branchIds.map((id) => 'branch_id.eq.$id').join(','));
      }

      final response = await query.limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking for after-midnight data: $e');
      // If there's an error, be conservative and return true to prevent disabling
      return true;
    }
  }

  // Safe Management
  Future<double> getSafeBalance(String branchId) async {
    try {
      final response = await _client
          .from('safe_balances')
          .select()
          .eq('branch_id', branchId)
          .maybeSingle();

      if (response == null) return 0.0;
      return (response['balance'] as num).toDouble();
    } catch (e) {
      debugPrint('Error fetching safe balance: $e');
      return 0.0;
    }
  }

  // Get safe balance as of a specific date (sum all transactions up to and including that date)
  Future<double> getSafeBalanceAsOfDate(String branchId, DateTime asOfDate) async {
    try {
      final dateStr = asOfDate.toIso8601String().split('T')[0];
      
      final response = await _client
          .from('safe_transactions')
          .select()
          .eq('branch_id', branchId)
          .lte('date', dateStr);

      double balance = 0.0;
      for (var transaction in response) {
        final type = transaction['type'] as String;
        final amount = (transaction['amount'] as num).toDouble();
        
        if (type == 'deposit') {
          balance += amount;
        } else if (type == 'withdrawal') {
          balance -= amount;
        }
      }

      return balance;
    } catch (e) {
      debugPrint('Error fetching safe balance as of date: $e');
      return 0.0;
    }
  }

  Future<List<SafeTransaction>> getSafeTransactions(
    String branchId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('safe_transactions')
          .select()
          .eq('branch_id', branchId);

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }

      final response = await query.order('created_at', ascending: false);

      return (response as List)
          .map((json) => SafeTransaction.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching safe transactions: $e');
      return [];
    }
  }

  Future<void> saveSafeTransaction(SafeTransaction transaction) async {
    try {
      await _client.from('safe_transactions').insert(transaction.toJson());
      // Balance is automatically updated by trigger
    } catch (e) {
      debugPrint('Error saving safe transaction: $e');
      rethrow;
    }
  }

  Future<void> deleteSafeTransaction(String id) async {
    try {
      await _client.from('safe_transactions').delete().eq('id', id);
      // Balance is automatically updated by trigger
    } catch (e) {
      debugPrint('Error deleting safe transaction: $e');
      rethrow;
    }
  }

  // Fixed Expenses
  Future<List<FixedExpense>> getFixedExpenses(
    String branchId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('fixed_expenses')
          .select()
          .eq('branch_id', branchId);

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((item) => FixedExpense.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('Error fetching fixed expenses: $e');
      rethrow;
    }
  }

  Future<void> saveFixedExpense(FixedExpense expense) async {
    try {
      final data = expense.toJson();
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) data['last_edited_email'] = email;
      await _client.from('fixed_expenses').insert(data);
    } catch (e) {
      debugPrint('Error saving fixed expense: $e');
      rethrow;
    }
  }

  Future<void> deleteFixedExpense(String id) async {
    try {
      await _client.from('fixed_expenses').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting fixed expense: $e');
      rethrow;
    }
  }

  // Owner Dashboard - Aggregated data
  Future<Map<String, dynamic>> getBranchSummary(
      String? branchId, DateTime startDate, DateTime endDate) async {
    try {
      var query = _client
          .from('cash_closings')
          .select()
          .gte('date', startDate.toIso8601String().split('T')[0])
          .lte('date', endDate.toIso8601String().split('T')[0]);

      if (branchId != null) {
        query = query.eq('branch_id', branchId);
      }

      final response = await query;

      // Aggregate data
      double totalSales = 0;
      double totalExpenses = 0;
      double totalClosing = 0;

      for (var item in response) {
        totalSales += (item['total_cash_sales'] as num).toDouble();
        totalExpenses += (item['total_expenses'] as num).toDouble();
        totalClosing += (item['next_opening'] as num).toDouble();
      }

      return {
        'total_sales': totalSales,
        'total_expenses': totalExpenses,
        'total_closing': totalClosing,
      };
    } catch (e) {
      debugPrint('Error fetching branch summary: $e');
      return {
        'total_sales': 0.0,
        'total_expenses': 0.0,
        'total_closing': 0.0,
      };
    }
  }
}
