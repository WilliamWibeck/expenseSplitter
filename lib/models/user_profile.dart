class UserProfile {
  final String id;
  final String displayName;
  final String email;
  final String? phoneNumber;
  final String? profileImageUrl;
  final String? bio;
  final int createdAtMs;
  final int updatedAtMs;
  final Map<String, dynamic> preferences;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.phoneNumber,
    this.profileImageUrl,
    this.bio,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.preferences = const {},
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      bio: json['bio'] as String?,
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      preferences: Map<String, dynamic>.from(json['preferences'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'phoneNumber': phoneNumber,
      'profileImageUrl': profileImageUrl,
      'bio': bio,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'preferences': preferences,
    };
  }

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? email,
    String? phoneNumber,
    String? profileImageUrl,
    String? bio,
    int? createdAtMs,
    int? updatedAtMs,
    Map<String, dynamic>? preferences,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      preferences: preferences ?? this.preferences,
    );
  }

  /// Get user initials for avatar display
  String get initials {
    final names = displayName.trim().split(' ');
    if (names.length >= 2) {
      return '${names.first[0]}${names.last[0]}'.toUpperCase();
    } else if (names.isNotEmpty) {
      return names.first.substring(0, 1).toUpperCase();
    }
    return email.substring(0, 1).toUpperCase();
  }

  /// Check if user has completed their profile
  bool get isProfileComplete {
    return displayName.isNotEmpty && 
           phoneNumber != null && 
           phoneNumber!.isNotEmpty;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile &&
        other.id == id &&
        other.displayName == displayName &&
        other.email == email &&
        other.phoneNumber == phoneNumber &&
        other.profileImageUrl == profileImageUrl &&
        other.bio == bio &&
        other.createdAtMs == createdAtMs &&
        other.updatedAtMs == updatedAtMs;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      displayName,
      email,
      phoneNumber,
      profileImageUrl,
      bio,
      createdAtMs,
      updatedAtMs,
    );
  }

  @override
  String toString() {
    return 'UserProfile(id: $id, displayName: $displayName, email: $email, phoneNumber: $phoneNumber)';
  }
}