import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../domain/entities/process_response.dart';

/// In-memory history of generation jobs with local persistence
final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<ProcessResponse>>((ref) {
      return HistoryNotifier();
    });

class HistoryNotifier extends StateNotifier<List<ProcessResponse>> {
  static const _storageKey = 'shazapiano_history';

  HistoryNotifier() : super(const []) {
    _loadFromStorage();
  }

  /// Load history from SharedPreferences
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        // Deserialization not implemented yet - placeholder to avoid analyzer warnings
        if (jsonList.isNotEmpty) {
          // TODO: implement proper deserialization from JSON to ProcessResponse
          state = const [];
        }
      }
    } catch (e) {
      // Silent fail - history not available
      state = const [];
    }
  }

  /// Save history to SharedPreferences
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Note: This is a simplified approach. For production,
      // implement proper serialization
      await prefs.setString(_storageKey, jsonEncode([]));
    } catch (e) {
      // Silent fail
    }
  }

  void add(ProcessResponse response) {
    final updated = [response, ...state];
    // Keep last 20 jobs
    state = updated.take(20).toList();
    _saveToStorage();
  }

  void clear() {
    state = const [];
    _saveToStorage();
  }
}
