import 'package:flutter/foundation.dart';

enum SplitMode { equal, custom, percent }

@immutable
class Expense {
  const Expense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amountCents,
    required this.paidByUserId,
    required this.splitUserIds,
    required this.createdAtMs,
    this.splitMode = SplitMode.equal,
    this.customAmounts = const {},
    this.percentages = const {},
  });

  final String id;
  final String groupId;
  final String description;
  final int amountCents;
  final String paidByUserId;
  final List<String> splitUserIds;
  final int createdAtMs;
  final SplitMode splitMode;
  final Map<String, int> customAmounts; // userId -> amount in cents
  final Map<String, double> percentages; // userId -> percentage (0.0-1.0)

  Map<String, Object?> toJson() => <String, Object?>{
        'groupId': groupId,
        'description': description,
        'amountCents': amountCents,
        'paidByUserId': paidByUserId,
        'splitUserIds': splitUserIds,
        'createdAtMs': createdAtMs,
        'splitMode': splitMode.name,
        'customAmounts': customAmounts,
        'percentages': percentages,
      };

  static Expense fromDoc(String id, Map<String, Object?> data) {
    final splitModeStr = data['splitMode'] as String? ?? 'equal';
    final splitMode = SplitMode.values.firstWhere(
      (e) => e.name == splitModeStr,
      orElse: () => SplitMode.equal,
    );
    
    final customAmountsData = data['customAmounts'] as Map<String, dynamic>? ?? {};
    final customAmounts = <String, int>{};
    customAmountsData.forEach((k, v) => customAmounts[k] = (v as num).toInt());
    
    final percentagesData = data['percentages'] as Map<String, dynamic>? ?? {};
    final percentages = <String, double>{};
    percentagesData.forEach((k, v) => percentages[k] = (v as num).toDouble());
    
    return Expense(
      id: id,
      groupId: (data['groupId'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      amountCents: (data['amountCents'] as num?)?.toInt() ?? 0,
      paidByUserId: (data['paidByUserId'] as String?) ?? '',
      splitUserIds: (data['splitUserIds'] as List<dynamic>? ?? const <dynamic>[]).map((e) => e as String).toList(),
      createdAtMs: (data['createdAtMs'] as num?)?.toInt() ?? 0,
      splitMode: splitMode,
      customAmounts: customAmounts,
      percentages: percentages,
    );
  }
}


