// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // Request permission on Android 13+
    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Schedule periodic motivational reminders
  static Future<void> scheduleGoalReminders({
    required String goalTitle,
    required String rewardTitle,
    required int pendingTasks,
  }) async {
    if (!_initialized) await init();

    // Cancel existing reminders
    await cancelGoalReminders();

    if (pendingTasks <= 0) return;

    final messages = [
      '🎯 Don\'t forget your goal: "$goalTitle"! Complete a task to earn $rewardTitle.',
      '⭐ You have $pendingTasks task${pendingTasks > 1 ? 's' : ''} left! Less screen time = more fun!',
      '🏆 Keep going! Every task gets you closer to $rewardTitle.',
      '💪 Stay focused! Your goal "$goalTitle" is waiting.',
    ];

    // Schedule 4 reminders throughout the day
    final now = DateTime.now();
    final times = [
      now.add(const Duration(hours: 3)),
      now.add(const Duration(hours: 6)),
      now.add(const Duration(hours: 9)),
      now.add(const Duration(hours: 12)),
    ];

    for (int i = 0; i < times.length; i++) {
      final scheduledTime = times[i];
      if (scheduledTime.isBefore(now)) continue;

      await _notifications.zonedSchedule(
        1000 + i, // unique ID
        'STR App Reminder',
        messages[i % messages.length],
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'goal_reminders',
            'Goal Reminders',
            channelDescription: 'Motivational reminders for your goals',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Cancel all goal reminders
  static Future<void> cancelGoalReminders() async {
    for (int i = 0; i < 10; i++) {
      await _notifications.cancel(1000 + i);
    }
  }

  /// Show immediate notification
  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();

    await _notifications.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'general',
          'General Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Check and schedule reminders based on active goal
  static Future<void> refreshReminders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final goalSnapshot = await FirebaseFirestore.instance
          .collection('goals')
          .where('childId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (goalSnapshot.docs.isEmpty) {
        await cancelGoalReminders();
        return;
      }

      final goal = goalSnapshot.docs.first.data();
      final tasks = (goal['tasks'] as List<dynamic>?) ?? [];
      final pendingTasks = tasks.where((t) => !(t['completed'] ?? false)).length;

      if (pendingTasks > 0) {
        await scheduleGoalReminders(
          goalTitle: goal['title'] ?? 'Your Goal',
          rewardTitle: goal['reward']?['title'] ?? 'your reward',
          pendingTasks: pendingTasks,
        );
      } else {
        await cancelGoalReminders();
      }
    } catch (e) {
      print('NotificationService.refreshReminders error: $e');
    }
  }
}