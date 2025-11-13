import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_expense.dart';
import '../models/cash_count.dart';
import '../models/card_sale.dart';
import '../models/online_sale.dart';
import '../models/qr_payment.dart';
import '../models/due.dart';
import '../models/cash_closing.dart';
import '../models/branch.dart';
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
          .order('created_at', ascending: false);

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
      await _client.from('cash_expenses').insert(expense.toJson());
    } catch (e) {
      debugPrint('Error saving cash expense: $e');
      rethrow;
    }
  }

  Future<void> updateCashExpense(CashExpense expense) async {
    try {
      await _client
          .from('cash_expenses')
          .update(expense.toJson())
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
          .order('created_at', ascending: false);

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
      await _client.from('card_sales').insert(sale.toJson());
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
          .order('created_at', ascending: false);

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
          .order('created_at', ascending: false);

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
      await _client.from('online_sales').insert(sale.toJson());
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
          .order('created_at', ascending: false);

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
      await _client.from('qr_payments').insert(payment.toJson());
    } catch (e) {
      debugPrint('Error saving QR payment: $e');
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

      final response = await query.order('created_at', ascending: false);

      return (response as List).map((json) => Due.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching dues: $e');
      return [];
    }
  }

  Future<void> saveDue(Due due) async {
    try {
      await _client.from('dues').insert(due.toJson());
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
      await _client.from('cash_closings').upsert(closing.toJson());
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
