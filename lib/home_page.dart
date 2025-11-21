import 'package:flutter/material.dart';
import 'package:water_bottle/services/firebase_auth_service.dart';
import 'package:water_bottle/services/supabase_data_service.dart';
import 'package:water_bottle/services/notification_service.dart';
import 'package:water_bottle/services/app_events.dart';

enum VerificationStatus { pending, verified, rejected }

// Optimized widget for fetch type selection to prevent unnecessary rebuilds
class FetchTypeButton extends StatelessWidget {
  final String label;
  final String selected;
  final VoidCallback onTap;

  const FetchTypeButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    bool isSelected = selected == label;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow:
                isSelected
                    ? const [
                      BoxShadow(
                        color: Color(
                          0x1A000000,
                        ), // Using hex for black.withOpacity(0.1)
                        blurRadius: 4,
                        offset: Offset(0, 0),
                      ),
                    ]
                    : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color:
                    isSelected
                        ? const Color(0xFF111518)
                        : const Color(0xFF617989),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WaterActivity {
  final String? id; // Supabase post ID
  final String name;
  final String imageUrl;
  final String message;
  final DateTime date;
  final double points;
  final VerificationStatus verificationStatus;
  final List<String> verifiedBy;
  final List<String> rejectedBy;
  final String? partnerUserName; // Partner user name for Together mode
  final String fetchType; // 'Single' or 'Together'
  final String? ownerFirebaseUid; // Post owner's Firebase UID

  WaterActivity({
    this.id,
    required this.name,
    required this.imageUrl,
    required this.message,
    required this.date,
    required this.points,
    VerificationStatus? verificationStatus,
    List<String>? verifiedBy,
    List<String>? rejectedBy,
    this.partnerUserName,
    this.fetchType = 'Single',
    this.ownerFirebaseUid,
  }) : verificationStatus = verificationStatus ?? VerificationStatus.pending,
       verifiedBy = verifiedBy ?? const [],
       rejectedBy = rejectedBy ?? const [];
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Firebase service for user management
  final FirebaseAuthService _authService = FirebaseAuthService();

  // Supabase data service for data operations
  final SupabaseDataService _dataService = SupabaseDataService();

  // Notification service for sending notifications
  final NotificationService _notificationService = NotificationService();

  // Loading states for better UX
  bool _isPosting = false;

  // Activities list - will be populated from Supabase
  List<WaterActivity> _activities = [];

  // Form controllers
  final TextEditingController _messageController = TextEditingController();

  // Use ValueNotifier for better performance - only rebuilds specific parts
  final ValueNotifier<String> _fetchType = ValueNotifier(
    'Single',
  ); // 'Single' or 'Together'
  final ValueNotifier<String> _selectedUser = ValueNotifier('Select users');
  final ValueNotifier<int> _bottleCount = ValueNotifier(1);

  // Cache for performance
  bool _isModalOpen = false;

  // Dynamic users from database (excluding current user)
  List<String> _availableUsers = ['Select users'];

  // Pre-built dropdown items to prevent rebuilding
  late List<DropdownMenuItem<String>> _userDropdownItems;

  @override
  void initState() {
    super.initState();

    // Add listener to message controller for real-time character count
    _messageController.addListener(() {
      setState(() {
        // This will rebuild the widget to update the character count
      });
    });

    // Listen to auth state changes
    _authService.authStateChanges.listen((user) {
      if (user != null) {
        // User signed in, initialize data
        _initializeData();
      } else {
        // User signed out, load sample data
        _loadSampleData();
      }
    });

    // Initialize data after a short delay to ensure Firebase and Supabase are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _initializeData();
      });
    });
  }

  // Initialize data after Firebase auth is ready
  Future<void> _initializeData() async {
    try {
      // Check if Supabase is ready
      if (!_dataService.isSupabaseReady) {
        print('Supabase not ready, loading sample data');
        _loadSampleData();
        return;
      }

      // Check if user is authenticated
      if (_authService.currentUser != null) {
        // Initialize user profile in Supabase after Firebase auth
        await _initializeUserProfile();

        // Load data from Supabase
        await _loadDataFromSupabase();
      } else {
        // Load sample data if no user is authenticated
        _loadSampleData();
      }
    } catch (e) {
      print('Error initializing data: $e');
      // Fallback to sample data
      _loadSampleData();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _fetchType.dispose();
    _selectedUser.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when page becomes visible
    _refreshDataIfNeeded();
  }

  // Refresh data if needed when page becomes visible
  void _refreshDataIfNeeded() {
    // Only refresh if we have a user and Supabase is ready
    if (_authService.currentUser != null && _dataService.isSupabaseReady) {
      _loadDataFromSupabase();
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activityDate = DateTime(date.year, date.month, date.day);

    if (activityDate == today) {
      return 'Today';
    } else if (activityDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${_getMonthName(date.month)} ${date.day}';
    }
  }

  // Format time as HH:MM (24-hour) with leading zeros
  String _formatTime(DateTime date) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    final hh = twoDigits(date.hour);
    final mm = twoDigits(date.minute);
    return '$hh:$mm';
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  // Group activities by date
  Map<String, List<WaterActivity>> _groupActivitiesByDate() {
    Map<String, List<WaterActivity>> grouped = {};

    for (var activity in _activities) {
      String dateKey = _formatDate(activity.date);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(activity);
    }

    return grouped;
  }

  // Calculate total points for a date group
  double _calculateTotalPoints(List<WaterActivity> activities) {
    return activities.fold(0.0, (sum, activity) {
      if (activity.fetchType == 'Together' &&
          activity.partnerUserName != null) {
        // Total points across both users for a Together post
        return sum + (activity.points * 2);
      } else {
        // Single mode posts contribute their per-user points
        return sum + activity.points;
      }
    });
  }

  // Calculate total points for a specific user
  double _calculateUserPoints(String userName) {
    return _activities.fold(0.0, (sum, activity) {
      // Only count verified posts
      if (activity.verificationStatus != VerificationStatus.verified) {
        return sum;
      }

      // Check if this user is involved in the activity
      bool isUserInvolved = false;
      double pointsToAdd = 0.0;

      if (activity.name == userName) {
        // User is the poster
        isUserInvolved = true;
        pointsToAdd = activity.points;
      } else if (activity.fetchType == 'Together' &&
          activity.partnerUserName == userName) {
        // User is the partner in Together mode
        isUserInvolved = true;
        pointsToAdd = activity.points; // Partner gets same per-user points
      }

      return isUserInvolved ? sum + pointsToAdd : sum;
    });
  }

  // Get all unique users who have posted activities
  List<String> _getAllUsers() {
    final users = _activities.map((activity) => activity.name).toSet().toList();
    users.removeWhere((user) => user == 'Current User');
    return users;
  }

  // Initialize user profile in Supabase
  Future<void> _initializeUserProfile() async {
    try {
      print('🔄 Initializing user profile...');
      await _dataService.initializeUserProfile();
      print('✅ User profile initialized successfully');
    } catch (e) {
      print('❌ Error initializing user profile: $e');
    }
  }

  // Load data from Supabase
  Future<void> _loadDataFromSupabase() async {
    try {
      print('🔄 Loading data from Supabase...');

      // Load water fetch posts
      final posts = await _dataService.getAllWaterFetchPosts();
      print('✅ Loaded ${posts.length} posts from Supabase');

      setState(() {
        _activities = posts;
      });

      // Load users for dropdown
      await _loadUsersFromDatabase();
      print('✅ Users loaded successfully');
    } catch (e) {
      print('❌ Error loading data from Supabase: $e');
      // Fallback to sample data if Supabase fails
      _loadSampleData();
    }
  }

  // Load sample data as fallback
  void _loadSampleData() {
    _activities = [];
  }

  // Load users from database and build dropdown items
  Future<void> _loadUsersFromDatabase() async {
    try {
      // Get users from Supabase
      final users = await _dataService.getAllUsersExceptCurrent();

      if (users.isEmpty) {
        // No users available in database
        setState(() {
          _availableUsers = ['Select users'];
        });

        // Build dropdown items
        _userDropdownItems =
            _availableUsers.map((String user) {
              return DropdownMenuItem<String>(
                value: user,
                child: Text(
                  user,
                  style: TextStyle(
                    color:
                        user == 'Select users'
                            ? const Color(0xFF617989)
                            : const Color(0xFF111518),
                    fontSize: 16,
                  ),
                ),
              );
            }).toList();
      } else {
        // Users available - update the list
        setState(() {
          _availableUsers = ['Select users', ...users];
        });

        // Build dropdown items
        _userDropdownItems =
            _availableUsers.map((String user) {
              return DropdownMenuItem<String>(
                value: user,
                child: Text(
                  user,
                  style: TextStyle(
                    color:
                        user == 'Select users'
                            ? const Color(0xFF617989)
                            : const Color(0xFF111518),
                    fontSize: 16,
                  ),
                ),
              );
            }).toList();
      }
    } catch (e) {
      // Show error state
      setState(() {
        _availableUsers = ['Select users', 'Error loading users'];
      });

      _userDropdownItems =
          _availableUsers.map((String user) {
            final isError = user == 'Error loading users';
            return DropdownMenuItem<String>(
              value: user,
              enabled: !isError,
              child: Text(
                user,
                style: TextStyle(
                  color:
                      isError
                          ? const Color(0xFFE74C3C)
                          : user == 'Select users'
                          ? const Color(0xFF617989)
                          : const Color(0xFF111518),
                  fontSize: 16,
                ),
              ),
            );
          }).toList();
    }
  }

  Future<void> _verifyActivity(WaterActivity activity) async {
    try {
      // Get current user's name for verification
      final currentUserName =
          _authService.getCurrentUserProfile()?['displayName'] ??
          'Current User';

      // Check if current user is trying to verify their own activity
      if (activity.name == currentUserName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot verify your own activity'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Verify in Supabase if we have a post ID
      if (activity.id != null) {
        await _dataService.verifyWaterFetchPost(activity.id!, currentUserName);
      }

      // Update local state
      final index = _activities.indexOf(activity);
      if (index != -1) {
        setState(() {
          _activities[index] = WaterActivity(
            id: activity.id,
            name: activity.name,
            imageUrl: activity.imageUrl,
            message: activity.message,
            date: activity.date,
            points: activity.points, // Keep original points
            verificationStatus: VerificationStatus.verified,
            verifiedBy: [...activity.verifiedBy, currentUserName],
            rejectedBy: activity.rejectedBy,
            partnerUserName: activity.partnerUserName,
            fetchType: activity.fetchType,
            ownerFirebaseUid: activity.ownerFirebaseUid,
          );
        });
      }

      // Show success message with dynamic points info
      if (mounted) {
        if (activity.fetchType == 'Together' &&
            activity.partnerUserName != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Verified! ${activity.name} & ${activity.partnerUserName} both get ${activity.points} points each.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Verified! ${activity.name} gets ${activity.points} point${activity.points == 1.0 ? '' : 's'}.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Notify post owner about verification (non-blocking)
      try {
        final ownerUid = activity.ownerFirebaseUid;
        if (ownerUid != null && ownerUid.isNotEmpty) {
          await _notificationService.sendVerificationNotification(
            postOwnerUid: ownerUid,
            verifierName: currentUserName,
            postMessage: activity.message,
          );
        }
      } catch (e) {
        print('Notification error (verify): $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectActivity(WaterActivity activity) async {
    try {
      // Get current user's name for rejection
      final currentUserName =
          _authService.getCurrentUserProfile()?['displayName'] ??
          'Current User';

      // Check if current user is trying to reject their own activity
      if (activity.name == currentUserName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot reject your own activity'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Reject in Supabase if we have a post ID
      if (activity.id != null) {
        await _dataService.rejectWaterFetchPost(activity.id!, currentUserName);
      }

      // Update local state
      final index = _activities.indexOf(activity);
      if (index != -1) {
        setState(() {
          _activities[index] = WaterActivity(
            id: activity.id,
            name: activity.name,
            imageUrl: activity.imageUrl,
            message: activity.message,
            date: activity.date,
            points: 0.0, // No points for rejected activities
            verificationStatus: VerificationStatus.rejected,
            verifiedBy: activity.verifiedBy,
            rejectedBy: [...activity.rejectedBy, currentUserName],
            partnerUserName: activity.partnerUserName,
            fetchType: activity.fetchType,
            ownerFirebaseUid: activity.ownerFirebaseUid,
          );
        });
      }

      // Show rejection message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Rejected! ${activity.name} gets 0 points.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Notify post owner about rejection (non-blocking)
      try {
        final ownerUid = activity.ownerFirebaseUid;
        if (ownerUid != null && ownerUid.isNotEmpty) {
          await _notificationService.sendRejectionNotification(
            postOwnerUid: ownerUid,
            rejectorName: currentUserName,
            postMessage: activity.message,
          );
        }
      } catch (e) {
        print('Notification error (reject): $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showVerifiedList(WaterActivity activity) {
    // Multiple safety checks for verifiedBy list
    List<String> verifiedBy;
    try {
      verifiedBy = activity.verifiedBy ?? const [];
    } catch (e) {
      verifiedBy = const [];
    }

    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Verified by ${verifiedBy.length} users',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (verifiedBy.isNotEmpty)
                  ...verifiedBy.map(
                    (user) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(user, style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  const Text(
                    'No verifications yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
              ],
            ),
          ),
    );
  }

  void _showRejectedList(WaterActivity activity) {
    // Multiple safety checks for rejectedBy list
    List<String> rejectedBy;
    try {
      rejectedBy = activity.rejectedBy ?? const [];
    } catch (e) {
      rejectedBy = const [];
    }

    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cancel, color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Rejected by ${rejectedBy.length} users',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rejectedBy.isNotEmpty)
                  ...rejectedBy.map(
                    (user) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.cancel, color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Text(user, style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  const Text(
                    'No rejections yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
              ],
            ),
          ),
    );
  }

  void _showEvaluationHistory(WaterActivity activity) {
    // Multiple safety checks for both lists
    List<String> verifiedBy;
    List<String> rejectedBy;
    try {
      verifiedBy = activity.verifiedBy ?? const [];
      rejectedBy = activity.rejectedBy ?? const [];
    } catch (e) {
      verifiedBy = const [];
      rejectedBy = const [];
    }

    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history, color: Colors.blue, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Evaluation History',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Verified section
                if (verifiedBy.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Verified by ${verifiedBy.length} users:',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...verifiedBy.map(
                    (user) => Padding(
                      padding: const EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Text(
                        '✓ $user',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Rejected section
                if (rejectedBy.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.cancel, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Rejected by ${rejectedBy.length} users:',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...rejectedBy.map(
                    (user) => Padding(
                      padding: const EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Text(
                        '✗ $user',
                        style: const TextStyle(fontSize: 14, color: Colors.red),
                      ),
                    ),
                  ),
                ],

                if (verifiedBy.isEmpty && rejectedBy.isEmpty)
                  const Text(
                    'No evaluations yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildActivityItem(WaterActivity activity) {
    // Ensure verification status has a default value with multiple safety checks
    VerificationStatus status;
    try {
      status = activity.verificationStatus ?? VerificationStatus.pending;
    } catch (e) {
      status = VerificationStatus.pending;
    }

    // Ensure verifiedBy and rejectedBy lists are safe
    List<String> verifiedBy;
    List<String> rejectedBy;
    try {
      verifiedBy = activity.verifiedBy ?? const [];
      rejectedBy = activity.rejectedBy ?? const [];
    } catch (e) {
      verifiedBy = const [];
      rejectedBy = const [];
    }

    final currentUserName =
        _authService.getCurrentUserProfile()?['displayName'] ?? 'Current User';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Profile image with initials fallback
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF42AAF0),
            ),
            child:
                activity.imageUrl.isNotEmpty &&
                        activity.imageUrl != 'https://picsum.photos/150/150'
                    ? ClipOval(
                      child: Image.network(
                        activity.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildInitialsAvatar(activity.name);
                        },
                      ),
                    )
                    : _buildInitialsAvatar(activity.name),
          ),
          const SizedBox(width: 16),
          // Activity details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Show both usernames prominently for Together mode
                if (activity.fetchType == 'Together' &&
                    activity.partnerUserName != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 16,
                            color: const Color(0xFF42AAF0),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Together Mode',
                            style: const TextStyle(
                              color: Color(0xFF42AAF0),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activity.name} & ${activity.partnerUserName}',
                        style: const TextStyle(
                          color: Color(0xFF111518),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${activity.points} point${activity.points == 1 ? '' : 's'} each',
                        style: const TextStyle(
                          color: Color(0xFF42AAF0),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.name,
                        style: const TextStyle(
                          color: Color(0xFF111518),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${activity.points} point${activity.points == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF637988),
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                Text(
                  activity.message,
                  style: const TextStyle(
                    color: Color(0xFF637988),
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Show post time in HH:MM format
                Text(
                  _formatTime(activity.date),
                  style: TextStyle(
                    // color: Colors.grey[500],
                    color: const Color(0xFF42AAF0),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Verification status and actions
          Column(
            children: [
              // Verification status indicator
              if (status == VerificationStatus.verified)
                GestureDetector(
                  onTap: () => _showVerifiedList(activity),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Verified list',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (status == VerificationStatus.rejected)
                GestureDetector(
                  onTap: () => _showRejectedList(activity),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cancel, color: Colors.red, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Rejected list',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),

              const SizedBox(height: 8),

              // Show evaluation history if post has both verifications and rejections
              if (verifiedBy.isNotEmpty && rejectedBy.isNotEmpty)
                GestureDetector(
                  onTap: () => _showEvaluationHistory(activity),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history, color: Colors.blue, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'History',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (verifiedBy.isNotEmpty && rejectedBy.isNotEmpty)
                const SizedBox(height: 8),

              // Owner cannot verify/reject own post; show only Delete for owner
              if (activity.ownerFirebaseUid == _authService.currentUser?.uid)
                activity.verificationStatus != VerificationStatus.verified
                    ? GestureDetector(
                      onTap: () => _confirmAndDeletePost(activity),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.delete, color: Colors.red, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Delete',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    : const SizedBox.shrink()
              else if (!(activity.verifiedBy).contains(currentUserName) &&
                  !(activity.rejectedBy).contains(currentUserName))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Verify button
                    GestureDetector(
                      onTap: () => _verifyActivity(activity),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.green,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Reject button
                    GestureDetector(
                      onTap: () => _rejectActivity(activity),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeletePost(WaterActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Post'),
          content: const Text('Are you sure you want to delete this post?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      if (activity.id != null) {
        await _dataService.deleteWaterFetchPost(activity.id!);

        setState(() {
          _activities.removeWhere((a) => a.id == activity.id);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDateSection(String dateTitle, List<WaterActivity> activities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            dateTitle,
            style: const TextStyle(
              color: Color(0xFF111518),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Activities for this date
        ...activities.map((activity) {
          return _buildActivityItem(activity);
        }),
        // Total points for this date with breakdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Points: ${_calculateTotalPoints(activities)}',
                style: const TextStyle(
                  color: Color(0xFF637988),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Show point breakdown
              if (activities.any(
                (a) => a.verificationStatus == VerificationStatus.verified,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Verified: ${activities.where((a) => a.verificationStatus == VerificationStatus.verified).fold(0.0, (sum, a) {
                      if (a.fetchType == 'Together' && a.partnerUserName != null) {
                        return sum + (a.points * 2); // total across both users
                      } else {
                        return sum + a.points; // Single mode
                      }
                    })} pts',
                    style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if there's any data to show
    bool hasData = _activities.isNotEmpty;

    if (!hasData) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Water Fetching',
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

              // Empty state
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.water_drop_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No water activities yet',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start posting your water fetching activities!',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // Add button
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => _showPostWaterFetchModal(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: const Color(0xFF111518),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                        minimumSize: const Size(0, 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 24),
                          const SizedBox(height: 16),
                          const Text(
                            'I have bought water',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.015,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom navigation
              _buildBottomNavigationBar(),
            ],
          ),
        ),
      );
    }

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
                  Text(
                    'Water Fetching',
                    style: const TextStyle(
                      color: Color(0xFF111518),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      letterSpacing: -0.015,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      _groupActivitiesByDate().entries
                          .map(
                            (entry) =>
                                _buildDateSection(entry.key, entry.value),
                          )
                          .toList(),
                ),
              ),
            ),

            // Add button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => _showPostWaterFetchModal(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF42AAF0),
                      foregroundColor: const Color(0xFF111518),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 24),
                        const SizedBox(width: 16),
                        const Text(
                          'I have bought water',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.015,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom navigation
            _buildBottomNavigationBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0F3F4), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Home tab (active)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.home, color: Color(0xFF111518), size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Home',
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
              // Leaderboard tab
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/leaderboard'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        color: const Color(0xFF637988),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Leaderboard',
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
              // Profile tab
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
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

  void _showPostWaterFetchModal() {
    // Prevent multiple modals
    if (_isModalOpen) return;
    _isModalOpen = true;

    // Refresh user list when modal opens (only if needed)
    if (_availableUsers.length <= 1) {
      _loadUsersFromDatabase();
    }

    // Set default message
    _messageController.text = 'I have bought water';
    _bottleCount.value = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  height: 20,
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: Container(
                    height: 4,
                    width: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBE1E6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Post Water Fetch',
                              style: const TextStyle(
                                color: Color(0xFF111518),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                                letterSpacing: -0.015,
                              ),
                            ),
                            if (_authService.currentUser != null)
                              Text(
                                'as ${_authService.getCurrentUserProfile()?['displayName'] ?? 'Current User'}',
                                style: const TextStyle(
                                  color: Color(0xFF617989),
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _isModalOpen = false;
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close, size: 24),
                      ),
                    ],
                  ),
                ),

                // Scrollable content area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // Fetch type radio buttons
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F3F4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                ValueListenableBuilder<String>(
                                  valueListenable: _fetchType,
                                  builder: (context, fetchType, child) {
                                    return FetchTypeButton(
                                      label: 'Single',
                                      selected: fetchType,
                                      onTap: () => _fetchType.value = 'Single',
                                    );
                                  },
                                ),
                                ValueListenableBuilder<String>(
                                  valueListenable: _fetchType,
                                  builder: (context, fetchType, child) {
                                    return FetchTypeButton(
                                      label: 'Together',
                                      selected: fetchType,
                                      onTap:
                                          () => _fetchType.value = 'Together',
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // User selection dropdown (only show for Together)
                        ValueListenableBuilder<String>(
                          valueListenable: _fetchType,
                          builder: (context, fetchType, child) {
                            if (fetchType == 'Together') {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Label for user selection
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 16,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      'Select a user to fetch water together:',
                                      style: const TextStyle(
                                        color: Color(0xFF111518),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F3F4),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedUser.value,
                                          isExpanded: true,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Color(0xFF617989),
                                            size: 24,
                                          ),
                                          items: _userDropdownItems,
                                          onChanged: (String? newValue) {
                                            if (newValue != null) {
                                              _selectedUser.value = newValue;
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Display selected user name below dropdown
                                  ValueListenableBuilder<String>(
                                    valueListenable: _selectedUser,
                                    builder: (context, selectedUser, child) {
                                      if (selectedUser != 'Select users') {
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            left: 16,
                                            top: 8,
                                            bottom: 8,
                                            right: 16,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE3F2FD),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF42AAF0),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF42AAF0,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                  Icons.person,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Fetching together with:',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF617989,
                                                        ),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                    Text(
                                                      selectedUser,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF111518,
                                                        ),
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  _selectedUser.value =
                                                      'Select users';
                                                },
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: Color(0xFF617989),
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 24,
                                                      minHeight: 24,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        );
                                      } else {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                            top: 8,
                                            bottom: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 16,
                                                color: const Color(0xFF617989),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Please select a user to fetch water together',
                                                style: const TextStyle(
                                                  color: Color(0xFF617989),
                                                  fontSize: 14,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),

                        // Message input field
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _messageController,
                                maxLines: 3,
                                maxLength: 200,
                                decoration: InputDecoration(
                                  hintText: 'I have bought water',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF617989),
                                    fontSize: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFF0F3F4),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFF0F3F4),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF42AAF0),
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF0F3F4),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  counterText: '',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Required field',
                                      style: TextStyle(
                                        color:
                                            _messageController.text.isEmpty
                                                ? Colors.red
                                                : Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${_messageController.text.length}/200',
                                      style: const TextStyle(
                                        color: Color(0xFF617989),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottle count selector
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 8,
                                ),
                                child: Text(
                                  'Bottles',
                                  style: const TextStyle(
                                    color: Color(0xFF111518),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F3F4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    ValueListenableBuilder<int>(
                                      valueListenable: _bottleCount,
                                      builder: (context, bottleCount, child) {
                                        final bool isSelected =
                                            bottleCount == 1;
                                        return Expanded(
                                          child: GestureDetector(
                                            onTap: () => _bottleCount.value = 1,
                                            child: Container(
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color:
                                                    isSelected
                                                        ? Colors.white
                                                        : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow:
                                                    isSelected
                                                        ? const [
                                                          BoxShadow(
                                                            color: Color(
                                                              0x1A000000,
                                                            ),
                                                            blurRadius: 4,
                                                            offset: Offset(
                                                              0,
                                                              0,
                                                            ),
                                                          ),
                                                        ]
                                                        : null,
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  '1 bottle',
                                                  style: TextStyle(
                                                    color: Color(0xFF111518),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    ValueListenableBuilder<int>(
                                      valueListenable: _bottleCount,
                                      builder: (context, bottleCount, child) {
                                        final bool isSelected =
                                            bottleCount == 2;
                                        return Expanded(
                                          child: GestureDetector(
                                            onTap: () => _bottleCount.value = 2,
                                            child: Container(
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color:
                                                    isSelected
                                                        ? Colors.white
                                                        : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow:
                                                    isSelected
                                                        ? const [
                                                          BoxShadow(
                                                            color: Color(
                                                              0x1A000000,
                                                            ),
                                                            blurRadius: 4,
                                                            offset: Offset(
                                                              0,
                                                              0,
                                                            ),
                                                          ),
                                                        ]
                                                        : null,
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  '2 bottles',
                                                  style: TextStyle(
                                                    color: Color(0xFF111518),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Post button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _isPosting ? null : () => _postWaterFetch(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isPosting
                                ? const Color(0xFFBDBDBD)
                                : const Color(0xFF42AAF0),
                        foregroundColor: const Color(0xFF111518),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child:
                          _isPosting
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF111518),
                                  ),
                                ),
                              )
                              : const Text(
                                'Post',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.015,
                                ),
                              ),
                    ),
                  ),
                ),

                // Bottom navigation
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFF0F3F4), width: 1),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Home tab (active)
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.home,
                                  color: Color(0xFF111518),
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Home',
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
                          // Leaderboard tab
                          Expanded(
                            child: GestureDetector(
                              onTap:
                                  () => Navigator.of(
                                    context,
                                  ).pushReplacementNamed('/leaderboard'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.emoji_events_outlined,
                                    color: const Color(0xFF637988),
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Leaderboard',
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
                          // Profile tab
                          Expanded(
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _postWaterFetch() async {
    // Prevent multiple posts
    if (_isPosting) return;

    // Validate message
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a message')));
      return;
    }

    // Validate user selection for Together mode
    if (_fetchType.value == 'Together' &&
        _selectedUser.value == 'Select users') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user for together mode')),
      );
      return;
    }

    // Check if users are available for Together mode
    if (_fetchType.value == 'Together' && _availableUsers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other users available for Together mode.'),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isPosting = true;
      });

      // Compute points based on bottle count and fetch type
      final int bottles = _bottleCount.value;
      final double basePoints = bottles == 1 ? 0.5 : 1.0;
      double pointsPerUser;
      if (_fetchType.value == 'Together') {
        const int participants = 2; // poster + one partner
        pointsPerUser = basePoints / participants; // 0.25 or 0.5
      } else {
        pointsPerUser = basePoints; // 0.5 or 1.0
      }

      // Capture values for notifications/messages before resetting
      final String postedFetchType = _fetchType.value;
      final String postedSelectedUser = _selectedUser.value;
      final int postedBottles = _bottleCount.value;

      // Create post in Supabase
      await _dataService.createWaterFetchPost(
        message: _messageController.text.trim(),
        fetchType: postedFetchType,
        partnerUserId:
            postedFetchType == 'Together' ? postedSelectedUser : null,
        points: pointsPerUser,
      );

      // Cache message for notifications before resetting form
      final String postedMessage = _messageController.text.trim();

      // Reset form
      _messageController.clear();
      _fetchType.value = 'Single';
      _selectedUser.value = 'Select users';
      _bottleCount.value = 1;

      // Refresh data from Supabase
      await _loadDataFromSupabase();

      // Send notifications to other users about the new post
      try {
        final currentUserProfile = _authService.getCurrentUserProfile();
        final currentUserName =
            currentUserProfile?['displayName'] ?? 'Unknown User';
        final message =
            postedMessage.isEmpty ? 'I have bought water' : postedMessage;
        final fetchType = postedFetchType;
        final partnerUserName =
            fetchType == 'Together' ? postedSelectedUser : null;

        await _notificationService.sendPostCreationNotification(
          postOwnerName: currentUserName,
          postMessage: message,
          fetchType: fetchType,
          partnerUserName: partnerUserName,
        );
      } catch (e) {
        print('Error sending notifications: $e');
        // Don't fail the post creation if notifications fail
      }

      // Notify other pages to refresh (for real-time updates)
      _notifyDataChanged();

      // Close modal
      Navigator.pop(context);

      // Show success message
      final fetchType = postedFetchType;
      final selectedUser = postedSelectedUser;
      final int bottlesPosted = postedBottles;
      final double basePts = bottlesPosted == 1 ? 0.5 : 1.0;
      final String messageText =
          fetchType == 'Together'
              ? 'Posted as $selectedUser & ${_authService.getCurrentUserProfile()?['displayName'] ?? 'You'}! Both users will get ${(basePts / 2)} points each when verified.'
              : 'Posted successfully! You will get ${basePts} points when verified.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageText), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  // Notify other pages that data has changed
  void _notifyDataChanged() {
    // This will trigger a refresh when navigating to other pages
    setState(() {
      // Force a rebuild to ensure data is fresh
    });

    // Broadcast a lightweight app-level event so other pages (leaderboard)
    // can reload their data when needed.
    AppEvents.notifyDataChanged();
  }

  // Broadcast data change to other pages
  void _broadcastDataChange() {
    // This will be used by other pages to refresh their data
    // when they become visible again
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
