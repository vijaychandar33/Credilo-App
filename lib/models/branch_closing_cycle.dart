/// Per-branch custom closing cycle stored in Supabase.
class BranchClosingCycle {
  final String branchId;
  final bool useCustomClosing;
  final int closingHour;
  final int closingMinute;

  BranchClosingCycle({
    required this.branchId,
    this.useCustomClosing = false,
    this.closingHour = 1,
    this.closingMinute = 0,
  });

  factory BranchClosingCycle.fromJson(Map<String, dynamic> json) {
    return BranchClosingCycle(
      branchId: json['branch_id']?.toString() ?? '',
      useCustomClosing: json['use_custom_closing'] as bool? ?? false,
      closingHour: (json['closing_hour'] as num?)?.toInt() ?? 1,
      closingMinute: (json['closing_minute'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branch_id': branchId,
      'use_custom_closing': useCustomClosing,
      'closing_hour': closingHour,
      'closing_minute': closingMinute,
    };
  }

  BranchClosingCycle copyWith({
    bool? useCustomClosing,
    int? closingHour,
    int? closingMinute,
  }) {
    return BranchClosingCycle(
      branchId: branchId,
      useCustomClosing: useCustomClosing ?? this.useCustomClosing,
      closingHour: closingHour ?? this.closingHour,
      closingMinute: closingMinute ?? this.closingMinute,
    );
  }
}
