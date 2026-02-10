class QrPayment {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String? providerId; // UUID; rename-safe link to upi_providers
  final String provider;
  final double? amount; // Legacy field, nullable for backward compatibility
  final double? amountBeforeMidnight; // Sales before 12 AM
  final double? amountAfterMidnight; // Sales after 12 AM until closing time
  final String? notes;
  final DateTime? createdAt;

  QrPayment({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    this.providerId,
    required this.provider,
    this.amount,
    this.amountBeforeMidnight,
    this.amountAfterMidnight,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      if (providerId != null) 'provider_id': providerId,
      'provider': provider,
      if (amount != null) 'amount': amount,
      if (amountBeforeMidnight != null) 'amount_before_midnight': amountBeforeMidnight,
      if (amountAfterMidnight != null) 'amount_after_midnight': amountAfterMidnight,
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
      providerId: json['provider_id']?.toString(),
      provider: json['provider'] ?? '',
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
      amountBeforeMidnight: json['amount_before_midnight'] != null 
          ? (json['amount_before_midnight'] as num).toDouble() 
          : null,
      amountAfterMidnight: json['amount_after_midnight'] != null 
          ? (json['amount_after_midnight'] as num).toDouble() 
          : null,
      notes: json['notes'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

