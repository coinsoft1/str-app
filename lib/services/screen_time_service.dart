import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:usage_stats/usage_stats.dart';

class AppUsageInfo {
  final String packageName;
  final String appName;
  final int minutesUsed;
  final DateTime lastUsed;
  final bool isEducational;

  AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.minutesUsed,
    required this.lastUsed,
    this.isEducational = false,
  });
}

class ScreenTimeService {
  static final ScreenTimeService _instance = ScreenTimeService._internal();
  factory ScreenTimeService() => _instance;
  ScreenTimeService._internal();

  static const Set<String> _defaultEducationalApps = {
    'com.khanacademy.android',
    'com.duolingo',
    'com.google.android.apps.classroom',
  };

  // SAFETY: Check if Android before doing anything
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<bool> checkPermission() async {
    if (!_isAndroid) return false;
    try {
      return await UsageStats.checkUsagePermission() ?? false;
    } catch (e) {
      print('Error checking permission: $e');
      return false;
    }
  }

  Future<void> requestPermission() async {
    if (!_isAndroid) return;
    try {
      await UsageStats.grantUsagePermission();
    } catch (e) {
      print('Error requesting permission: $e');
    }
  }

  Future<List<AppUsageInfo>> getUsageSince(DateTime startTime, {Set<String>? parentDefinedEducational}) async {
    if (!_isAndroid) return [];
    
    try {
      final endTime = DateTime.now();
      List<EventUsageInfo> events = [];
      
      try {
        events = await UsageStats.queryEvents(startTime, endTime);
      } catch (e) {
        print('Error querying events: $e');
        return [];
      }
      
      if (events.isEmpty) return [];
      
      final Map<String, int> packageMinutes = {};
      final Map<String, DateTime> lastUsedMap = {};
      
      DateTime? lastEventTime;
      String? lastPackage;
      bool wasForeground = false;

      // Sort safely
      events.sort((a, b) {
        final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
        final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
        return aTime.compareTo(bTime);
      });
      
      for (var event in events) {
        final eventType = event.eventType;
        final packageName = event.packageName ?? '';
        final timeStampStr = event.timeStamp ?? '0';
        final timeStamp = int.tryParse(timeStampStr) ?? 0;
        
        if (timeStamp == 0) continue;
        
        final timestamp = DateTime.fromMillisecondsSinceEpoch(timeStamp);
        
        if (eventType == '1' || eventType == 'FOREGROUND') {
          if (lastPackage != null && wasForeground && lastEventTime != null) {
            final duration = timestamp.difference(lastEventTime).inMinutes;
            if (duration > 0 && duration < 60) {
              packageMinutes[lastPackage] = (packageMinutes[lastPackage] ?? 0) + duration;
            }
          }
          lastPackage = packageName;
          wasForeground = true;
          lastEventTime = timestamp;
        } else if (eventType == '2' || eventType == 'BACKGROUND') {
          if (lastPackage != null && wasForeground && lastEventTime != null) {
            final duration = timestamp.difference(lastEventTime).inMinutes;
            if (duration > 0 && duration < 60) {
              packageMinutes[lastPackage] = (packageMinutes[lastPackage] ?? 0) + duration;
            }
          }
          wasForeground = false;
          lastEventTime = timestamp;
        }
        
        if (packageName.isNotEmpty) {
          lastUsedMap[packageName] = timestamp;
        }
      }

      final allEducational = {..._defaultEducationalApps, ...(parentDefinedEducational ?? {})};
      
      return packageMinutes.entries.map((entry) {
        final package = entry.key;
        return AppUsageInfo(
          packageName: package,
          appName: package.split('.').last,
          minutesUsed: entry.value,
          lastUsed: lastUsedMap[package] ?? startTime,
          isEducational: allEducational.contains(package),
        );
      }).where((info) => info.minutesUsed > 0).toList();
      
    } catch (e, stack) {
      print('Error getting usage stats: $e\n$stack');
      return [];
    }
  }

  Future<int> getTotalScreenTimeMinutes(DateTime startTime, {Set<String>? educationalApps}) async {
    if (!_isAndroid) return 0;
    final usage = await getUsageSince(startTime, parentDefinedEducational: educationalApps);
    return usage.fold<int>(0, (sum, app) => sum + app.minutesUsed);
  }

  // Legacy method
  Future<int> getScreenTimeMinutes(DateTime startTime) async {
    return await getTotalScreenTimeMinutes(startTime);
  }

  Future<Map<String, int>> getCategorizedUsage(DateTime startTime, {Set<String>? parentDefinedEducational}) async {
    if (!_isAndroid) return {'educational': 0, 'entertainment': 0, 'utility': 0, 'total': 0};
    
    final usage = await getUsageSince(startTime, parentDefinedEducational: parentDefinedEducational);
    
    int educational = 0;
    int entertainment = 0;
    
    for (var app in usage) {
      if (app.isEducational) {
        educational += app.minutesUsed;
      } else {
        entertainment += app.minutesUsed;
      }
    }
    
    return {
      'educational': educational,
      'entertainment': entertainment,
      'utility': 0,
      'total': educational + entertainment,
    };
  }

  bool isBedtime({int bedtimeStart = 21, int bedtimeEnd = 7}) {
    final now = DateTime.now();
    final hour = now.hour;
    
    if (bedtimeStart > bedtimeEnd) {
      return hour >= bedtimeStart || hour < bedtimeEnd;
    } else {
      return hour >= bedtimeStart && hour < bedtimeEnd;
    }
  }
}