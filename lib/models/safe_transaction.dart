enum SafeTransactionType {
  deposit,
  withdrawal,
}

class SafeTransaction {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final SafeTransactionType type;
  final double amount;
  final String? note;
  final String? cashClosingId;
  final DateTime? createdAt;

  SafeTransaction({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.type,
    required this.amount,
    this.note,
    this.cashClosingId,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'type': type == SafeTransactionType.deposit ? 'deposit' : 'withdrawal',
      'amount': amount,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (cashClosingId != null) 'cash_closing_id': cashClosingId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory SafeTransaction.fromJson(Map<String, dynamic> json) {
    return SafeTransaction(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      type: json['type'] == 'deposit'
          ? SafeTransactionType.deposit
          : SafeTransactionType.withdrawal,
      amount: (json['amount'] as num).toDouble(),
      note: json['note']?.toString(),
      cashClosingId: json['cash_closing_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}
