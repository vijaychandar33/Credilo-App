class CashClosing {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final double opening;
  final double totalCashSales;
  final double totalExpenses;
  final double countedCash;
  final double withdrawn;
  final String? withdrawnNotes;
  final double? adjustments;
  final double nextOpening;
  final double? discrepancy;
  final DateTime? createdAt;
  final String? lastEditedEmail;

  CashClosing({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.opening,
    required this.totalCashSales,
    required this.totalExpenses,
    required this.countedCash,
    required this.withdrawn,
    this.withdrawnNotes,
    this.adjustments,
    required this.nextOpening,
    this.discrepancy,
    this.createdAt,
    this.lastEditedEmail,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'opening': opening,
      'total_cash_sales': totalCashSales,
      'total_expenses': totalExpenses,
      'counted_cash': countedCash,
      'withdrawn': withdrawn,
      'withdrawn_notes': withdrawnNotes,
      'adjustments': adjustments,
      'next_opening': nextOpening,
      'discrepancy': discrepancy,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (lastEditedEmail != null) 'last_edited_email': lastEditedEmail,
    };
  }

  factory CashClosing.fromJson(Map<String, dynamic> json) {
    return CashClosing(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      opening: (json['opening'] as num).toDouble(),
      totalCashSales: (json['total_cash_sales'] as num).toDouble(),
      totalExpenses: (json['total_expenses'] as num).toDouble(),
      countedCash: (json['counted_cash'] as num).toDouble(),
      withdrawn: (json['withdrawn'] as num).toDouble(),
      withdrawnNotes: json['withdrawn_notes']?.toString(),
      adjustments: json['adjustments'] != null
          ? (json['adjustments'] as num).toDouble()
          : null,
      nextOpening: (json['next_opening'] as num).toDouble(),
      discrepancy: json['discrepancy'] != null
          ? (json['discrepancy'] as num).toDouble()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      lastEditedEmail: json['last_edited_email']?.toString(),
    );
  }
}

