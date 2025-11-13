class QrPayment {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String provider;
  final double amount;
  final String? txnId;
  final DateTime? settlementDate;
  final String? notes;
  final DateTime? createdAt;

  QrPayment({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.provider,
    required this.amount,
    this.txnId,
    this.settlementDate,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'provider': provider,
      'amount': amount,
      'txn_id': txnId,
      'settlement_date': settlementDate?.toIso8601String().split('T')[0],
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory QrPayment.fromJson(Map<String, dynamic> json) {
    return QrPayment(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      provider: json['provider'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      txnId: json['txn_id'],
      settlementDate: json['settlement_date'] != null
          ? DateTime.parse(json['settlement_date'])
          : null,
      notes: json['notes'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

