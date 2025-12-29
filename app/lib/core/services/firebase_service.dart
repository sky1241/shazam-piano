import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Firebase service for app initialization and common operations
class FirebaseService {
  static const Duration _initTimeout = Duration(seconds: 12);
  static const Duration _authTimeout = Duration(seconds: 8);
  static const Duration _crashlyticsTimeout = Duration(seconds: 8);

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseAnalytics get analytics => FirebaseAnalytics.instance;
  static FirebaseCrashlytics get crashlytics => FirebaseCrashlytics.instance;

  /// Initialize Firebase
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp().timeout(_initTimeout);
      debugPrint('Firebase Core initialized');
    } on TimeoutException catch (e) {
      debugPrint('Firebase initialization timed out: $e');
      return;
    } catch (e, stackTrace) {
      debugPrint('Firebase initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return;
    }

    // Setup Crashlytics (non-blocking)
    try {
      await _setupCrashlytics().timeout(_crashlyticsTimeout);
      debugPrint('Crashlytics initialized');
    } on TimeoutException catch (e) {
      debugPrint('Crashlytics setup timed out (non-critical): $e');
    } catch (e) {
      debugPrint('Crashlytics setup failed (non-critical): $e');
    }

    // Setup anonymous auth (non-blocking)
    try {
      await _setupAuth().timeout(_authTimeout);
      debugPrint('Anonymous auth initialized');
    } on TimeoutException catch (e) {
      debugPrint('Anonymous auth timed out (non-critical): $e');
    } catch (e) {
      debugPrint('Anonymous auth failed (non-critical): $e');
    }

    debugPrint('Firebase initialized successfully');
  }

  /// Setup Crashlytics
  static Future<void> _setupCrashlytics() async {
    // Pass all uncaught errors to Crashlytics
    FlutterError.onError = crashlytics.recordFlutterFatalError;
  }

  /// Setup anonymous authentication
  static Future<void> _setupAuth() async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
      debugPrint('Signed in anonymously: ${auth.currentUser?.uid}');
    }
  }

  /// Get or create user document
  static Future<Map<String, dynamic>> getUserData() async {
    final user = auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final userDoc = firestore.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();

    if (!snapshot.exists) {
      // Create new user document
      final data = {
        'created_at': FieldValue.serverTimestamp(),
        'unlocked': false,
        'total_generations': 0,
      };
      await userDoc.set(data);
      return data;
    }

    return snapshot.data() ?? {};
  }

  /// Update user unlock status
  static Future<void> updateUnlockStatus(bool unlocked) async {
    final user = auth.currentUser;
    if (user == null) return;

    await firestore.collection('users').doc(user.uid).update({
      'unlocked': unlocked,
      'unlocked_at': FieldValue.serverTimestamp(),
    });
  }

  /// Log analytics event
  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
  }) async {
    await analytics.logEvent(name: name, parameters: parameters);
  }

  /// Log screen view
  static Future<void> logScreenView(String screenName) async {
    await analytics.logScreenView(screenName: screenName);
  }
}
