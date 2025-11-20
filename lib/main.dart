import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:water_bottle/login_page.dart';
import 'package:water_bottle/signup_page.dart';
import 'package:water_bottle/home_page.dart';
import 'package:water_bottle/profile_page.dart';
import 'package:water_bottle/leaderboard_page.dart';
import 'package:water_bottle/auth_wrapper.dart';
import 'package:water_bottle/auth_test.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:water_bottle/config/supabase_config.dart';
import 'firebase_options.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Safely initialize Firebase, handling duplicate app scenarios
    await _initializeFirebaseSafely();
  } catch (e) {
    print('Error initializing Firebase: $e');
    // Continue with the app even if Firebase fails
  }

  try {
    // Initialize Supabase only if configured (prevents empty-host URI errors)
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        debug: SupabaseConfig.enableDebug,
      );
      print('Supabase initialized successfully');
    } else {
      // Avoid making requests with an empty host (which causes "No host specified in URI /rest/...")
      print('Supabase not initialized: ${SupabaseConfig.missingConfigMessage}');
    }
  } catch (e) {
    print('Error initializing Supabase: $e');
    // Continue with the app even if Supabase fails
  }

  // Ask for notifications permission (Android 13+ and iOS)
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  } catch (e) {
    // Ignore permission errors
  }

  runApp(const WaterBottleApp());
}

// Helper function to safely initialize Firebase
Future<void> _initializeFirebaseSafely() async {
  try {
    // Check if Firebase is already initialized
    if (Firebase.apps.isNotEmpty) {
      try {
        // Try to get the default app
        final existingApp = Firebase.app();
        print(
          'Firebase already initialized, using existing instance: ${existingApp.name}',
        );
        return; // Exit early if we successfully got an existing app
      } catch (e) {
        print('Firebase apps exist but cannot be accessed: $e');
        // Continue with initialization attempt
      }
    }

    // Initialize Firebase if no apps exist or if we couldn't access existing ones
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure Firebase Auth persistence to ensure user stays logged in
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization error: $e');

    // Handle duplicate app error specifically
    if (e.toString().contains('duplicate-app')) {
      print('Duplicate app error detected, trying to access existing instance');
      try {
        final app = Firebase.app();
        print('Successfully accessed existing Firebase app: ${app.name}');
      } catch (accessError) {
        print('Could not access existing Firebase app: $accessError');
        // Continue with the app - Firebase might still work
      }
    } else {
      // For other errors, rethrow
      rethrow;
    }
  }
}

class WaterBottleApp extends StatelessWidget {
  const WaterBottleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Water Bottle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF42AAF0)),
        textTheme: GoogleFonts.manropeTextTheme(),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const HomePage(),
        '/profile': (context) => const ProfilePage(),
        '/leaderboard': (context) => const LeaderboardPage(),
        '/auth-test': (context) => const AuthTest(),
      },
    );
  }
}
