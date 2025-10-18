import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/user_profile.dart';
import '../data/user_profile_repository.dart';
import '../auth/auth_repository.dart'; // For currentUserProvider
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../main.dart'; // For developerModeProvider and userProfileByIdProvider

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _isLoading = false;
  bool _hasChanges = false;
  bool _profileLoaded = false; // Add flag to prevent reload loops
  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _bioController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  void _loadProfile(UserProfile? profile) {
    if (profile != null && !_profileLoaded) {
      _displayNameController.text = profile.displayName;
      _phoneController.text = profile.phoneNumber ?? '';
      _bioController.text = profile.bio ?? '';
      _hasChanges = false;
      _profileLoaded = true;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final devMode = ref.read(developerModeProvider);
      if (devMode) {
        // ...existing code for developer mode...
        final currentProfile = ref.read(userProfileByIdProvider('dev_user_123'));
        final updatedProfile = UserProfile(
          id: 'dev_user_123',
          displayName: _displayNameController.text.trim(),
          email: currentProfile?.value?.email ?? 'developer@example.com',
          phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
          profileImageUrl: _selectedImagePath ?? currentProfile?.value?.profileImageUrl,
          createdAtMs: currentProfile?.value?.createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          preferences: currentProfile?.value?.preferences ?? {},
        );
        ref.read(developerUserProfilesProvider.notifier).updateProfile(updatedProfile);
        if (mounted) {
          setState(() {
            _hasChanges = false;
            _profileLoaded = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // In production mode, save to Firebase and update Firebase Auth displayName
        final currentUser = ref.read(currentUserProvider);
        final currentProfile = ref.read(currentUserProfileProvider).value;
        final displayName = _displayNameController.text.trim();
        final fbUser = fb.FirebaseAuth.instance.currentUser;
        if (fbUser != null && displayName.isNotEmpty) {
          // Update Firebase Auth displayName
          await fbUser.updateDisplayName(displayName);
        }
        if (currentProfile == null) {
          // Create new profile
          final newProfile = UserProfile(
            id: currentUser?.uid ?? 'unknown_user',
            displayName: displayName,
            email: currentUser?.email ?? '',
            phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
            profileImageUrl: _selectedImagePath, // Include selected image
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await ref.read(userProfileRepositoryProvider).saveUserProfile(newProfile);
        } else {
          // Update existing profile
          final updatedProfile = currentProfile.copyWith(
            displayName: displayName,
            phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
            profileImageUrl: _selectedImagePath ?? currentProfile.profileImageUrl,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await ref.read(userProfileRepositoryProvider).saveUserProfile(updatedProfile);
        }
        if (mounted) {
          setState(() {
            _hasChanges = false;
            _profileLoaded = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose Profile Picture',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImageSourceOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.pop(context);
                      final image = await _imagePicker.pickImage(source: ImageSource.camera);
                      if (image != null) {
                        setState(() {
                          _selectedImagePath = image.path;
                          _hasChanges = true;
                        });
                      }
                    },
                  ),
                  _buildImageSourceOption(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () async {
                      Navigator.pop(context);
                      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setState(() {
                          _selectedImagePath = image.path;
                          _hasChanges = true;
                        });
                      }
                    },
                  ),
                  if (_selectedImagePath != null || (ref.read(currentUserProfileProvider).value?.profileImageUrl != null))
                    _buildImageSourceOption(
                      icon: Icons.delete,
                      label: 'Remove',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedImagePath = null;
                          _hasChanges = true;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: color ?? Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color ?? Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devMode = ref.watch(developerModeProvider);
    
    if (devMode) {
      // In developer mode, use mock data
      final userProfile = ref.watch(userProfileByIdProvider('dev_user_123'));
      
      // Load profile data into form on first build
      if (userProfile != null && !_profileLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadProfile(userProfile.value);
        });
      }

  return _buildProfileContent(userProfile.value);
    } else {
      // In production mode, use real Firebase data
      final profileAsyncValue = ref.watch(currentUserProfileProvider);
      
      return profileAsyncValue.when(
        data: (profile) {
          // Load profile data into form
          if (profile != null && !_profileLoaded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadProfile(profile);
            });
          }

          return _buildProfileContent(profile);
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => _buildErrorState(error),
      );
    }
  }

  Widget _buildProfileContent(UserProfile? profile) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/settings'); // Fallback to settings page
            }
          },
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Picture Section
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage: _selectedImagePath != null
                            ? FileImage(File(_selectedImagePath!)) as ImageProvider
                            : (profile?.profileImageUrl != null 
                                ? NetworkImage(profile!.profileImageUrl!)
                                : null),
                          child: (_selectedImagePath == null && profile?.profileImageUrl == null)
                            ? Text(
                                profile?.initials ?? 'U',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              onPressed: _pickImage,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile?.email ?? 'user@example.com',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Display Name Field
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'Enter your display name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // Phone Number Field
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter your phone number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: 'Used for payment integrations like Swish',
                ),
                keyboardType: TextInputType.phone,
              ),
              
              const SizedBox(height: 16),
              
              // Bio Field
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell others about yourself',
                  prefixIcon: const Icon(Icons.edit),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
                maxLength: 150,
              ),
              
              const SizedBox(height: 24),
              
              // Profile Completion Status
              if (profile != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: profile.isProfileComplete 
                      ? Colors.green.shade50 
                      : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: profile.isProfileComplete 
                        ? Colors.green.shade200 
                        : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        profile.isProfileComplete 
                          ? Icons.check_circle 
                          : Icons.warning,
                        color: profile.isProfileComplete 
                          ? Colors.green.shade600 
                          : Colors.orange.shade600,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.isProfileComplete 
                                ? 'Profile Complete' 
                                : 'Profile Incomplete',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: profile.isProfileComplete 
                                  ? Colors.green.shade800 
                                  : Colors.orange.shade800,
                              ),
                            ),
                            if (!profile.isProfileComplete)
                              Text(
                                'Add a phone number to enable payment features',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Save Button (if on mobile or no changes detected in app bar)
              if (!_hasChanges || MediaQuery.of(context).size.width < 600)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Profile'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/settings'); // Fallback to settings page
            }
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load profile',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/settings'); // Fallback to settings page
                }
              },
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}