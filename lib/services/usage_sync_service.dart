// lib/services/usage_sync_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Unified usage data service that combines:
/// 1. Auto-tracked Android usage stats (if available)
/// 2. Manual child session logs (primary source for research)
/// 3. Parent verification status
class UsageSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get or create the daily usage document for a child
  static Future<Map<String, dynamic>?> getUsageForDate(String childId, String dateStr) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(childId)
          .collection('usageAnalysis')
          .doc(dateStr)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['dateStr'] = dateStr;
        return data;
      }

      // If no auto-tracked data, aggregate from manual session logs
      return await _aggregateManualLogs(childId, dateStr);
    } catch (e) {
      print('UsageSyncService.getUsageForDate error: $e');
      return await _aggregateManualLogs(childId, dateStr);
    }
  }

  /// Aggregate manual session logs into daily summary format
  static Future<Map<String, dynamic>?> _aggregateManualLogs(String childId, String dateStr) async {
    try {
      final parts = dateStr.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final startOfDay = DateTime(year, month, day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('sessionLogs')
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
          .where('status', whereIn: ['verified', 'corrected', 'pending'])
          .get();

      if (snapshot.docs.isEmpty) return null;

      int totalMinutes = 0;
      int educationMinutes = 0;
      int entertainmentMinutes = 0;
      int socialMinutes = 0;
      int otherMinutes = 0;
      int sessionCount = 0;
      Map<String, dynamic> appDetails = {};
      DateTime? firstPickup;
      DateTime? lastSessionEnd;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duration = (data['durationMinutes'] as num?)?.toInt() ?? 0;
        final category = data['category'] as String? ?? 'other';
        final appName = data['appName'] as String? ?? 'Unknown';
        final startTime = (data['startTime'] as Timestamp?)?.toDate();

        if (duration <= 0) continue;

        totalMinutes += duration;
        sessionCount++;

        switch (category.toLowerCase()) {
          case 'educational':
          case 'education':
            educationMinutes += duration;
            break;
          case 'entertainment':
            entertainmentMinutes += duration;
            break;
          case 'social':
            socialMinutes += duration;
            break;
          default:
            otherMinutes += duration;
            break;
        }

        // Track app details
        if (appDetails.containsKey(appName)) {
          appDetails[appName]['minutes'] = (appDetails[appName]['minutes'] as int) + duration;
        } else {
          appDetails[appName] = {
            'minutes': duration,
            'category': category,
          };
        }

        if (startTime != null) {
          if (firstPickup == null || startTime.isBefore(firstPickup)) {
            firstPickup = startTime;
          }
          final endTime = startTime.add(Duration(minutes: duration));
          if (lastSessionEnd == null || endTime.isAfter(lastSessionEnd)) {
            lastSessionEnd = endTime;
          }
        }
      }

      if (totalMinutes == 0) return null;

      return {
        'dateStr': dateStr,
        'totalMinutes': totalMinutes,
        'educationMinutes': educationMinutes,
        'entertainmentMinutes': entertainmentMinutes,
        'socialMinutes': socialMinutes,
        'otherMinutes': otherMinutes,
        'sessionCount': sessionCount,
        'appDetails': appDetails,
        'firstPickupTime': firstPickup != null ? Timestamp.fromDate(firstPickup) : null,
        'lastSessionEnd': lastSessionEnd != null ? Timestamp.fromDate(lastSessionEnd) : null,
        'dailyLimit': 120,
        'source': 'manual_logs',
        'syncTimestamp': Timestamp.now(),
      };
    } catch (e) {
      print('UsageSyncService._aggregateManualLogs error: $e');
      return null;
    }
  }

  /// Get last 7 days of data (for history view)
  static Future<List<Map<String, dynamic>>> getLast7Days(String childId) async {
    List<Map<String, dynamic>> results = [];
    final now = DateTime.now();

    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayData = await getUsageForDate(childId, dateStr);
      if (dayData != null) {
        dayData['dateLabel'] = _formatDateLabel(date);
        results.add(dayData);
      }
    }

    return results;
  }

  static String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      return 'Yesterday';
    }
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  /// Sync today's Android usage stats (optional enhancement layer)
  static Future<void> syncTodayUsage() async {
    // This is a placeholder for Android auto-sync
    // In the new architecture, manual logs are primary
    // Auto-sync can be added later as a verification layer
    if (kDebugMode) {
      print('UsageSyncService.syncTodayUsage: Manual logging is primary source');
    }
  }

  /// Get raw session logs for a specific date (for verification queue)
  static Future<List<Map<String, dynamic>>> getSessionLogsForDate(
      String childId,
      String dateStr, {
        String? status,
      }) async {
    try {
      final parts = dateStr.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final startOfDay = DateTime(year, month, day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      Query query = _firestore
          .collection('users')
          .doc(childId)
          .collection('sessionLogs')
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('startTime', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('UsageSyncService.getSessionLogsForDate error: $e');
      return [];
    }
  }
}