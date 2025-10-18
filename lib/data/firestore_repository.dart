import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod/riverpod.dart';

import '../models/expense.dart';
import '../models/group.dart';
import '../models/settlement.dart';

class FirestoreRepository {
  /// Fetch groups once (not a stream)
  Future<List<Group>> getGroupsOnce(String userId) async {
    final snap = await _db
        .collection('groups')
        .where('memberUserIds', arrayContains: userId)
        .orderBy('createdAtMs', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((d) => Group.fromDoc(d.id, d.data())).toList();
  }
  FirestoreRepository(this._db);
  final FirebaseFirestore _db;

  // Local cache for groups to handle connection issues
  static List<Group> _cachedGroups = [];
  static String? _cachedUserId;

  // Groups
  Stream<Group> watchGroup(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((d) => Group.fromDoc(d.id, d.data() ?? {}));
  }

  Stream<List<Group>> watchGroups(String userId) {
    print('Setting up groups stream for user: $userId');
    return _db
        .collection('groups')
        .where('memberUserIds', arrayContains: userId)
        .orderBy('createdAtMs', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) {
          final groups = snap.docs
              .map((d) => Group.fromDoc(d.id, d.data()))
              .toList();
          print('Groups stream updated: ${groups.length} groups found');
          if (groups.isNotEmpty) {
            print('Group names: ${groups.map((g) => g.name).join(', ')}');
            // Update cache when we get data successfully
            _cachedGroups = groups;
            _cachedUserId = userId;
          }
          return groups;
        })
        .handleError((error) {
          print('Groups stream error: $error');
          // Return cached groups if available for this user
          if (_cachedUserId == userId && _cachedGroups.isNotEmpty) {
            print(
              'Returning ${_cachedGroups.length} cached groups due to connection error',
            );
            return _cachedGroups;
          }
          return <Group>[];
        });
  }

  Future<String> createGroup({
    required String name,
    required List<String> memberUserIds,
  }) async {
    final shareCode = _generateShareCode();
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final doc = await _db.collection('groups').add({
      'name': name,
      'memberUserIds': memberUserIds,
      'createdAtMs': currentTime,
      'shareCode': shareCode,
    });

    // Add to cache immediately for better UX
    final newGroup = Group(
      id: doc.id,
      name: name,
      memberUserIds: memberUserIds,
      createdAtMs: currentTime,
      shareCode: shareCode,
    );

    // Update cache if it's for the same user
    if (memberUserIds.length == 1 && _cachedUserId == memberUserIds.first) {
      _cachedGroups = [newGroup, ..._cachedGroups];
      print('Added new group to cache: $name');
    }

    return doc.id;
  }

  Future<void> updateGroup({
    required String groupId,
    String? name,
    List<String>? memberUserIds,
  }) async {
    final Map<String, Object?> data = {};
    if (name != null) data['name'] = name;
    if (memberUserIds != null) data['memberUserIds'] = memberUserIds;
    if (data.isEmpty) return;
    await _db.collection('groups').doc(groupId).update(data);
  }

  Future<void> deleteGroup(String groupId) async {
    await _db.collection('groups').doc(groupId).delete();
  }

  // Expenses
  Stream<List<Expense>> watchExpenses(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromDoc(d.id, d.data())).toList(),
        );
  }

  Future<String> addExpense(Expense expense) async {
    final doc = await _db
        .collection('groups')
        .doc(expense.groupId)
        .collection('expenses')
        .add(expense.toJson());
    return doc.id;
  }

  Future<void> updateExpense(Expense expense) async {
    await _db
        .collection('groups')
        .doc(expense.groupId)
        .collection('expenses')
        .doc(expense.id)
        .update(expense.toJson());
  }

  Future<void> removeExpense({
    required String groupId,
    required String expenseId,
  }) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }

  Future<String?> joinGroupByCode({
    required String shareCode,
    required String userId,
  }) async {
    final query = await _db
        .collection('groups')
        .where('shareCode', isEqualTo: shareCode)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final groupDoc = query.docs.first;
    final groupId = groupDoc.id;
    final group = groupDoc.data();
    final currentMembers = List<String>.from(group['memberUserIds'] ?? []);
    if (currentMembers.contains(userId)) return groupId; // already a member
    currentMembers.add(userId);
    await _db.collection('groups').doc(groupId).update({
      'memberUserIds': currentMembers,
    });
    return groupId;
  }

  String _generateShareCode() {
    // Removed unused variable 'chars'
    final random = DateTime.now().millisecondsSinceEpoch % 1000000;
    return random.toString().padLeft(6, '0');
  }

  // Settlements
  Future<String> createGroupSettlement(GroupSettlement settlement) async {
    final doc = await _db
        .collection('groups')
        .doc(settlement.groupId)
        .collection('settlements')
        .add(settlement.toJson());
    return doc.id;
  }

  Stream<List<GroupSettlement>> watchGroupSettlements(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => GroupSettlement.fromDoc(d.id, d.data()))
              .toList(),
        );
  }

  Future<void> updateSettlementPayment({
    required String groupId,
    required String settlementId,
    required int paymentIndex,
    required SettlementPayment payment,
  }) async {
    final settlementRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .doc(settlementId);

    await _db.runTransaction((transaction) async {
      final settlementDoc = await transaction.get(settlementRef);
      if (!settlementDoc.exists) return;

      final data = settlementDoc.data()!;
      final paymentsData = List<dynamic>.from(data['payments'] ?? []);

      if (paymentIndex < paymentsData.length) {
        paymentsData[paymentIndex] = payment.toJson();

        // Check if all payments are complete
        final allComplete = paymentsData.every((p) => p['isCompleted'] == true);

        transaction.update(settlementRef, {
          'payments': paymentsData,
          if (allComplete && data['completedAtMs'] == null)
            'completedAtMs': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<void> deleteGroupSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .doc(settlementId)
        .delete();
  }
}

final Provider<FirestoreRepository> firestoreRepositoryProvider =
    Provider<FirestoreRepository>((ref) {
      return FirestoreRepository(FirebaseFirestore.instance);
    });
