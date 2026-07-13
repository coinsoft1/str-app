import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screen_time_service.dart';

class ScreenTimeTrackingService {
  static final ScreenTimeTrackingService _instance = ScreenTimeTrackingService._internal();
  factory ScreenTimeTrackingService() => _instance;
  ScreenTimeTrackingService._internal();

  Timer? _trackingTimer;
  bool _isRunning = false;
  final Map<String, DateTime> _lastCheckTimes = {};

  Future<void> startTracking() async {
    if (_isRunning) return;
    
    // Check permission first
    final hasPermission = await ScreenTimeService().checkPermission();
    if (!hasPermission) {
      print('Cannot start tracking: No Usage Stats permission');
      return;
    }

    _isRunning = true;
    print('Screen time tracking started');
    
    // First check
    await _checkAllChildren();
    
    // Check every 5 minutes
    _trackingTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _checkAllChildren();
    });
  }

  void stopTracking() {
    _trackingTimer?.cancel();
    _isRunning = false;
    print('Screen time tracking stopped');
  }

  Future<void> _checkAllChildren() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .where('role', isEqualTo: 'child')
          .get();

      for (var childDoc in childrenSnapshot.docs) {
        await _checkChildScreenTime(childDoc.id, childDoc.data());
      }
    } catch (e) {
      print('Error checking children: $e');
    }
  }

  Future<void> _checkChildScreenTime(String childId, Map<String, dynamic> childData) async {
    try {
      final config = childData['screenTimeConfig'] as Map<String, dynamic>?;
      if (config == null || config['enabled'] != true) return;

      // Get settings safely
      final dailyLimit = (config['dailyLimitMinutes'] as num?)?.toInt() ?? 60;
      final deductionRate = (config['deductionRate'] as num?)?.toInt() ?? 1;
      final allowNegative = config['debtSettings']?['allowNegative'] ?? true;
      final maxDebt = (config['debtSettings']?['maxDebt'] as num?)?.toInt() ?? 100;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      DateTime checkStart = _lastCheckTimes[childId] ?? todayStart;
      
      // Skip if less than 5 minutes
      if (now.difference(checkStart).inMinutes < 5) return;

      // Get usage safely
      final service = ScreenTimeService();
      final hasPermission = await service.checkPermission();
      if (!hasPermission) return; // Skip if permission lost

      final usage = await service.getUsageSince(checkStart);
      
      int periodMinutes = 0;
      for (var app in usage) {
        periodMinutes += app.minutesUsed;
      }

      if (periodMinutes <= 0) {
        _lastCheckTimes[childId] = now;
        return;
      }

      // Get current data
      final childRef = FirebaseFirestore.instance.collection('users').doc(childId);
      final currentDoc = await childRef.get();
      if (!currentDoc.exists) return;
      
      final currentData = currentDoc.data() ?? {};
      final currentTotalUsed = (currentData['actualScreenTimeUsed'] as num?)?.toInt() ?? 0;
      final newTotalUsed = currentTotalUsed + periodMinutes;
      
      // Calculate overage
      int overage = 0;
      if (newTotalUsed > dailyLimit) {
        final previousOverage = currentTotalUsed > dailyLimit ? currentTotalUsed - dailyLimit : 0;
        overage = (newTotalUsed - dailyLimit) - previousOverage;
      }

      if (overage <= 0) {
        // Just update usage, no deduction
        await childRef.update({
          'actualScreenTimeUsed': newTotalUsed,
          'lastScreenTimeCheck': now,
        });
        _lastCheckTimes[childId] = now;
        return;
      }

      // Calculate deduction
      int pointsToDeduct = overage * deductionRate;
      final currentPoints = (currentData['currentPoints'] as num?)?.toInt() ?? 0;
      final currentDebt = (currentData['screenTimeDebt'] as num?)?.toInt() ?? 0;
      
      int newPoints = currentPoints - pointsToDeduct;
      int newDebt = currentDebt;
      bool debtCreated = false;

      if (newPoints < 0 && allowNegative) {
        final potentialDebt = newDebt + newPoints.abs();
        newDebt = potentialDebt > maxDebt ? maxDebt : potentialDebt.toInt();
        newPoints = 0;
        debtCreated = true;
      } else if (newPoints < 0) {
        newPoints = 0; // Don't go negative if not allowed
      }

      // Build update
      Map<String, dynamic> updateData = {
        'actualScreenTimeUsed': newTotalUsed,
        'lastScreenTimeCheck': now,
        'currentPoints': newPoints,
      };

      if (newDebt > 0 || debtCreated) {
        updateData['screenTimeDebt'] = newDebt;
        updateData['lastDeductionAt'] = now;
        
        // Create notification
        await _createDebtNotification(childId, childData, newDebt);
      }

      await childRef.update(updateData);
      _lastCheckTimes[childId] = now;

    } catch (e, stack) {
      print('Error checking screen time for $childId: $e\n$stack');
    }
  }

  Future<void> _createDebtNotification(String childId, Map<String, dynamic> childData, int debtAmount) async {
    try {
      final parentId = childData['parentId'];
      final childName = childData['name'] ?? 'Child';
      
      await FirebaseFirestore.instance.collection('notifications').add({
        'parentId': parentId,
        'childId': childId,
        'childName': childName,
        'type': 'screen_time_debt',
        'message': '$childName exceeded screen time limit. Debt: $debtAmount points',
        'debtAmount': debtAmount,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      print('Error creating notification: $e');
    }
  }

  Future<Map<String, dynamic>> manualCheck(String childId) async {
    final childDoc = await FirebaseFirestore.instance.collection('users').doc(childId).get();
    if (!childDoc.exists) return {};
    
    await _checkChildScreenTime(childId, childDoc.data()!);
    
    final updated = await FirebaseFirestore.instance.collection('users').doc(childId).get();
    return updated.data() ?? {};
  }
}