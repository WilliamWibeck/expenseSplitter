import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod/riverpod.dart';
import '../models/group.dart';
import '../models/expense.dart';

class FirestoreRepository {
  FirestoreRepository(this._db);
  final FirebaseFirestore _db;

  // Groups
  Stream<Group> watchGroup(String groupId) {
    return _db.collection('groups').doc(groupId).snapshots().map((d) => Group.fromDoc(d.id, d.data() ?? {}));
  }
  Stream<List<Group>> watchGroups(String userId) {
    return _db
        .collection('groups')
        .where('memberUserIds', arrayContains: userId)
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Group.fromDoc(d.id, d.data())).toList());
  }

  Future<String> createGroup({required String name, required List<String> memberUserIds}) async {
    final shareCode = _generateShareCode();
    final doc = await _db.collection('groups').add({
      'name': name,
      'memberUserIds': memberUserIds,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'shareCode': shareCode,
    });
    return doc.id;
  }

  Future<void> updateGroup({required String groupId, String? name, List<String>? memberUserIds}) async {
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
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Expense.fromDoc(d.id, d.data())).toList());
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

  Future<void> removeExpense({required String groupId, required String expenseId}) async {
    await _db.collection('groups').doc(groupId).collection('expenses').doc(expenseId).delete();
  }

  Future<String?> joinGroupByCode({required String shareCode, required String userId}) async {
    final query = await _db.collection('groups').where('shareCode', isEqualTo: shareCode).limit(1).get();
    if (query.docs.isEmpty) return null;
    final groupDoc = query.docs.first;
    final groupId = groupDoc.id;
    final group = groupDoc.data();
    final currentMembers = List<String>.from(group['memberUserIds'] ?? []);
    if (currentMembers.contains(userId)) return groupId; // already a member
    currentMembers.add(userId);
    await _db.collection('groups').doc(groupId).update({'memberUserIds': currentMembers});
    return groupId;
  }

  String _generateShareCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch % 1000000;
    return random.toString().padLeft(6, '0');
  }
}

final Provider<FirestoreRepository> firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository(FirebaseFirestore.instance);
});


