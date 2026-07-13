import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screen_time_service.dart';

class DeductionService {
  static final DeductionService _instance = DeductionService._internal();
  factory DeductionService() => _instance;
  DeductionService._internal();

  Timer? _monitoringTimer;
  final ScreenTimeService _screenTimeService = ScreenTimeService();
  
  // Start monitoring screen time for current user
  static void startMonitoring() {
    _instance._start();
  }

  static void stopMonitoring() {
    _instance._stop();
  }

  void _start() {
    _stop(); // Ensure no duplicate timers
    
    // Check every minute
    _monitoringTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndDeduct();
    });
    
    // Also check immediately
    _checkAndDeduct();
  }

  void _stop() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  Future<void> _checkAndDeduct() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final childDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!childDoc.exists) return;
      
      final data = childDoc.data() as Map<String, dynamic>;
      final dailyLimit = (data['dailyScreenTimeLimit'] ?? 120) as int;
      final bonusTime = (data['bonusScreenTime'] ?? 0) as int;
      final totalLimit = dailyLimit + bonusTime;
      final deductionRate = (data['deductionRate'] ?? 1) as int;
      final autoDeduct = data['autoDeductEnabled'] ?? false;
      final currentPoints = (data['currentPoints'] ?? 0) as int;

      // Get actual screen time from service
      final usedMinutes = await _screenTimeService.getScreenTimeMinutes(DateTime.now());
      
      // Update used time in Firestore
      await childDoc.reference.update({
        'actualScreenTimeUsed': usedMinutes,
        'lastScreenTimeCheck': FieldValue.serverTimestamp(),
      });

      // If over limit and auto-deduct enabled, deduct points
      if (usedMinutes > totalLimit && autoDeduct && currentPoints > 0) {
        final overage = usedMinutes - totalLimit;
        final pointsToDeduct = (overage * deductionRate).toInt();
        
        // Only deduct if we haven't already deducted for this overage
        final lastDeduction = data['lastPointsDeduction']?.toDate();
        final now = DateTime.now();
        
        if (lastDeduction == null || now.difference(lastDeduction).inMinutes >= 1) {
          await childDoc.reference.update({
            'currentPoints': FieldValue.increment(-pointsToDeduct),
            'totalPointsDeducted': FieldValue.increment(pointsToDeduct),
            'lastPointsDeduction': FieldValue.serverTimestamp(),
          });
          
          // Record transaction
          await FirebaseFirestore.instance.collection('pointTransactions').add({
            'childId': user.uid,
            'type': 'deduction',
            'points': -pointsToDeduct,
            'reason': 'Screen time overage: $overage minutes',
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('Error in deduction service: $e');
    }
  }

  // Manual deduction for AI negotiation
  Future<void> deductPointsAndGrantTime({
    required String childId,
    required int pointsToDeduct,
    required int minutesToGrant,
  }) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final childRef = FirebaseFirestore.instance.collection('users').doc(childId);
        final childDoc = await transaction.get(childRef);
        
        if (!childDoc.exists) throw Exception('Child not found');
        
        final data = childDoc.data() as Map<String, dynamic>;
        final currentPoints = (data['currentPoints'] ?? 0) as int;
        
        if (currentPoints < pointsToDeduct) {
          throw Exception('Insufficient points');
        }

        transaction.update(childRef, {
          'currentPoints': FieldValue.increment(-pointsToDeduct),
          'bonusScreenTime': FieldValue.increment(minutesToGrant),
        });
      });
    } catch (e) {
      print('Error deducting points: $e');
      rethrow;
    }
  }
}