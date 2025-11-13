class CashExpense {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String item;
  final String category;
  final double amount;
  final String? note;
  final DateTime? createdAt;

  CashExpense({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.item,
    required this.category,
    required this.amount,
    this.note,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'item': item,
      'category': category,
      'amount': amount,
      'note': note,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory CashExpense.fromJson(Map<String, dynamic> json) {
    return CashExpense(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      item: json['item'] ?? '',
      category: json['category'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      note: json['note'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

