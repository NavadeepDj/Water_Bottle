import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:water_bottle/services/app_events.dart';
import 'dart:async';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  List<LeaderboardUser> _leaderboardUsers = [];
  bool _isLoading = true;
  String? _error;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  StreamSubscription<void>? _dataChangedSub;

  @override
  void initState() {
    super.initState();
    _loadLeaderboardData();

    // Listen for app-level data change events and reload leaderboard when
    // posts are created/updated/deleted elsewhere in the app.
    _dataChangedSub = AppEvents.onDataChanged.listen((_) {
      _loadLeaderboardData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when page becomes visible
    _loadLeaderboardData();
  }

  @override
  void dispose() {
    _dataChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLeaderboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final client = Supabase.instance.client;

      // Fetch all users with their total points
      final response = await client
          .from('user_profiles')
          .select('display_name, photo_url, firebase_uid')
          .order('display_name');

      final List<LeaderboardUser> users = [];

      for (final user in response) {
        // Calculate total points for each user
        double totalPoints = 0.0;
        int verifiedPosts = 0;

        // Get posts where user is the poster
        final postsAsPoster = await client
            .from('water_fetch_posts')
            .select('points, verification_status, fetch_type, partner_user_id')
            .eq('firebase_uid', user['firebase_uid']);

        if (postsAsPoster != null) {
          for (final post in postsAsPoster) {
            if (post['verification_status'] == 'verified') {
              totalPoints += (post['points'] ?? 0.0).toDouble();
              verifiedPosts++;
            }
          }
        }

        // Get posts where user is the partner in Together mode
        final postsAsPartner = await client
            .from('water_fetch_posts')
            .select('points, verification_status, fetch_type, partner_user_id')
            .eq('partner_user_id', user['display_name'])
            .eq('fetch_type', 'Together');

        if (postsAsPartner != null) {
          for (final post in postsAsPartner) {
            if (post['verification_status'] == 'verified') {
              // Partner gets the per-user points stored in the post (0.25 or 0.5)
              totalPoints += (post['points'] ?? 0.0).toDouble();
              verifiedPosts++;
            }
          }
        }

        users.add(
          LeaderboardUser(
            displayName: user['display_name'] ?? 'Unknown User',
            photoUrl: user['photo_url'] ?? 'https://picsum.photos/150/150',
            totalPoints: totalPoints,
            verifiedPosts: verifiedPosts,
            firebaseUid: user['firebase_uid'],
          ),
        );
      }

      // Sort by total points (descending)
      users.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

      setState(() {
        _leaderboardUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load leaderboard: $e';
        _isLoading = false;
      });
    }
  }

  String _getRankText(int index) {
    switch (index) {
      case 0:
        return '1st';
      case 1:
        return '2nd';
      case 2:
        return '3rd';
      default:
        return '${index + 1}th';
    }
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFD700); // Gold
      case 1:
        return const Color(0xFFC0C0C0); // Silver
      case 2:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return const Color(0xFF617989); // Default
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: Color(0xFF111518),
                      size: 24,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Leaderboard',
                      style: const TextStyle(
                        color: Color(0xFF111518),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        letterSpacing: -0.015,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: _loadLeaderboardData,
                    icon: const Icon(
                      Icons.refresh,
                      color: Color(0xFF111518),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            // Leaderboard content
            Expanded(child: _buildLeaderboardContent()),

            // Bottom Navigation
            _buildBottomNavigationBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF42AAF0)),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Error loading leaderboard',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLeaderboardData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_leaderboardUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No leaderboard data yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start posting water activities to see rankings!',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboardData,
      color: const Color(0xFF42AAF0),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _leaderboardUsers.length,
        itemBuilder: (context, index) {
          final user = _leaderboardUsers[index];
          final isCurrentUser =
              user.firebaseUid == _firebaseAuth.currentUser?.uid;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrentUser ? const Color(0xFFF0F8FF) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border:
                    isCurrentUser
                        ? Border.all(color: const Color(0xFF42AAF0), width: 2)
                        : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Rank
                  SizedBox(
                    width: 60,
                    child: Text(
                      _getRankText(index),
                      style: TextStyle(
                        color: _getRankColor(index),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // User info
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              user.displayName,
                              style: TextStyle(
                                color: const Color(0xFF111518),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isCurrentUser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF42AAF0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'You',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${user.totalPoints.toStringAsFixed(1)} points • ${user.verifiedPosts} verified posts',
                          style: const TextStyle(
                            color: Color(0xFF617989),
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Profile image with initials fallback
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFF42AAF0),
                    ),
                    child:
                        user.photoUrl.isNotEmpty &&
                                user.photoUrl != 'https://picsum.photos/150/150'
                            ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                user.photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildInitialsAvatar(user.displayName);
                                },
                              ),
                            )
                            : _buildInitialsAvatar(user.displayName),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0F3F4), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Home tab
              Expanded(
                child: GestureDetector(
                  onTap:
                      () => Navigator.of(context).pushReplacementNamed('/home'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.home_outlined,
                        color: const Color(0xFF637988),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Home',
                        style: const TextStyle(
                          color: Color(0xFF637988),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.015,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Leaderboard tab (active)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events,
                      color: const Color(0xFF111518),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Leaderboard',
                      style: const TextStyle(
                        color: Color(0xFF111518),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.015,
                      ),
                    ),
                  ],
                ),
              ),
              // Profile tab
              Expanded(
                child: GestureDetector(
                  onTap:
                      () => Navigator.of(
                        context,
                      ).pushReplacementNamed('/profile'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: const Color(0xFF637988),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Profile',
                        style: const TextStyle(
                          color: Color(0xFF637988),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.015,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar(String displayName) {
    return Center(
      child: Text(
        _getInitials(displayName),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getInitials(String displayName) {
    if (displayName.trim().isEmpty) {
      return '?';
    }

    final names = displayName.trim().split(' ');
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    } else if (names.length == 1) {
      return names[0][0].toUpperCase();
    }
    return '?';
  }
}

class LeaderboardUser {
  final String displayName;
  final String photoUrl;
  final double totalPoints;
  final int verifiedPosts;
  final String firebaseUid;

  LeaderboardUser({
    required this.displayName,
    required this.photoUrl,
    required this.totalPoints,
    required this.verifiedPosts,
    required this.firebaseUid,
  });
}
