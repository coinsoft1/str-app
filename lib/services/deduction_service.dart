import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/screen_time_service.dart';
import '../services/ai_service.dart';

class DeductionService {
  static final DeductionService _instance = DeductionService._internal();
  factory DeductionService() => _instance;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScreenTimeService _screenTimeService = ScreenTimeService();
  Timer? _monitoringTimer;
  
  DeductionService._internal();

  static void startMonitoring() {
    DeductionService()._startAutoMonitoring();
  }

  static void stopMonitoring() {
    DeductionService()._stopAutoMonitoring();
  }

  static Future<void> processMissedDeductions(String userId) async {
    await DeductionService()._processMissedDeductions(userId);
  }

  void _startAutoMonitoring() {
    _stopAutoMonitoring();
    
    _monitoringTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final children = await _firestore.collection('users')
          .where('parentId', isEqualTo: user.uid)
          .get();

      for (var childDoc in children.docs) {
        await _checkAndDeductIfOverLimit(childDoc.id, childDoc.data());
      }
    });
    
    debugPrint('✅ Auto-monitoring started');
  }

  void _stopAutoMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('⏹️ Auto-monitoring stopped');
  }

  Future<void> _checkAndDeductIfOverLimit(String childId, Map<String, dynamic> childData) async {
    try {
      final today = DateTime.now();
      final dailyLimit = (childData['dailyScreenTimeLimit'] ?? 120) as int;
      final autoDeductEnabled = childData['autoDeductEnabled'] ?? false;
      final deductionRate = (childData['deductionRate'] ?? 1) as int;

      if (!autoDeductEnabled) return;

      int actualMinutes = await _screenTimeService.getScreenTimeMinutes(today);
      int minutesOver = actualMinutes - dailyLimit;

      if (minutesOver > 0) {
        int pointsToDeduct = minutesOver * deductionRate;
        await deductPointsAndGrantTime(
          childId: childId,
          pointsToDeduct: pointsToDeduct,
          minutesToGrant: 0,
        );
        
        debugPrint('🎯 Auto-deducted $pointsToDeduct points from $childId (over by $minutesOver min)');
      }
    } catch (e) {
      debugPrint('Error in auto-monitoring: $e');
    }
  }

  Future<void> _processMissedDeductions(String parentId) async {
    final children = await _firestore.collection('users')
        .where('parentId', isEqualTo: parentId)
        .get();

    for (var childDoc in children.docs) {
      final lastCheck = childDoc.data()['lastScreenTimeCheck']?.toDate();
      if (lastCheck == null || lastCheck.isBefore(DateTime.now().subtract(const Duration(hours: 24)))) {
        await _checkAndDeductIfOverLimit(childDoc.id, childDoc.data());
      }
    }
  }

  Future<Map<String, dynamic>> deductPointsAndGrantTime({
    required String childId,
    required int pointsToDeduct,
    required int minutesToGrant,
  }) async {
    try {
      final batch = _firestore.batch();
      final childRef = _firestore.collection('users').doc(childId);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final childDoc = await childRef.get();
      final data = childDoc.data() ?? {};
      
      int currentPoints = data['currentPoints'] ?? 0;
      int remainingScreenTime = data['remainingScreenTime'] ?? 0;

      if (currentPoints < pointsToDeduct) {
        return {
          'success': false,
          'message': 'Not enough points. Required: $pointsToDeduct, Available: $currentPoints',
        };
      }

      int actualScreenTimeUsed = await _screenTimeService.getScreenTimeMinutes(today);
      int newRemainingTime = remainingScreenTime + minutesToGrant;
      
      batch.update(childRef, {
        'currentPoints': currentPoints - pointsToDeduct,
        'remainingScreenTime': newRemainingTime,
        'lastScreenTimeUpdate': FieldValue.serverTimestamp(),
        'actualScreenTimeUsed': actualScreenTimeUsed,
      });

      final transactionRef = _firestore.collection('pointTransactions').doc();
      batch.set(transactionRef, {
        'childId': childId,
        'parentId': FirebaseAuth.instance.currentUser?.uid,
        'type': minutesToGrant > 0 ? 'exchange' : 'penalty',
        'points': pointsToDeduct,
        'minutesGranted': minutesToGrant,
        'remainingTimeAfter': newRemainingTime,
        'timestamp': FieldValue.serverTimestamp(),
        'screenTimeBeforeUsage': actualScreenTimeUsed,
      });

      await batch.commit();

      return {
        'success': true,
        'message': minutesToGrant > 0 
          ? 'Exchanged $pointsToDeduct points for $minutesToGrant minutes'
          : 'Deducted $pointsToDeduct points for overuse',
        'newRemainingTime': newRemainingTime,
        'pointsLeft': currentPoints - pointsToDeduct,
      };
    } catch (e) {
      debugPrint('Error in deduction: $e');
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  Future<int> getAvailablePoints(String childId) async {
    try {
      final childDoc = await _firestore.collection('users').doc(childId).get();
      return childDoc.data()?['currentPoints'] ?? 0;
    } catch (e) {
      debugPrint('Error getting points: $e');
      return 0;
    }
  }

  Future<int> getRemainingScreenTime(String childId) async {
    try {
      final childDoc = await _firestore.collection('users').doc(childId).get();
      return childDoc.data()?['remainingScreenTime'] ?? 0;
    } catch (e) {
      debugPrint('Error getting screen time: $e');
      return 0;
    }
  }
}