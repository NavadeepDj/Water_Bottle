import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:water_bottle/home_page.dart';

class SupabaseDataService {
  SupabaseClient get _client {
    try {
      return Supabase.instance.client;
    } catch (e) {
      throw Exception('Supabase not initialized: $e');
    }
  }

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // Check if Supabase is ready
  bool get isSupabaseReady {
    try {
      return Supabase.instance.client != null;
    } catch (e) {
      return false;
    }
  }

  // Get current Firebase user
  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  // Create or update user profile in Supabase
  Future<void> createOrUpdateUserProfile({
    required String displayName,
    String? photoURL,
    String? email,
  }) async {
    final user = currentFirebaseUser;
    if (user == null) throw Exception('No Firebase user authenticated');

    // Block placeholder names
    if (_isBlockedName(displayName)) {
      throw Exception('This name is not allowed. Please use your real name.');
    }

    try {
      await _client.from('user_profiles').upsert({
        'firebase_uid': user.uid,
        'display_name': displayName,
        'photo_url': photoURL,
        'email': email ?? user.email,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'firebase_uid');
    } catch (e) {
      rethrow;
    }
  }

  // Check if a name is blocked
  bool _isBlockedName(String name) {
    final blockedNames = [
      'john doe',
      'jane smith',
      'john smith',
      'jane doe',
      'test user',
      'sample user',
      'demo user',
      'example user',
    ];
    return blockedNames.contains(name.toLowerCase());
  }

  // Create a new water fetching post
  Future<void> createWaterFetchPost({
    required String message,
    required String fetchType,
    String? partnerUserId,
    required double points,
  }) async {
    final user = currentFirebaseUser;
    if (user == null) throw Exception('No Firebase user authenticated');

    try {
      // For Together mode, store the partner's display name directly
      // since partnerUserId is actually the display name from the dropdown
      String? partnerDisplayName;
      if (fetchType == 'Together' &&
          partnerUserId != null &&
          partnerUserId != 'Select users') {
        partnerDisplayName = partnerUserId;
      }

      await _client.from('water_fetch_posts').insert({
        'firebase_uid': user.uid,
        'message': message,
        'fetch_type': fetchType,
        'partner_user_id': partnerDisplayName, // Store display name directly
        'points': points,
        'verification_status': 'pending',
        'verified_by': [],
        'rejected_by': [],
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      rethrow;
    }
  }

  // Get all water fetching posts
  Future<List<WaterActivity>> getAllWaterFetchPosts() async {
    try {
      final response = await _client
          .from('water_fetch_posts')
          .select('*, user_profiles!inner(*)')
          .order('created_at', ascending: false);

      List<WaterActivity> activities = [];

      for (final post in response) {
        final userProfile = post['user_profiles'] as Map<String, dynamic>;

        // Get partner user info for Together mode posts
        String? partnerUserName;
        if (post['partner_user_id'] != null &&
            post['fetch_type'] == 'Together') {
          // partner_user_id now stores the display name directly
          partnerUserName = post['partner_user_id'];
        }

        activities.add(
          WaterActivity(
            id: post['id']?.toString(),
            name: userProfile['display_name'] ?? 'Unknown User',
            imageUrl: userProfile['photo_url'] ?? '',
            message: post['message'] ?? '',
            date: DateTime.parse(post['created_at']),
            points: (post['points'] ?? 0.0).toDouble(),
            verificationStatus: _parseVerificationStatus(
              post['verification_status'],
            ),
            verifiedBy: List<String>.from(post['verified_by'] ?? []),
            rejectedBy: List<String>.from(post['rejected_by'] ?? []),
            partnerUserName: partnerUserName,
            fetchType: post['fetch_type'] ?? 'Single',
            ownerFirebaseUid: post['firebase_uid'] as String?,
          ),
        );
      }

      return activities;
    } catch (e) {
      return [];
    }
  }

  // Get user profile by Firebase UID
  Future<Map<String, dynamic>?> getUserProfile(String firebaseUid) async {
    try {
      final response =
          await _client
              .from('user_profiles')
              .select()
              .eq('firebase_uid', firebaseUid)
              .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  // Get all users (excluding current user)
  Future<List<String>> getAllUsersExceptCurrent() async {
    final user = currentFirebaseUser;
    if (user == null) return [];

    try {
      final response = await _client
          .from('user_profiles')
          .select('display_name')
          .neq('firebase_uid', user.uid);

      return response
          .map<String>((profile) => profile['display_name'] ?? 'Unknown User')
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Verify a water fetch post
  Future<void> verifyWaterFetchPost(String postId, String verifierName) async {
    try {
      final response =
          await _client
              .from('water_fetch_posts')
              .select('verified_by, rejected_by')
              .eq('id', postId)
              .single();

      List<String> verifiedBy = List<String>.from(
        response['verified_by'] ?? [],
      );
      List<String> rejectedBy = List<String>.from(
        response['rejected_by'] ?? [],
      );

      // Remove from rejected list if previously rejected
      rejectedBy.remove(verifierName);

      // Add to verified list
      if (!verifiedBy.contains(verifierName)) {
        verifiedBy.add(verifierName);
      }

      await _client
          .from('water_fetch_posts')
          .update({
            'verification_status': 'verified',
            'verified_by': verifiedBy,
            'rejected_by': rejectedBy,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', postId);
    } catch (e) {
      print('Error verifying post: $e');
      rethrow;
    }
  }

  // Reject a water fetch post
  Future<void> rejectWaterFetchPost(String postId, String rejectorName) async {
    try {
      final response =
          await _client
              .from('water_fetch_posts')
              .select('verified_by, rejected_by')
              .eq('id', postId)
              .single();

      List<String> verifiedBy = List<String>.from(
        response['verified_by'] ?? [],
      );
      List<String> rejectedBy = List<String>.from(
        response['rejected_by'] ?? [],
      );

      // Remove from verified list if previously verified
      verifiedBy.remove(rejectorName);

      // Add to rejected list
      if (!rejectedBy.contains(rejectorName)) {
        rejectedBy.add(rejectorName);
      }

      await _client
          .from('water_fetch_posts')
          .update({
            'verification_status': 'rejected',
            'verified_by': verifiedBy,
            'rejected_by': rejectedBy,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', postId);
    } catch (e) {
      print('Error rejecting post: $e');
      rethrow;
    }
  }

  // Delete a water fetch post by ID
  Future<void> deleteWaterFetchPost(String postId) async {
    try {
      // Supabase `id` column is numeric (BIGSERIAL). Try to pass an int when
      // possible so the query matches correctly. Fall back to the original
      // string if parsing fails.
      final int? idAsInt = int.tryParse(postId ?? '');
      final dynamic idFilter = idAsInt ?? postId;

      await _client.from('water_fetch_posts').delete().eq('id', idFilter);

      // Verify deletion: try to select the row back. If it still exists, the
      // delete likely failed due to RLS or permissions.
      try {
        // Use maybeSingle() which returns null when no rows match. This
        // avoids PostgrestException when the result contains 0 rows and
        // treats that as deletion success.
        final check = await _client
            .from('water_fetch_posts')
            .select()
            .eq('id', idFilter)
            .maybeSingle();

        if (check != null) {
          // Row still exists after delete attempt
          throw Exception('Delete failed or not permitted by RLS/policies');
        }
      } catch (verifyError) {
        // Surface any unexpected verification errors
        rethrow;
      }
    } catch (e) {
      print('Error deleting post: $e');
      rethrow;
    }
  }

  // Helper method to parse verification status
  VerificationStatus _parseVerificationStatus(String? status) {
    switch (status) {
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }

  // Initialize user profile after Firebase auth
  Future<void> initializeUserProfile() async {
    final user = currentFirebaseUser;
    if (user == null) {
      print('❌ No Firebase user found for profile initialization');
      return;
    }

    try {
      print('🔄 Checking if profile exists for: ${user.email}');

      // Check if profile already exists
      final existingProfile = await getUserProfile(user.uid);
      if (existingProfile == null) {
        print('🔄 Creating new profile for: ${user.email}');
        // Create new profile with Firebase display name (full name from signup)
        await createOrUpdateUserProfile(
          displayName: user.displayName ?? 'User ${user.uid.substring(0, 8)}',
          photoURL: user.photoURL,
          email: user.email,
        );
        print('✅ New profile created for: ${user.email}');
      } else {
        print('✅ Profile already exists for: ${user.email}');
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          // Update existing profile with Firebase display name if it's different
          final currentName = existingProfile['display_name'] as String?;
          if (currentName != user.displayName) {
            print('🔄 Updating profile name for: ${user.email}');
            await createOrUpdateUserProfile(
              displayName: user.displayName!,
              photoURL: user.photoURL,
              email: user.email,
            );
            print('✅ Profile updated for: ${user.email}');
          }
        }
      }
    } catch (e) {
      print('❌ Error initializing user profile: $e');
    }
  }
}
