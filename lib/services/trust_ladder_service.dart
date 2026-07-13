// lib/services/trust_ladder_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// FIXED POINT STRUCTURE (Standardized for Study)
/// - Log session: 0 points (tentative, pending verification)
/// - Parent verifies accurate: +1.0 points (configurable via SettingsService)
/// - Parent corrects: +0.5 points (configurable via SettingsService)
/// - Parent rejects: 0 points, streak reset
/// - 3-day accuracy streak: +2 bonus
/// - 5-day accuracy streak: +5 bonus

class TrustLadderService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Point constants - defaults, overridable by SettingsService
  static const double BASE_LOG_POINTS = 0.0;
  static const double VERIFY_BONUS = 1.0;
  static const double CORRECT_BONUS = 0.5;
  static const double REJECT_POINTS = 0.0;
  static const int STREAK_3_BONUS = 2;
  static const int STREAK_5_BONUS = 5;

  // Trust ladder thresholds
  static const int AUTO_PILOT_THRESHOLD = 5;
  static const int ACTIVE_MONITOR_TRIGGER = 2;

  static Future<Map<String, dynamic>> submitSessionLog({
    required String childId,
    required String parentId,
    required String appName,
    required String category,
    required int durationMinutes,
    required DateTime startTime,
    required DateTime endTime,
    String platform = 'android',
  }) async {
    final batch = _firestore.batch();
    final now = Timestamp.now();

    final trustDoc = await _firestore
        .collection('users')
        .doc(childId)
        .collection('trustLadder')
        .doc('current')
        .get();

    String currentTier = 'daily_glance';
    int totalLogs = 0;

    if (trustDoc.exists) {
      final tData = trustDoc.data()!;
      currentTier = tData['currentTier'] ?? 'daily_glance';
      totalLogs = (tData['totalLogs'] ?? 0) as int;
    }

    final logRef = _firestore
        .collection('users')
        .doc(childId)
        .collection('sessionLogs')
        .doc();

    final logData = {
      'childId': childId,
      'parentId': parentId,
      'appName': appName,
      'category': category,
      'durationMinutes': durationMinutes,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'status': 'pending',
      'pointsAwarded': 0.0,
      'platform': platform,
      'createdAt': now,
      'verificationModeAtLog': currentTier,
    };

    batch.set(logRef, logData);

    final childRef = _firestore.collection('users').doc(childId);
    batch.update(childRef, {
      'totalLogsSubmitted': FieldValue.increment(1),
    });

    final trustRef = _firestore
        .collection('users')
        .doc(childId)
        .collection('trustLadder')
        .doc('current');

    batch.set(trustRef, {
      'currentTier': currentTier,
      'totalLogs': totalLogs + 1,
      'lastLogAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();

    await _createParentNotification(
      childId: childId,
      parentId: parentId,
      logId: logRef.id,
      mode: currentTier,
      appName: appName,
      category: category,
      durationMinutes: durationMinutes,
    );

    return {
      'logId': logRef.id,
      'status': 'pending',
      'pointsAwarded': 0.0,
      'currentTier': currentTier,
      'message': 'Log submitted! Your parent will review it soon.',
    };
  }

  static Future<Map<String, dynamic>> verifyLog({
    required String childId,
    required String parentId,
    required String logId,
    required String action,
    String? parentNote,
    String? correctedCategory,
    int? correctedDuration,
    double? verifyPointsOverride,
    double? correctPointsOverride,
  }) async {
    final batch = _firestore.batch();
    final now = Timestamp.now();

    final logRef = _firestore
        .collection('users')
        .doc(childId)
        .collection('sessionLogs')
        .doc(logId);

    final logDoc = await logRef.get();
    if (!logDoc.exists) {
      throw Exception('Log not found');
    }

    final logData = logDoc.data()!;
    final double currentPointsAwarded = (logData['pointsAwarded'] as num?)?.toDouble() ?? 0.0;
    final String previousStatus = logData['status'] ?? 'pending';

    final trustRef = _firestore
        .collection('users')
        .doc(childId)
        .collection('trustLadder')
        .doc('current');
    final trustDoc = await trustRef.get();

    int accuracyStreak = 0;
    int totalVerified = 0;
    int totalCorrected = 0;
    int totalRejected = 0;
    String currentTier = 'daily_glance';

    if (trustDoc.exists) {
      final tData = trustDoc.data()!;
      accuracyStreak = (tData['accuracyStreak'] ?? 0) as int;
      totalVerified = (tData['totalVerified'] ?? 0) as int;
      totalCorrected = (tData['totalCorrected'] ?? 0) as int;
      totalRejected = (tData['totalRejected'] ?? 0) as int;
      currentTier = tData['currentTier'] ?? 'daily_glance';
    }

    double newPoints = currentPointsAwarded;
    String newStatus = previousStatus;
    int streakChange = 0;
    String tierChange = 'none';

    switch (action) {
      case 'verify':
        newStatus = 'verified';
        newPoints = verifyPointsOverride ?? VERIFY_BONUS;
        streakChange = 1;
        totalVerified++;

        int bonusPoints = 0;
        final newStreak = accuracyStreak + 1;
        if (newStreak == 3) bonusPoints = STREAK_3_BONUS;
        if (newStreak == 5) bonusPoints = STREAK_5_BONUS;

        if (newStreak >= AUTO_PILOT_THRESHOLD && currentTier != 'auto_pilot') {
          currentTier = 'auto_pilot';
          tierChange = 'promote';
        }

        final childRef = _firestore.collection('users').doc(childId);
        batch.update(childRef, {
          'currentPoints': FieldValue.increment(newPoints),
          'totalVerifiedLogs': FieldValue.increment(1),
        });

        if (bonusPoints > 0) {
          batch.update(childRef, {
            'currentPoints': FieldValue.increment(bonusPoints.toDouble()),
            'streakBonusPoints': FieldValue.increment(bonusPoints.toDouble()),
          });
        }
        break;

      case 'correct':
        newStatus = 'corrected';
        newPoints = correctPointsOverride ?? CORRECT_BONUS;
        streakChange = -accuracyStreak;
        totalCorrected++;

        if (currentTier == 'auto_pilot') {
          currentTier = 'daily_glance';
          tierChange = 'demote';
        }

        final childRef = _firestore.collection('users').doc(childId);
        batch.update(childRef, {
          'currentPoints': FieldValue.increment(newPoints),
          'totalCorrectedLogs': FieldValue.increment(1),
        });
        break;

      case 'reject':
        newStatus = 'rejected';
        newPoints = REJECT_POINTS;
        streakChange = -accuracyStreak;
        totalRejected++;

        if (totalRejected >= ACTIVE_MONITOR_TRIGGER) {
          currentTier = 'active_monitor';
          tierChange = 'demote';
        } else if (currentTier == 'auto_pilot') {
          currentTier = 'daily_glance';
          tierChange = 'demote';
        }

        final childRef = _firestore.collection('users').doc(childId);
        batch.update(childRef, {
          'totalRejectedLogs': FieldValue.increment(1),
        });
        break;
    }

    batch.update(logRef, {
      'status': newStatus,
      'pointsAwarded': newPoints,
      'parentNote': parentNote ?? '',
      'correctedCategory': correctedCategory,
      'correctedDuration': correctedDuration,
      'verifiedAt': now,
      'verifiedBy': parentId,
    });

    // NEW: Notify child on rejection so they can re-log
    if (action == 'reject') {
      final childNotifRef = _firestore.collection('notifications').doc();
      batch.set(childNotifRef, {
        'childId': childId,
        'parentId': parentId,
        'type': 'log_rejected',
        'logId': logId,
        'message': 'Your parent rejected your ${logData['appName']} log. Please re-log your screen time.',
        'read': false,
        'createdAt': now,
      });
    }

    final newStreak = (accuracyStreak + streakChange).clamp(0, 999);
    batch.set(trustRef, {
      'currentTier': currentTier,
      'accuracyStreak': newStreak,
      'totalVerified': totalVerified,
      'totalCorrected': totalCorrected,
      'totalRejected': totalRejected,
      'lastVerificationAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    final verificationLogRef = _firestore
        .collection('users')
        .doc(parentId)
        .collection('verificationActions')
        .doc();

    batch.set(verificationLogRef, {
      'childId': childId,
      'logId': logId,
      'action': action,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'pointsBefore': currentPointsAwarded,
      'pointsAfter': newPoints,
      'tierChange': tierChange,
      'parentNote': parentNote,
      'timestamp': now,
    });

    await batch.commit();

    return {
      'status': newStatus,
      'pointsAwarded': newPoints,
      'accuracyStreak': newStreak,
      'currentTier': currentTier,
      'tierChange': tierChange,
      'streakBonus': action == 'verify' && (accuracyStreak + 1 == 3 || accuracyStreak + 1 == 5)
          ? (accuracyStreak + 1 == 5 ? STREAK_5_BONUS : STREAK_3_BONUS)
          : 0,
    };
  }

  static Future<String> getCurrentTier(String childId) async {
    final doc = await _firestore
        .collection('users')
        .doc(childId)
        .collection('trustLadder')
        .doc('current')
        .get();

    if (!doc.exists) return 'daily_glance';
    return doc.data()?['currentTier'] ?? 'daily_glance';
  }

  static Future<Map<String, dynamic>> getTrustStats(String childId) async {
    final doc = await _firestore
        .collection('users')
        .doc(childId)
        .collection('trustLadder')
        .doc('current')
        .get();

    if (!doc.exists) {
      return {
        'currentTier': 'daily_glance',
        'accuracyStreak': 0,
        'totalLogs': 0,
        'totalVerified': 0,
        'totalCorrected': 0,
        'totalRejected': 0,
      };
    }

    return doc.data()!;
  }

  static Future<List<Map<String, dynamic>>> getPendingLogs(String parentId) async {
    final childrenSnapshot = await _firestore
        .collection('users')
        .where('parentId', isEqualTo: parentId)
        .where('role', isEqualTo: 'child')
        .get();

    List<Map<String, dynamic>> pendingLogs = [];

    for (var child in childrenSnapshot.docs) {
      final childId = child.id;
      final childName = child.data()['displayName'] ?? child.data()['name'] ?? 'Child';

      final logsSnapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('sessionLogs')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      for (var log in logsSnapshot.docs) {
        final data = log.data();
        data['id'] = log.id;
        data['childId'] = childId;
        data['childName'] = childName;
        pendingLogs.add(data);
      }
    }

    return pendingLogs;
  }

  static Future<String> getParentVerificationMode(String parentId) async {
    final doc = await _firestore
        .collection('users')
        .doc(parentId)
        .collection('settings')
        .doc('verification')
        .get();

    if (!doc.exists) return 'daily_glance';
    return doc.data()?['mode'] ?? 'daily_glance';
  }

  static Future<void> setParentVerificationMode(String parentId, String mode) async {
    await _firestore
        .collection('users')
        .doc(parentId)
        .collection('settings')
        .doc('verification')
        .set({
      'mode': mode,
      'updatedAt': Timestamp.now(),
      'previousMode': await getParentVerificationMode(parentId),
    }, SetOptions(merge: true));
  }

  static Future<int> autoApproveLogs(String parentId) async {
    final childrenSnapshot = await _firestore
        .collection('users')
        .where('parentId', isEqualTo: parentId)
        .where('role', isEqualTo: 'child')
        .get();

    int approvedCount = 0;

    for (var child in childrenSnapshot.docs) {
      final childId = child.id;
      final tier = await getCurrentTier(childId);

      if (tier == 'auto_pilot') {
        final pending = await _firestore
            .collection('users')
            .doc(childId)
            .collection('sessionLogs')
            .where('status', isEqualTo: 'pending')
            .get();

        for (var log in pending.docs) {
          await verifyLog(
            childId: childId,
            parentId: parentId,
            logId: log.id,
            action: 'verify',
            parentNote: 'Auto-approved (Auto-Pilot mode)',
          );
          approvedCount++;
        }
      }
    }

    return approvedCount;
  }

  static String _getChildMessage(String tier) {
    switch (tier) {
      case 'auto_pilot':
        return 'Great job! Your logs are auto-approved. Keep it up!';
      case 'daily_glance':
        return 'Log submitted! Your parent will review it soon.';
      case 'active_monitor':
        return 'Log submitted. Your parent will review each log carefully.';
      default:
        return 'Log submitted!';
    }
  }

  static Future<void> _createParentNotification({
    required String childId,
    required String parentId,
    required String logId,
    required String mode,
    required String appName,
    required String category,
    required int durationMinutes,
  }) async {
    if (mode == 'active_monitor') {
      await _firestore.collection('notifications').add({
        'parentId': parentId,
        'childId': childId,
        'type': 'log_pending',
        'logId': logId,
        'message': 'New log to review: $appName ($category, ${durationMinutes}min)',
        'read': false,
        'createdAt': Timestamp.now(),
        'isUrgent': true,
      });
    }
  }
}