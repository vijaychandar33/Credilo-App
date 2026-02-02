enum DueType { receivable, payable }
enum DueStatus { open, partiallyPaid, paid }

/// Whether a due amount has been received (receivables) or paid (payables).
/// Stored in DB as 'received' or 'not_received'.
String dueReceivedStatusToJson(bool isReceived) =>
    isReceived ? 'received' : 'not_received';

bool dueReceivedStatusFromJson(dynamic value) {
  if (value == null) return false;
  return value.toString() == 'received';
}

class Due {
  final String? id;
  final DateTime date;
  final String userId;
  final String branchId;
  final String party;
  final double amount;
  final DueType type;
  /// Whether the due has been received (receivables) or paid (payables).
  /// Null treated as not received for backward compatibility.
  final bool isReceived;
  final String? remarks;
  final DateTime? createdAt;

  Due({
    this.id,
    required this.date,
    required this.userId,
    required this.branchId,
    required this.party,
    required this.amount,
    required this.type,
    this.isReceived = false,
    this.remarks,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'branch_id': branchId,
      'party': party,
      'amount': amount,
      'type': type == DueType.receivable ? 'receivable' : 'payable',
      'status': dueReceivedStatusToJson(isReceived),
      'remarks': remarks,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Due.fromJson(Map<String, dynamic> json) {
    return Due(
      id: json['id']?.toString(),
      date: DateTime.parse(json['date']),
      userId: json['user_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      party: json['party'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] == 'receivable'
          ? DueType.receivable
          : DueType.payable,
      isReceived: dueReceivedStatusFromJson(json['status']),
      remarks: json['remarks'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }
}

