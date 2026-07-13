import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../models/usage_entry.dart';

class UsageTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Known app categorization database
  final Map<String, UsageCategory> _appDatabase = {
    // Educational
    'com.khanacademy.android': UsageCategory.educational,
    'com.duolingo': UsageCategory.educational,
    'com.google.android.apps.classroom': UsageCategory.educational,
    'com.brainpop.android': UsageCategory.educational,
    'com.pbskids.video': UsageCategory.educational,
    'com.scratchjr.android': UsageCategory.educational,
    'com.google.android.apps.docs.editors.docs': UsageCategory.educational,
    'com.microsoft.office.word': UsageCategory.educational,
    'com.microsoft.office.powerpoint': UsageCategory.educational,
    'com.zoom.us': UsageCategory.educational,
    'com.microsoft.teams': UsageCategory.educational,
    'com.apple.iwork.pages': UsageCategory.educational,
    'com.apple.iwork.numbers': UsageCategory.educational,
    'com.apple.iwork.keynote': UsageCategory.educational,
    'com.epic.books': UsageCategory.educational,
    'com.amazon.kindle': UsageCategory.educational,
    'com.google.android.apps.books': UsageCategory.educational,
    'com.tocaboca.tocakitchen2': UsageCategory.educational,
    
    // Entertainment
    'com.google.android.youtube': UsageCategory.entertainment,
    'com.facebook.katana': UsageCategory.entertainment,
    'com.facebook.orca': UsageCategory.entertainment,
    'com.instagram.android': UsageCategory.entertainment,
    'com.snapchat.android': UsageCategory.entertainment,
    'com.zhiliaoapp.musically': UsageCategory.entertainment,
    'com.netflix.mediaclient': UsageCategory.entertainment,
    'com.disney.disneyplus': UsageCategory.entertainment,
    'com.hulu.plus': UsageCategory.entertainment,
    'com.amazon.avod.thirdpartyclient': UsageCategory.entertainment,
    'com.spotify.music': UsageCategory.entertainment,
    'com.roblox.client': UsageCategory.entertainment,
    'com.supercell.clashofclans': UsageCategory.entertainment,
    'com.king.candycrushsaga': UsageCategory.entertainment,
    'com.minecraft.minecraftpe': UsageCategory.entertainment,
    'com.twitch.android.app': UsageCategory.entertainment,
    'com.discord': UsageCategory.entertainment,
    'com.twitter.android': UsageCategory.entertainment,
    'tv.twitch.android.app': UsageCategory.entertainment,
    
    // Utility
    'com.android.dialer': UsageCategory.utility,
    'com.google.android.dialer': UsageCategory.utility,
    'com.android.contacts': UsageCategory.utility,
    'com.android.camera': UsageCategory.utility,
    'com.google.android.apps.camera': UsageCategory.utility,
    'com.android.settings': UsageCategory.utility,
    'com.google.android.apps.maps': UsageCategory.utility,
    'com.android.calculator2': UsageCategory.utility,
    'com.google.android.calculator': UsageCategory.utility,
    'com.google.android.gm': UsageCategory.utility,
    'com.android.messaging': UsageCategory.utility,
    'com.whatsapp': UsageCategory.utility,
    'com.apple.mobilephone': UsageCategory.utility,
    'com.apple.camera': UsageCategory.utility,
    'com.apple.Maps': UsageCategory.utility,
  };

  // Get icon for app package
  IconData getAppIcon(String packageName) {
    final iconMap = {
      'com.google.android.youtube': Icons.play_circle_fill,
      'com.facebook.katana': Icons.facebook,
      'com.instagram.android': Icons.camera_alt,
      'com.snapchat.android': Icons.camera_enhance,
      'com.netflix.mediaclient': Icons.movie,
      'com.roblox.client': Icons.videogame_asset,
      'com.minecraft.minecraftpe': Icons.landscape,
      'com.khanacademy.android': Icons.school,
      'com.duolingo': Icons.language,
      'com.google.android.apps.classroom': Icons.class_,
      'com.zoom.us': Icons.video_call,
      'com.whatsapp': Icons.chat,
      'com.android.settings': Icons.settings,
      'com.google.android.apps.maps': Icons.map,
      'com.spotify.music': Icons.music_note,
      'com.discord': Icons.chat_bubble,
    };
    return iconMap[packageName] ?? Icons.apps;
  }

  // Get color for app package
  Color getAppColor(String packageName) {
    if (_appDatabase[packageName] == UsageCategory.educational) return Colors.green;
    if (_appDatabase[packageName] == UsageCategory.entertainment) return Colors.orange;
    if (_appDatabase[packageName] == UsageCategory.utility) return Colors.blue;
    return Colors.grey;
  }

  // Get app display name
  String getAppDisplayName(String package, String className) {
    final knownNames = {
      'com.khanacademy.android': 'Khan Academy',
      'com.duolingo': 'Duolingo',
      'com.google.android.youtube': 'YouTube',
      'com.facebook.katana': 'Facebook',
      'com.instagram.android': 'Instagram',
      'com.netflix.mediaclient': 'Netflix',
      'com.roblox.client': 'Roblox',
      'com.minecraft.minecraftpe': 'Minecraft',
      'com.snapchat.android': 'Snapchat',
      'com.whatsapp': 'WhatsApp',
      'com.discord': 'Discord',
    };
    
    return knownNames[package] ?? className.split('.').last;
  }

  // NEW: Get comprehensive automatic quick summary data
  Future<Map<String, dynamic>> getAutomaticQuickSummaryData(String childId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final yesterday = startOfDay.subtract(const Duration(days: 1));
      final weekAgo = startOfDay.subtract(const Duration(days: 7));

      // Get child's screen time rules for bedtime check
      final childDoc = await _firestore.collection('users').doc(childId).get();
      final childData = childDoc.data() ?? {};
      final bedtimeStart = childData['bedtimeStart'] ?? 21; // 9pm default
      final bedtimeEnd = childData['bedtimeEnd'] ?? 7; // 7am default
      final dailyLimit = childData['dailyScreenTimeLimit'] ?? 120; // 2 hours default

      // Get ONLY automatic entries for today
      final todaySnapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('usageEntries')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .where('source', isEqualTo: 'automatic')
          .where('verified', isEqualTo: true)
          .get();

      // Get yesterday's automatic entries for comparison
      final yesterdaySnapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('usageEntries')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday))
          .where('timestamp', isLessThan: Timestamp.fromDate(startOfDay))
          .where('source', isEqualTo: 'automatic')
          .where('verified', isEqualTo: true)
          .get();

      // Get week's automatic entries for average
      final weekSnapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('usageEntries')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .where('source', isEqualTo: 'automatic')
          .where('verified', isEqualTo: true)
          .get();

      // Process today's data
      int eduToday = 0, entToday = 0, utilToday = 0;
      final Map<String, Map<String, dynamic>> appStats = {}; // package -> {name, minutes, opens}
      final Map<int, int> hourlyUsage = {}; // hour -> minutes
      int totalSessions = 0;
      int longestSession = 0;
      DateTime? lastEventTime;
      DateTime? firstPickup;
      int bedtimeViolationMinutes = 0;
      int rapidSwitches = 0;
      String? lastPackage;

      for (var doc in todaySnapshot.docs) {
        final entry = UsageEntry.fromMap(doc.data());
        totalSessions++;
        
        // Track categories
        switch (entry.category) {
          case UsageCategory.educational:
            eduToday += entry.durationMinutes;
            break;
          case UsageCategory.entertainment:
            entToday += entry.durationMinutes;
            break;
          case UsageCategory.utility:
            utilToday += entry.durationMinutes;
            break;
        }

        // Track app usage (frequency + duration)
        final pkg = entry.packageName ?? 'unknown';
        if (!appStats.containsKey(pkg)) {
          appStats[pkg] = {
            'name': entry.appName,
            'package': pkg,
            'minutes': 0,
            'opens': 0,
            'category': entry.category,
          };
        }
        appStats[pkg]!['minutes'] += entry.durationMinutes;
        appStats[pkg]!['opens'] += 1;

        // Track hourly usage
        final hour = entry.timestamp.hour;
        hourlyUsage[hour] = (hourlyUsage[hour] ?? 0) + entry.durationMinutes;

        // Check bedtime violation
        if (hour >= bedtimeStart || hour < bedtimeEnd) {
          bedtimeViolationMinutes += entry.durationMinutes;
        }

        // Track first pickup
        if (firstPickup == null || entry.timestamp.isBefore(firstPickup)) {
          firstPickup = entry.timestamp;
        }

        // Track last event for "currently active"
        if (lastEventTime == null || entry.timestamp.isAfter(lastEventTime)) {
          lastEventTime = entry.timestamp;
        }
        lastPackage = pkg;

        // Track rapid switching (app switches without 5 min gap)
        if (lastPackage != null && lastPackage != pkg) {
          rapidSwitches++;
        }
      }

      // Calculate longest session (simplified: max single entry duration)
      for (var doc in todaySnapshot.docs) {
        final entry = UsageEntry.fromMap(doc.data());
        if (entry.durationMinutes > longestSession) {
          longestSession = entry.durationMinutes;
        }
      }

      // Check if currently active (last event within 5 minutes)
      bool isCurrentlyActive = false;
      String? currentApp;
      if (lastEventTime != null) {
        final diff = now.difference(lastEventTime).inMinutes;
        isCurrentlyActive = diff < 5;
        if (isCurrentlyActive) currentApp = lastPackage;
      }

      // Calculate yesterday's total
      int yesterdayTotal = 0;
      for (var doc in yesterdaySnapshot.docs) {
        yesterdayTotal += UsageEntry.fromMap(doc.data()).durationMinutes;
      }

      // Calculate weekly average
      int weekTotal = 0;
      for (var doc in weekSnapshot.docs) {
        weekTotal += UsageEntry.fromMap(doc.data()).durationMinutes;
      }
      final weeklyAverage = weekSnapshot.docs.isEmpty ? 0 : (weekTotal / 7).round();

      // Get top 3 apps by duration
      final sortedApps = appStats.values.toList()
        ..sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));
      final topApps = sortedApps.take(3).toList();

      // Calculate wellness score (0-100)
      final totalToday = eduToday + entToday + utilToday;
      double eduRatio = totalToday > 0 ? eduToday / totalToday : 0; // FIXED: Define eduRatio here
      
      double wellnessScore = 0;
      if (totalToday > 0) {
        // Educational ratio (up to 40 points)
        wellnessScore += eduRatio * 40;
        
        // Time limit compliance (up to 30 points)
        if (totalToday <= dailyLimit) {
          wellnessScore += 30;
        } else if (totalToday <= dailyLimit * 1.5) {
          wellnessScore += 15;
        }
        
        // Bedtime compliance (up to 20 points)
        if (bedtimeViolationMinutes == 0) {
          wellnessScore += 20;
        } else if (bedtimeViolationMinutes < 30) {
          wellnessScore += 10;
        }
        
        // Session health (up to 10 points) - no binges over 2 hours
        if (longestSession <= 120) {
          wellnessScore += 10;
        } else if (longestSession <= 180) {
          wellnessScore += 5;
        }
        
        wellnessScore = wellnessScore.clamp(0, 100);
      }

      // Generate AI insight
      String aiInsight;
      final displayName = childData['name'] ?? 'Your child';
      
      if (totalToday == 0) {
        aiInsight = "No automatic tracking data yet. Ensure Usage Stats permission is enabled.";
      } else if (isCurrentlyActive) {
        final appName = currentApp != null ? getAppDisplayName(currentApp, currentApp) : 'device';
        aiInsight = "📱 Currently active on $appName. Total today: ${_formatDuration(totalToday)}.";
      } else if (bedtimeViolationMinutes > 30) {
        aiInsight = "⚠️ Bedtime violation detected: ${bedtimeViolationMinutes}min used during restricted hours ($bedtimeStart:00-$bedtimeEnd:00).";
      } else if (eduRatio < 0.2 && totalToday > 60) {
        aiInsight = "🎮 High entertainment ratio (${(entToday/totalToday*100).round()}%). Consider suggesting educational apps before dinner.";
      } else if (longestSession > 120) {
        aiInsight = "⏰ Long binge session detected (${_formatDuration(longestSession)}). Consider enabling break reminders.";
      } else if (totalToday > dailyLimit) {
        aiInsight = "📊 Daily limit exceeded by ${totalToday - dailyLimit} minutes. Device may need to be set aside.";
      } else if (eduRatio > 0.5) {
        aiInsight = "🌟 Excellent balance! ${(eduToday/totalToday*100).round()}% educational content. Within healthy time limits.";
      } else {
        aiInsight = "✅ Normal usage pattern. $totalSessions sessions, ${_formatDuration(totalToday)} total. All metrics within range.";
      }

      return {
        'totalMinutes': totalToday,
        'educational': eduToday,
        'entertainment': entToday,
        'utility': utilToday,
        'educationalRatio': eduRatio,
        'yesterdayTotal': yesterdayTotal,
        'weeklyAverage': weeklyAverage,
        'topApps': topApps,
        'hourlyUsage': hourlyUsage,
        'wellnessScore': wellnessScore.round(),
        'aiInsight': aiInsight,
        'entryCount': totalSessions,
        'longestSession': longestSession,
        'firstPickup': firstPickup?.toString() ?? 'N/A',
        'bedtimeViolationMinutes': bedtimeViolationMinutes,
        'isCurrentlyActive': isCurrentlyActive,
        'currentApp': currentApp,
        'rapidSwitches': rapidSwitches,
        'dailyLimit': dailyLimit,
        'hasData': todaySnapshot.docs.isNotEmpty,
        'childName': displayName,
      };
    } catch (e) {
      print('Error getting automatic quick summary: $e');
      return {
        'totalMinutes': 0,
        'educational': 0,
        'entertainment': 0,
        'utility': 0,
        'yesterdayTotal': 0,
        'weeklyAverage': 0,
        'topApps': [],
        'hourlyUsage': {},
        'wellnessScore': 0,
        'aiInsight': 'Unable to load automatic tracking data. Check permissions.',
        'entryCount': 0,
        'longestSession': 0,
        'isCurrentlyActive': false,
        'hasData': false,
      };
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  // Manual logging: Child submits entry
  Future<String> submitManualEntry({
    required String appName,
    required int durationMinutes,
    required UsageCategory category,
    String? notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final entry = UsageEntry(
      id: _firestore.collection('usageLogs').doc().id,
      childId: user.uid,
      timestamp: DateTime.now(),
      appName: appName,
      durationMinutes: durationMinutes,
      category: category,
      source: 'manual',
      verified: false,
      notes: notes,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usageEntries')
        .doc(entry.id)
        .set(entry.toMap());

    return entry.id;
  }

  // Get today's entries for child
  Stream<List<UsageEntry>> getTodayEntries(String childId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection('users')
        .doc(childId)
        .collection('usageEntries')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UsageEntry.fromMap(doc.data()))
            .toList());
  }

  // FIXED: Get pending verification entries for parent
  Stream<List<UsageEntry>> getPendingVerifications(String parentId) {
    return _firestore
        .collection('users')
        .where('parentId', isEqualTo: parentId)
        .snapshots()
        .asyncMap((childrenSnapshot) async {
      final entries = <UsageEntry>[];
      
      for (var childDoc in childrenSnapshot.docs) {
        final childId = childDoc.id;
        
        try {
          final snapshot = await _firestore
              .collection('users')
              .doc(childId)
              .collection('usageEntries')
              .where('verified', isEqualTo: false)
              .where('source', isEqualTo: 'manual')
              .get();
          
          for (var doc in snapshot.docs) {
            entries.add(UsageEntry.fromMap(doc.data()));
          }
        } catch (e) {
          print('Error fetching entries for child $childId: $e');
        }
      }
      
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    });
  }

  // Parent verifies entry
  Future<void> verifyEntry(String childId, String entryId, bool approved) async {
    final docRef = _firestore
        .collection('users')
        .doc(childId)
        .collection('usageEntries')
        .doc(entryId);

    if (approved) {
      await docRef.update({'verified': true});
    } else {
      await docRef.delete();
    }
  }

  // Get daily summary
  Future<Map<String, dynamic>> getDailySummary(String childId, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection('users')
          .doc(childId)
          .collection('usageEntries')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .where('verified', isEqualTo: true)
          .get();

      int educational = 0;
      int entertainment = 0;
      int utility = 0;

      for (var doc in snapshot.docs) {
        final entry = UsageEntry.fromMap(doc.data());
        switch (entry.category) {
          case UsageCategory.educational:
            educational += entry.durationMinutes;
            break;
          case UsageCategory.entertainment:
            entertainment += entry.durationMinutes;
            break;
          case UsageCategory.utility:
            utility += entry.durationMinutes;
            break;
        }
      }

      final total = educational + entertainment + utility;

      return {
        'educational': educational,
        'entertainment': entertainment,
        'utility': utility,
        'total': total,
        'educationalRatio': total > 0 ? educational / total : 0,
        'date': date,
      };
    } catch (e) {
      print('Error in getDailySummary: $e');
      return {
        'educational': 0,
        'entertainment': 0,
        'utility': 0,
        'total': 0,
        'educationalRatio': 0.0,
        'date': date,
      };
    }
  }

  // Get weekly trend data
  Future<List<Map<String, dynamic>>> getWeeklyTrend(String childId) async {
    final List<Map<String, dynamic>> results = [];
    final now = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final summary = await getDailySummary(childId, date);
      summary['day'] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][date.weekday % 7];
      results.add(summary);
    }

    return results;
  }

  // Android automatic tracking - ENHANCED
  Future<List<UsageEntry>> syncAndroidUsage(String childId) async {
    try {
      final bool? hasPermission = await UsageStats.checkUsagePermission();
      if (hasPermission != true) {
        print('Usage permission not granted.');
        return [];
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      
      // Query events from today
      final events = await UsageStats.queryEvents(startOfDay, now);
      final Map<String, int> appUsage = {}; // package -> minutes
      final Map<String, int> appOpens = {}; // package -> open count
      final Map<String, String> appNames = {};

      // Process events to calculate session time
      DateTime? lastEventTime;
      String? lastPackage;
      
      for (var event in events) {
        if (event.eventType == '1') { // ACTIVITY_RESUMED (app opened/foreground)
          final package = event.packageName ?? '';
          if (package.isNotEmpty && !package.contains('str_app')) {
            final eventTime = DateTime.fromMillisecondsSinceEpoch(int.parse(event.timeStamp!));
            
            // If we have a previous event, calculate time spent
            if (lastPackage != null && lastEventTime != null) {
              final diff = eventTime.difference(lastEventTime).inMinutes;
              if (diff > 0 && diff < 60) { // Ignore gaps > 1 hour (phone was locked)
                appUsage[lastPackage] = (appUsage[lastPackage] ?? 0) + diff;
              }
            }
            
            appOpens[package] = (appOpens[package] ?? 0) + 1;
            appNames[package] = event.className ?? package;
            lastPackage = package;
            lastEventTime = eventTime;
          }
        }
      }

      final List<UsageEntry> autoEntries = [];
      
      for (var entry in appUsage.entries) {
        final package = entry.key;
        final minutes = entry.value;
        
        if (minutes < 1) continue; // Skip very short usage

        final category = _appDatabase[package] ?? UsageCategory.utility;
        final appName = getAppDisplayName(package, appNames[package] ?? '');
        final opens = appOpens[package] ?? 1;

        // Check if entry already exists for this app today
        final existing = await _firestore
            .collection('users')
            .doc(childId)
            .collection('usageEntries')
            .where('packageName', isEqualTo: package)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(startOfDay))
            .where('source', isEqualTo: 'automatic')
            .get();

        if (existing.docs.isEmpty) {
          final autoEntry = UsageEntry(
            id: _firestore.collection('usageLogs').doc().id,
            childId: childId,
            timestamp: now,
            appName: appName,
            packageName: package,
            durationMinutes: minutes,
            category: category,
            source: 'automatic',
            verified: true,
            notes: 'Auto-tracked: $opens opens',
            createdAt: now,
          );

          await _firestore
              .collection('users')
              .doc(childId)
              .collection('usageEntries')
              .doc(autoEntry.id)
              .set(autoEntry.toMap());

          autoEntries.add(autoEntry);
        } else {
          // Update existing entry with new data
          final doc = existing.docs.first;
          final existingData = UsageEntry.fromMap(doc.data());
          final newDuration = existingData.durationMinutes + minutes;
          final newOpens = int.parse(existingData.notes?.split(' ')[1] ?? '0') + opens;
          
          await doc.reference.update({
            'durationMinutes': newDuration,
            'notes': 'Auto-tracked: $newOpens opens',
            'timestamp': Timestamp.fromDate(now), // Update to latest
          });
        }
      }

      return autoEntries;
    } catch (e) {
      print('Error syncing usage: $e');
      return [];
    }
  }

  // Export to CSV
  Future<void> exportToCSV(String childId, DateTime startDate, DateTime endDate) async {
    final entries = await _getEntriesInRange(childId, startDate, endDate);
    
    final List<List<dynamic>> rows = [
      ['Date', 'Time', 'App Name', 'Category', 'Duration (min)', 'Source', 'Verified']
    ];

    for (var entry in entries) {
      rows.add([
        entry.timestamp.toString().split(' ')[0],
        entry.timestamp.toString().split(' ')[1].substring(0, 5),
        entry.appName,
        entry.category.displayName,
        entry.durationMinutes,
        entry.source,
        entry.verified ? 'Yes' : 'No',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/usage_report_${childId}_${startDate.toIso8601String().split('T')[0]}.csv');
    await file.writeAsString(csv);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Screen Usage Report');
  }

  // Export to JSON
  Future<void> exportToJSON(String childId, DateTime startDate, DateTime endDate) async {
    final entries = await _getEntriesInRange(childId, startDate, endDate);
    
    final data = {
      'childId': childId,
      'exportDate': DateTime.now().toIso8601String(),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'entries': entries.map((e) => e.toMap()).toList(),
      'summary': {
        'totalEntries': entries.length,
        'educationalMinutes': entries.where((e) => e.category == UsageCategory.educational).fold(0, (sum, e) => sum + e.durationMinutes),
        'entertainmentMinutes': entries.where((e) => e.category == UsageCategory.entertainment).fold(0, (sum, e) => sum + e.durationMinutes),
        'utilityMinutes': entries.where((e) => e.category == UsageCategory.utility).fold(0, (sum, e) => sum + e.durationMinutes),
      }
    };

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/usage_report_${childId}_${startDate.toIso8601String().split('T')[0]}.json');
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(data));
    
    await Share.shareXFiles([XFile(file.path)], text: 'Screen Usage JSON Report');
  }

  Future<List<UsageEntry>> _getEntriesInRange(String childId, DateTime start, DateTime end) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(childId)
        .collection('usageEntries')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .where('verified', isEqualTo: true)
        .get();

    return snapshot.docs.map((doc) => UsageEntry.fromMap(doc.data())).toList();
  }

  // Get comparison data
  Future<Map<String, dynamic>> getComparisonData(
    String childId,
    DateTime startDate,
    DateTime endDate,
    String comparisonType,
  ) async {
    try {
      final days = endDate.difference(startDate).inDays + 1;
      final List<Map<String, dynamic>> dailyData = [];

      for (int i = 0; i < days; i++) {
        final date = startDate.add(Duration(days: i));
        final summary = await getDailySummary(childId, date);
        
        dailyData.add({
          'date': date.toString().split(' ')[0],
          'educational': summary['educational'],
          'entertainment': summary['entertainment'],
          'utility': summary['utility'],
        });
      }

      return {
        'comparisonType': comparisonType,
        'dailyData': dailyData,
        'totals': {
          'educational': dailyData.fold(0, (sum, d) => sum + ((d['educational'] as num?)?.toInt() ?? 0)),
          'entertainment': dailyData.fold(0, (sum, d) => sum + ((d['entertainment'] as num?)?.toInt() ?? 0)),
          'utility': dailyData.fold(0, (sum, d) => sum + ((d['utility'] as num?)?.toInt() ?? 0)),
        }
      };
    } catch (e) {
      print('Error in getComparisonData: $e');
      throw Exception('Failed to load analytics data: $e');
    }
  }
}