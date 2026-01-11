import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../model/practice_models.dart';

/// Configuration for debug logging
class DebugLogConfig {
  const DebugLogConfig({
    this.enableLogs = false,
    this.enableJsonExport = false,
    this.maxLogEntries = 1000,
  });

  final bool enableLogs;
  final bool enableJsonExport;
  final int maxLogEntries;
}

/// Log entry for note resolution
class NoteResolutionLog {
  NoteResolutionLog({
    required this.timestamp,
    required this.sessionId,
    required this.expectedIndex,
    required this.grade,
    this.dtMs,
    required this.pointsAdded,
    required this.combo,
    required this.totalScore,
    this.matchedPlayedId,
  });

  final DateTime timestamp;
  final String sessionId;
  final int expectedIndex;
  final HitGrade grade;
  final double? dtMs;
  final int pointsAdded;
  final int combo;
  final int totalScore;
  final String? matchedPlayedId;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'sessionId': sessionId,
        'expectedIndex': expectedIndex,
        'grade': grade.name,
        'dtMs': dtMs,
        'pointsAdded': pointsAdded,
        'combo': combo,
        'totalScore': totalScore,
        'matchedPlayedId': matchedPlayedId,
      };
}

/// Log entry for wrong note played
class WrongNoteLog {
  WrongNoteLog({
    required this.timestamp,
    required this.sessionId,
    required this.playedId,
    required this.pitchKey,
    required this.tPlayedMs,
    required this.reason,
  });

  final DateTime timestamp;
  final String sessionId;
  final String playedId;
  final int pitchKey;
  final double tPlayedMs;
  final String reason;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'sessionId': sessionId,
        'playedId': playedId,
        'pitchKey': pitchKey,
        'tPlayedMs': tPlayedMs,
        'reason': reason,
      };
}

/// Debug logger for practice scoring system
/// 
/// Features:
/// - Logs note resolutions (hit/miss) with timing info
/// - Logs wrong notes with reason
/// - Optional JSON export for analysis
/// - Circular buffer (max entries)
/// - Session-aware logging
class PracticeDebugLogger {
  PracticeDebugLogger({required this.config});

  final DebugLogConfig config;

  final List<NoteResolutionLog> _resolutionLogs = [];
  final List<WrongNoteLog> _wrongNoteLogs = [];

  /// Log a note resolution (hit/miss/wrong)
  /// 
  /// Called after matching and scoring a note
  void logResolveExpected({
    required String sessionId,
    required int expectedIndex,
    required HitGrade grade,
    double? dtMs,
    required int pointsAdded,
    required int combo,
    required int totalScore,
    String? matchedPlayedId,
  }) {
    if (!config.enableLogs) return;

    final log = NoteResolutionLog(
      timestamp: DateTime.now(),
      sessionId: sessionId,
      expectedIndex: expectedIndex,
      grade: grade,
      dtMs: dtMs,
      pointsAdded: pointsAdded,
      combo: combo,
      totalScore: totalScore,
      matchedPlayedId: matchedPlayedId,
    );

    _resolutionLogs.add(log);
    _trimLogs(_resolutionLogs);

    if (kDebugMode) {
      final dtStr = dtMs != null ? '${dtMs.toStringAsFixed(1)}ms' : 'null';
      final matchStr = matchedPlayedId != null
          ? matchedPlayedId.substring(0, 8)
          : 'none';
      debugPrint(
        'RESOLVE_NOTE session=$sessionId idx=$expectedIndex grade=${grade.name} '
        'dt=$dtStr pts=$pointsAdded combo=$combo total=$totalScore match=$matchStr',
      );
    }
  }

  /// Log a wrong note (played but didn't match any expected note)
  /// 
  /// Called when a played note cannot be matched
  void logWrongPlayed({
    required String sessionId,
    required String playedId,
    required int pitchKey,
    required double tPlayedMs,
    required String reason,
  }) {
    if (!config.enableLogs) return;

    final log = WrongNoteLog(
      timestamp: DateTime.now(),
      sessionId: sessionId,
      playedId: playedId,
      pitchKey: pitchKey,
      tPlayedMs: tPlayedMs,
      reason: reason,
    );

    _wrongNoteLogs.add(log);
    _trimLogs(_wrongNoteLogs);

    if (kDebugMode) {
      debugPrint(
        'WRONG_NOTE session=$sessionId playedId=${playedId.substring(0, 8)} '
        'pitch=$pitchKey t=${tPlayedMs.toStringAsFixed(1)}ms reason=$reason',
      );
    }
  }

  /// Export all logs as JSON string
  /// 
  /// Useful for offline analysis or debugging
  String exportLogsAsJson() {
    if (!config.enableJsonExport) {
      return '{"error": "JSON export is disabled in config"}';
    }

    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'resolutionLogs': _resolutionLogs.map((e) => e.toJson()).toList(),
      'wrongNoteLogs': _wrongNoteLogs.map((e) => e.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Clear all logs
  void clearLogs() {
    _resolutionLogs.clear();
    _wrongNoteLogs.clear();
  }

  /// Get resolution logs for a specific session
  List<NoteResolutionLog> getResolutionLogsForSession(String sessionId) {
    return _resolutionLogs
        .where((log) => log.sessionId == sessionId)
        .toList();
  }

  /// Get wrong note logs for a specific session
  List<WrongNoteLog> getWrongNoteLogsForSession(String sessionId) {
    return _wrongNoteLogs.where((log) => log.sessionId == sessionId).toList();
  }

  /// Get summary statistics for a session
  Map<String, dynamic> getSessionSummary(String sessionId) {
    final resolutions = getResolutionLogsForSession(sessionId);
    final wrongs = getWrongNoteLogsForSession(sessionId);

    final perfectCount =
        resolutions.where((r) => r.grade == HitGrade.perfect).length;
    final goodCount = resolutions.where((r) => r.grade == HitGrade.good).length;
    final okCount = resolutions.where((r) => r.grade == HitGrade.ok).length;
    final missCount = resolutions.where((r) => r.grade == HitGrade.miss).length;

    final totalScore =
        resolutions.isNotEmpty ? resolutions.last.totalScore : 0;
    final maxCombo = resolutions.fold<int>(
      0,
      (max, r) => r.combo > max ? r.combo : max,
    );

    final timings = resolutions
        .where((r) => r.dtMs != null)
        .map((r) => r.dtMs!.abs())
        .toList();
    final avgTiming =
        timings.isNotEmpty ? timings.reduce((a, b) => a + b) / timings.length : 0.0;

    return {
      'sessionId': sessionId,
      'totalNotes': resolutions.length,
      'perfectCount': perfectCount,
      'goodCount': goodCount,
      'okCount': okCount,
      'missCount': missCount,
      'wrongCount': wrongs.length,
      'totalScore': totalScore,
      'maxCombo': maxCombo,
      'avgTimingMs': avgTiming,
    };
  }

  /// Trim logs to max entries (circular buffer)
  void _trimLogs<T>(List<T> logs) {
    if (logs.length > config.maxLogEntries) {
      logs.removeRange(0, logs.length - config.maxLogEntries);
    }
  }

  /// Get current log counts
  Map<String, int> get logCounts => {
        'resolutions': _resolutionLogs.length,
        'wrongNotes': _wrongNoteLogs.length,
      };
}
