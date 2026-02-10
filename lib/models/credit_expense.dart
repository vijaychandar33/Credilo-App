enum CreditExpenseStatus { unpaid, paid }

/// Payment method when marking a credit expense as paid (Supplier Dashboard only).
enum CreditExpensePaymentMethod { cash, bank, others }

extension CreditExpensePaymentMethodExt on CreditExpensePaymentMethod {
  String get displayLabel {
    switch (this) {
      case CreditExpensePaymentMethod.cash:
        return 'Paid via Cash';
      case CreditExpensePaymentMethod.bank:
        return 'Paid via Bank';
      case CreditExpensePaymentMethod.others:
        return 'Others';
    }
  }

  String get value {
    switch (this) {
      case CreditExpensePaymentMethod.cash:
        return 'cash';
      case CreditExpensePaymentMethod.bank:
        return 'bank';
      case CreditExpensePaymentMethod.others:
        return 'others';
    }
  }

  static CreditExpensePaymentMethod? fromValue(String? v) {
    if (v == null) return null;
    switch (v.toLowerCase()) {
      case 'cash':
        return CreditExpensePaymentMethod.cash;
      case 'bank':
        return CreditExpensePaymentMethod.bank;
      case 'others':
        return CreditExpensePaymentMethod.others;
      default:
        return null;
    }
  }
}

class CreditExpense {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String supplier;
  final String? supplierId; // UUID; used for filtering so supplier rename doesn't break list
  final String category;
  final double amount;
  final String? note;
  final CreditExpenseStatus status;
  final String? paymentMethod; // 'cash' | 'bank' | 'others'
  final String? paymentNote;   // Required when paymentMethod == 'others'
  final DateTime? createdAt;
  final Map<String, dynamic>? branchInfo; // For branch name/location

  CreditExpense({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.supplier,
    this.supplierId,
    required this.category,
    required this.amount,
    this.note,
    this.status = CreditExpenseStatus.unpaid,
    this.paymentMethod,
    this.paymentNote,
    this.createdAt,
    this.branchInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'supplier': supplier,
      if (supplierId != null) 'supplier_id': supplierId,
      'category': category,
      'amount': amount,
      'note': note,
      'status': status == CreditExpenseStatus.paid ? 'paid' : 'unpaid',
      'payment_method': paymentMethod,
      'payment_note': paymentNote,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory CreditExpense.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? branchInfo;
    if (json['branches'] != null) {
      branchInfo = json['branches'] is Map<String, dynamic>
          ? json['branches'] as Map<String, dynamic>
          : null;
    }
    return CreditExpense(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      supplier: json['supplier'] ?? '',
      supplierId: json['supplier_id']?.toString(),
      category: json['category'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      note: json['note'],
      status: json['status'] == 'paid' || json['status'] == true
          ? CreditExpenseStatus.paid
          : CreditExpenseStatus.unpaid,
      paymentMethod: json['payment_method']?.toString(),
      paymentNote: json['payment_note']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      branchInfo: branchInfo,
    );
  }

  String? get branchName => branchInfo?['name'] as String?;
  String? get branchLocation => branchInfo?['location'] as String?;

  /// Human-readable payment info for display (e.g. "Paid via Cash" or "Paid via Others: Cheque").
  String? get paymentDisplayText {
    if (status != CreditExpenseStatus.paid) return null;
    final method = CreditExpensePaymentMethodExt.fromValue(paymentMethod);
    if (method == null) return null;
    if (method == CreditExpensePaymentMethod.others) {
      final n = paymentNote?.trim();
      return n != null && n.isNotEmpty
          ? 'Paid via Others: $n'
          : 'Paid via Others';
    }
    return method.displayLabel;
  }
}

