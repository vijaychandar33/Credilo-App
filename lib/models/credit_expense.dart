enum CreditExpenseStatus { unpaid, paid }

class CreditExpense {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String supplier;
  final String category;
  final double amount;
  final String? note;
  final CreditExpenseStatus status;
  final DateTime? createdAt;
  final Map<String, dynamic>? branchInfo; // For branch name/location

  CreditExpense({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.supplier,
    required this.category,
    required this.amount,
    this.note,
    this.status = CreditExpenseStatus.unpaid,
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
      'category': category,
      'amount': amount,
      'note': note,
      'status': status == CreditExpenseStatus.paid ? 'paid' : 'unpaid',
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
      category: json['category'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      note: json['note'],
      status: json['status'] == 'paid' || json['status'] == true
          ? CreditExpenseStatus.paid
          : CreditExpenseStatus.unpaid,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      branchInfo: branchInfo,
    );
  }
  
  String? get branchName => branchInfo?['name'] as String?;
  String? get branchLocation => branchInfo?['location'] as String?;
}

