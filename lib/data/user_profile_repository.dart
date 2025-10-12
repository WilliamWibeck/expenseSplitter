import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class UserProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Get user profile by ID
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        return UserProfile.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }
      return null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  /// Create or update user profile
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      final data = profile.toJson();
      data.remove('id'); // Don't store ID in document data
      
      await _firestore.collection('users').doc(profile.id).set(
        data,
        SetOptions(merge: true),
      );
    } catch (e) {
      print('Error saving user profile: $e');
      throw Exception('Failed to save user profile');
    }
  }

  /// Update specific profile fields
  Future<void> updateUserProfile(String userId, Map<String, dynamic> updates) async {
    try {
      updates['updatedAtMs'] = DateTime.now().millisecondsSinceEpoch;
      await _firestore.collection('users').doc(userId).update(updates);
    } catch (e) {
      print('Error updating user profile: $e');
      throw Exception('Failed to update user profile');
    }
  }

  /// Search users by display name or email
  Future<List<UserProfile>> searchUsers(String query) async {
    try {
      if (query.isEmpty) return [];
      
      // Search by display name
      final nameQuery = await _firestore
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThan: query + '\uf8ff')
          .limit(10)
          .get();

      // Search by email
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: query.toLowerCase())
          .where('email', isLessThan: query.toLowerCase() + '\uf8ff')
          .limit(10)
          .get();

      final Set<UserProfile> results = {};
      
      // Add name search results
      for (final doc in nameQuery.docs) {
        if (doc.data().isNotEmpty) {
          results.add(UserProfile.fromJson({
            'id': doc.id,
            ...doc.data(),
          }));
        }
      }

      // Add email search results
      for (final doc in emailQuery.docs) {
        if (doc.data().isNotEmpty) {
          results.add(UserProfile.fromJson({
            'id': doc.id,
            ...doc.data(),
          }));
        }
      }

      return results.toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  /// Get multiple user profiles by IDs
  Future<Map<String, UserProfile>> getUserProfiles(List<String> userIds) async {
    try {
      if (userIds.isEmpty) return {};
      
      final Map<String, UserProfile> profiles = {};
      
      // Firestore has a limit of 10 documents per batch
      for (int i = 0; i < userIds.length; i += 10) {
        final batch = userIds.skip(i).take(10).toList();
        final query = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
            
        for (final doc in query.docs) {
          if (doc.data().isNotEmpty) {
            profiles[doc.id] = UserProfile.fromJson({
              'id': doc.id,
              ...doc.data(),
            });
          }
        }
      }
      
      return profiles;
    } catch (e) {
      print('Error getting user profiles: $e');
      return {};
    }
  }

  /// Watch user profile changes
  Stream<UserProfile?> watchUserProfile(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserProfile.fromJson({
          'id': doc.id,
          ...doc.data()!,
        });
      }
      return null;
    });
  }
}

// Provider for UserProfile repository
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

// Provider for current user's profile
final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  // TODO: Get actual user ID from auth
  const userId = 'dev_user_123';
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.watchUserProfile(userId);
});

// Provider for user profiles by ID (cached)
final userProfileProvider = FutureProvider.family<UserProfile?, String>((ref, userId) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.getUserProfile(userId);
});

// Provider for multiple user profiles
final userProfilesProvider = FutureProvider.family<Map<String, UserProfile>, List<String>>((ref, userIds) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.getUserProfiles(userIds);
});

// Provider for user search
final userSearchProvider = FutureProvider.family<List<UserProfile>, String>((ref, query) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.searchUsers(query);
});