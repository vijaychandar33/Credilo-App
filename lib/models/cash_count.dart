class CashCount {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String denomination;
  final int count;
  final double total;
  final DateTime? createdAt;

  CashCount({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.denomination,
    required this.count,
    required this.total,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'denomination': denomination,
      'count': count,
      'total': total,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory CashCount.fromJson(Map<String, dynamic> json) {
    return CashCount(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      denomination: json['denomination'] ?? '',
      count: json['count'] ?? 0,
      total: (json['total'] as num).toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

