import 'package:flutter/foundation.dart';
import 'dart:convert';

@immutable
class Group {
  static String encodeList(List<Group> groups) {
    return groups.map((g) => g.toJson()..['id'] = g.id).toList().toString();
  }

  static List<Group> decodeList(String encoded) {
    final List<dynamic> list = List<dynamic>.from(
      (encoded.startsWith('[') && encoded.endsWith(']'))
          ? (encoded.length > 2 ? (jsonDecode(encoded) as List) : [])
          : [],
    );
    return list
        .map((e) => Group.fromDoc(e['id'] as String, Map<String, Object?>.from(e)))
        .toList();
  }
  const Group({
    required this.id,
    required this.name,
    required this.memberUserIds,
    required this.createdAtMs,
    this.shareCode,
  });

  final String id;
  final String name;
  final List<String> memberUserIds;
  final int createdAtMs;
  final String? shareCode;

  Group copyWith({String? id, String? name, List<String>? memberUserIds, int? createdAtMs, String? shareCode}) => Group(
        id: id ?? this.id,
        name: name ?? this.name,
        memberUserIds: memberUserIds ?? this.memberUserIds,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        shareCode: shareCode ?? this.shareCode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'memberUserIds': memberUserIds,
        'createdAtMs': createdAtMs,
        'shareCode': shareCode,
      };

  static Group fromDoc(String id, Map<String, Object?> data) {
    return Group(
      id: id,
      name: (data['name'] as String?) ?? 'Group',
      memberUserIds: (data['memberUserIds'] as List<dynamic>? ?? const <dynamic>[]).map((e) => e as String).toList(),
      createdAtMs: (data['createdAtMs'] as num?)?.toInt() ?? 0,
      shareCode: data['shareCode'] as String?,
    );
  }
}

@immutable
class SettlementInfo {
  const SettlementInfo({
    required this.debtorId,
    required this.creditorId,
    required this.amount,
  });
  
  final String debtorId;
  final String creditorId;
  final int amount; // Amount in cents
}


