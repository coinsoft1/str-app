// lib/widgets/daily_usage_summary.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import '../services/usage_sync_service.dart';

enum ViewMode { day, week, month }

class DailyUsageSummary extends StatefulWidget {
  final String childId;
  final String? childName;
  final ScrollController? scrollController;

  const DailyUsageSummary({
    super.key,
    required this.childId,
    this.childName,
    this.scrollController,
  });

  @override
  State<DailyUsageSummary> createState() => _DailyUsageSummaryState();
}

class _DailyUsageSummaryState extends State<DailyUsageSummary> {
  ViewMode _viewMode = ViewMode.day;
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> entries = [];
  List<Map<String, dynamic>> autoTrackedApps = [];
  bool isLoading = true;
  bool isExporting = false;
  final GlobalKey _printKey = GlobalKey();

  // Metrics
  Map<String, int> timeOfDayBreakdown = {
    'morning': 0,
    'afternoon': 0,
    'evening': 0,
    'night': 0,
  };

  int longestSession = 0;
  String? firstPickupTime;
  double vsYesterdayPercent = 0;
  int weeklyAverage = 0;
  int pointsImpact = 0;
  int bedtimeUsage = 0;
  int learningStreak = 0;
  String topCategory = 'None';
  String peakTimeLabel = '';
  String peakTimeRange = '';
  int peakTimeMinutes = 0;
  String? lastSyncedTime;
  String dataSource = '';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void didUpdateWidget(DailyUsageSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      loadData();
    }
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    data = {};
    entries = [];
    autoTrackedApps = [];
    timeOfDayBreakdown = {'morning': 0, 'afternoon': 0, 'evening': 0, 'night': 0};
    longestSession = 0;
    firstPickupTime = null;
    vsYesterdayPercent = 0;
    weeklyAverage = 0;
    pointsImpact = 0;
    bedtimeUsage = 0;
    learningStreak = 0;
    topCategory = 'None';
    peakTimeLabel = '';
    peakTimeRange = '';
    peakTimeMinutes = 0;
    lastSyncedTime = null;
    dataSource = '';

    try {
      switch (_viewMode) {
        case ViewMode.day:
          await _loadDailyData();
          break;
        case ViewMode.week:
          await _loadWeeklyData();
          break;
        case ViewMode.month:
          await _loadMonthlyData();
          break;
      }
      await _calculateStreaks();
      _calculatePeakTime();
    } catch (e) {
      print('Error loading usage data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadDailyData() async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final today = await UsageSyncService.getUsageForDate(widget.childId, dateStr);
      if (today != null) {
        data = today;
        dataSource = today['source'] as String? ?? 'unknown';

        final syncTimestamp = today['syncTimestamp'] as Timestamp?;
        if (syncTimestamp != null) {
          lastSyncedTime = DateFormat('h:mm a').format(syncTimestamp.toDate());
        }

        final pickupTimestamp = today['firstPickupTime'] as Timestamp?;
        if (pickupTimestamp != null) {
          firstPickupTime = DateFormat('h:mm a').format(pickupTimestamp.toDate());
        }

        final appDetails = today['appDetails'] as Map<String, dynamic>?;
        if (appDetails != null) {
          autoTrackedApps = appDetails.entries.map((entry) {
            final appData = entry.value as Map<String, dynamic>;
            return {
              'appName': entry.key,
              'durationMinutes': appData['minutes'] ?? 0,
              'category': appData['category'] ?? 'other',
            };
          }).toList();

          autoTrackedApps.sort((a, b) =>
              (b['durationMinutes'] as int).compareTo(a['durationMinutes'] as int)
          );
        }
      }

      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final entriesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('sessionLogs')
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('startTime', descending: false)
          .get();

      entries = entriesSnapshot.docs.map((doc) {
        final d = doc.data();
        d['id'] = doc.id;
        return d;
      }).toList();

      _processEntries();
      await _calculateDailyMetrics();
    } catch (e) {
      print('Error in _loadDailyData: $e');
    }
  }

  Future<void> _loadWeeklyData() async {
    List<Map<String, dynamic>> weekData = [];
    entries = [];
    autoTrackedApps = [];
    int daysWithData = 0;
    DateTime? earliestFirstPickup;

    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      try {
        final dayData = await UsageSyncService.getUsageForDate(widget.childId, dateStr);
        if (dayData != null) {
          weekData.add(dayData);
          if ((dayData['totalMinutes'] ?? 0) > 0) daysWithData++;

          final appDetails = dayData['appDetails'] as Map<String, dynamic>?;
          if (appDetails != null) {
            for (var entry in appDetails.entries) {
              final appData = entry.value as Map<String, dynamic>;
              final existingIndex = autoTrackedApps.indexWhere((a) => a['appName'] == entry.key);
              if (existingIndex >= 0) {
                autoTrackedApps[existingIndex]['durationMinutes'] += appData['minutes'] ?? 0;
              } else {
                autoTrackedApps.add({
                  'appName': entry.key,
                  'durationMinutes': appData['minutes'] ?? 0,
                  'category': appData['category'] ?? 'other',
                });
              }
            }
          }

          final pickupTimestamp = dayData['firstPickupTime'] as Timestamp?;
          if (pickupTimestamp != null) {
            if (earliestFirstPickup == null || pickupTimestamp.toDate().isBefore(earliestFirstPickup)) {
              earliestFirstPickup = pickupTimestamp.toDate();
            }
          }

          final startOfDay = DateTime(date.year, date.month, date.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));

          final dayEntries = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.childId)
              .collection('sessionLogs')
              .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
              .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
              .get();

          entries.addAll(dayEntries.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            data['_date'] = date;
            return data;
          }));
        }
      } catch (e) {
        print('Error loading day $i: $e');
      }
    }

    autoTrackedApps.sort((a, b) =>
        (b['durationMinutes'] as int).compareTo(a['durationMinutes'] as int)
    );

    if (earliestFirstPickup != null) {
      firstPickupTime = DateFormat('h:mm a').format(earliestFirstPickup);
    }

    int totalMinutes = 0;
    int totalEdu = 0;
    int totalEnt = 0;
    int totalUtil = 0;
    int totalSessions = 0;

    for (var day in weekData) {
      totalMinutes += (day['totalMinutes'] ?? 0) as int;
      totalEdu += (day['educationMinutes'] ?? 0) as int;
      totalEnt += (day['entertainmentMinutes'] ?? 0) as int;
      totalUtil += (day['otherMinutes'] ?? 0) as int;
      totalSessions += (day['sessionCount'] ?? 0) as int;
    }

    data = {
      'totalMinutes': totalMinutes,
      'educationMinutes': totalEdu,
      'entertainmentMinutes': totalEnt,
      'utilityMinutes': totalUtil,
      'sessionCount': totalSessions,
      'dailyLimit': 120 * 7,
      'daysWithData': daysWithData,
    };

    _processEntries();
    _calculateWeeklyMetrics(weekData);
  }

  Future<void> _loadMonthlyData() async {
    List<Map<String, dynamic>> monthData = [];
    entries = [];
    autoTrackedApps = [];
    DateTime? earliestFirstPickup;

    for (int i = 0; i < 30; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      try {
        final dayData = await UsageSyncService.getUsageForDate(widget.childId, dateStr);
        if (dayData != null) {
          monthData.add(dayData);

          final appDetails = dayData['appDetails'] as Map<String, dynamic>?;
          if (appDetails != null) {
            for (var entry in appDetails.entries) {
              final appData = entry.value as Map<String, dynamic>;
              final existingIndex = autoTrackedApps.indexWhere((a) => a['appName'] == entry.key);
              if (existingIndex >= 0) {
                autoTrackedApps[existingIndex]['durationMinutes'] += appData['minutes'] ?? 0;
              } else {
                autoTrackedApps.add({
                  'appName': entry.key,
                  'durationMinutes': appData['minutes'] ?? 0,
                  'category': appData['category'] ?? 'other',
                });
              }
            }
          }

          final pickupTimestamp = dayData['firstPickupTime'] as Timestamp?;
          if (pickupTimestamp != null) {
            if (earliestFirstPickup == null || pickupTimestamp.toDate().isBefore(earliestFirstPickup)) {
              earliestFirstPickup = pickupTimestamp.toDate();
            }
          }

          final startOfDay = DateTime(date.year, date.month, date.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));

          final dayEntries = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.childId)
              .collection('sessionLogs')
              .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
              .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
              .get();

          entries.addAll(dayEntries.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            data['_date'] = date;
            return data;
          }));
        }
      } catch (e) {
        print('Error loading day $i: $e');
      }
    }

    autoTrackedApps.sort((a, b) =>
        (b['durationMinutes'] as int).compareTo(a['durationMinutes'] as int)
    );

    if (earliestFirstPickup != null) {
      firstPickupTime = DateFormat('h:mm a').format(earliestFirstPickup);
    }

    int totalMinutes = 0;
    int totalEdu = 0;
    int totalEnt = 0;
    int totalUtil = 0;
    int totalSessions = 0;

    for (var day in monthData) {
      totalMinutes += (day['totalMinutes'] ?? 0) as int;
      totalEdu += (day['educationMinutes'] ?? 0) as int;
      totalEnt += (day['entertainmentMinutes'] ?? 0) as int;
      totalUtil += (day['otherMinutes'] ?? 0) as int;
      totalSessions += (day['sessionCount'] ?? 0) as int;
    }

    data = {
      'totalMinutes': totalMinutes,
      'educationMinutes': totalEdu,
      'entertainmentMinutes': totalEnt,
      'utilityMinutes': totalUtil,
      'sessionCount': totalSessions,
      'dailyLimit': 120 * 30,
    };

    _processEntries();
    _calculateWeeklyMetrics(monthData);
  }

  void _processEntries() {
    final localTimeOfDayBreakdown = {'morning': 0, 'afternoon': 0, 'evening': 0, 'night': 0};
    int localLongestSession = 0;
    int localBedtimeUsage = 0;
    int totalSessionMinutes = 0;
    int sessionCount = 0;

    for (var entry in entries) {
      final timestamp = (entry['startTime'] as Timestamp?)?.toDate();
      final duration = (entry['durationMinutes'] as num?)?.toInt() ?? 0;

      if (timestamp != null) {
        final hour = timestamp.hour;

        if (hour >= 6 && hour < 12) {
          localTimeOfDayBreakdown['morning'] = localTimeOfDayBreakdown['morning']! + duration;
        } else if (hour >= 12 && hour < 18) {
          localTimeOfDayBreakdown['afternoon'] = localTimeOfDayBreakdown['afternoon']! + duration;
        } else if (hour >= 18 && hour < 22) {
          localTimeOfDayBreakdown['evening'] = localTimeOfDayBreakdown['evening']! + duration;
        } else {
          localTimeOfDayBreakdown['night'] = localTimeOfDayBreakdown['night']! + duration;
          localBedtimeUsage += duration;
        }

        if (duration > localLongestSession) {
          localLongestSession = duration;
        }

        totalSessionMinutes += duration;
        sessionCount++;
      }
    }

    timeOfDayBreakdown = localTimeOfDayBreakdown;
    longestSession = localLongestSession;
    bedtimeUsage = localBedtimeUsage;

    if (sessionCount > 0) {
      data['averageSession'] = totalSessionMinutes ~/ sessionCount;
    }
  }

  void _calculatePeakTime() {
    int max = 0;
    String label = 'None';
    String range = '--';

    timeOfDayBreakdown.forEach((key, value) {
      if (value > max) {
        max = value;
        switch (key) {
          case 'morning':
            label = 'Morning';
            range = '6am - 12pm';
            break;
          case 'afternoon':
            label = 'Afternoon';
            range = '12pm - 6pm';
            break;
          case 'evening':
            label = 'Evening';
            range = '6pm - 10pm';
            break;
          case 'night':
            label = 'Night';
            range = '10pm - 6am';
            break;
        }
      }
    });

    peakTimeLabel = label;
    peakTimeRange = range;
    peakTimeMinutes = max;
  }

  Future<void> _calculateDailyMetrics() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final yesterdayData = await UsageSyncService.getUsageForDate(widget.childId, yesterdayStr);

    if (yesterdayData != null && (yesterdayData['totalMinutes'] ?? 0) > 0) {
      final yesterdayMin = yesterdayData['totalMinutes'] as int;
      final todayMin = data['totalMinutes'] ?? 0;
      vsYesterdayPercent = ((todayMin - yesterdayMin) / yesterdayMin) * 100;
    }

    int weekTotal = 0;
    int days = 0;
    for (int i = 1; i <= 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dayData = await UsageSyncService.getUsageForDate(widget.childId, dateStr);
      if (dayData != null && (dayData['totalMinutes'] ?? 0) > 0) {
        weekTotal += (dayData['totalMinutes'] as int);
        days++;
      }
    }
    if (days > 0) {
      weeklyAverage = weekTotal ~/ days;
    }

    await _calculatePointsImpact();
    await _calculateLearningStreak();

    final edu = data['educationMinutes'] ?? 0;
    final ent = data['entertainmentMinutes'] ?? 0;

    if (edu >= ent && edu > 0) {
      topCategory = 'Educational';
    } else if (ent > 0) {
      topCategory = 'Entertainment';
    } else {
      topCategory = 'None';
    }
  }

  void _calculateWeeklyMetrics(List<Map<String, dynamic>> weekData) {
    int daysWithData = weekData.where((d) => (d['totalMinutes'] ?? 0) > 0).length;
    weeklyAverage = daysWithData > 0
        ? (data['totalMinutes'] ?? 0) ~/ daysWithData
        : 0;

    final totalEdu = data['educationMinutes'] ?? 0;
    final totalEnt = data['entertainmentMinutes'] ?? 0;

    if (totalEdu >= totalEnt && totalEdu > 0) {
      topCategory = 'Educational 📚';
    } else if (totalEnt > 0) {
      topCategory = 'Entertainment 🎮';
    } else {
      topCategory = 'None';
    }

    _calculateLearningStreak();
    _calculatePointsImpact();
  }

  Future<void> _calculatePointsImpact() async {
    final total = data['totalMinutes'] ?? 0;
    final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
    _viewMode == ViewMode.week ? (data['dailyLimit'] ?? 840) ~/ 7 :
    (data['dailyLimit'] ?? 3600) ~/ 30;

    if (total > limit) {
      final overage = total - limit;
      pointsImpact = -(overage ~/ 10);
    } else {
      final saved = limit - total;
      pointsImpact = saved ~/ 20;
    }
  }

  Future<void> _calculateLearningStreak() async {
    int streak = 0;
    for (int i = 0; i < 30; i++) {
      try {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final dayData = await UsageSyncService.getUsageForDate(widget.childId, dateStr);

        if (dayData != null) {
          final edu = dayData['educationMinutes'] ?? 0;
          final ent = dayData['entertainmentMinutes'] ?? 0;
          if (edu > ent) {
            streak++;
          } else {
            break;
          }
        } else {
          break;
        }
      } catch (e) {
        break;
      }
    }
    learningStreak = streak;
  }

  Future<void> _calculateStreaks() async {
    // Placeholder for limit/tracking streaks if needed
  }

  bool get _isOverLimit {
    final total = data['totalMinutes'] ?? 0;
    final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
    _viewMode == ViewMode.week ? 840 : 3600;
    return total > limit;
  }

  double get _progress {
    final total = data['totalMinutes'] ?? 0;
    final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
    _viewMode == ViewMode.week ? 840 : 3600;
    if (limit == 0) return 0;
    return (total / limit).clamp(0.0, 1.0);
  }

  String get _periodLabel {
    switch (_viewMode) {
      case ViewMode.day:
        return 'Today';
      case ViewMode.week:
        return 'This Week';
      case ViewMode.month:
        return 'This Month';
    }
  }

  String get _pointsSubtext {
    if (pointsImpact >= 0) {
      return 'Under limit bonus';
    } else {
      final total = data['totalMinutes'] ?? 0;
      final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
      _viewMode == ViewMode.week ? 840 : 3600;
      final overage = total - limit;
      return '${_formatDuration(overage)} over ${(limit ~/ 60)}h limit';
    }
  }

  Future<void> _exportCSV() async {
    setState(() => isExporting = true);
    try {
      final StringBuffer csv = StringBuffer();
      csv.writeln('App Name,Duration (minutes),Category,Type,Status');

      for (var app in autoTrackedApps.take(10)) {
        final name = _cleanAppName(app['appName']);
        final mins = app['durationMinutes'];
        final cat = app['category'];
        csv.writeln('$name,$mins,$cat,Auto-Tracked,verified');
      }

      for (var entry in entries) {
        final name = entry['appName'] ?? 'Unknown';
        final mins = entry['durationMinutes'] ?? 0;
        final cat = entry['category'] ?? 'manual';
        final status = entry['status'] ?? 'unknown';
        csv.writeln('$name,$mins,$cat,Manual Entry,$status');
      }

      csv.writeln('');
      csv.writeln('Summary,,,,');
      csv.writeln('Total Minutes,${data['totalMinutes'] ?? 0},,,');
      csv.writeln('Education Minutes,${data['educationMinutes'] ?? 0},,,');
      csv.writeln('Entertainment Minutes,${data['entertainmentMinutes'] ?? 0},,,');
      csv.writeln('First Pickup,$firstPickupTime,,,');
      csv.writeln('Points Impact,$pointsImpact,,,');
      csv.writeln('Data Source,$dataSource,,,');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/report_${widget.childName ?? 'child'}_${_viewMode.name}.csv');
      await file.writeAsString(csv.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.childName ?? 'Child'}\'s $_periodLabel usage report (CSV)',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      setState(() => isExporting = false);
    }
  }

  Future<void> _copyTextSummary() async {
    final buffer = StringBuffer();
    buffer.writeln('${widget.childName ?? 'Child'}\'s Screen Time Report - $_periodLabel');
    buffer.writeln('Source: ${dataSource == 'manual_logs' ? 'Manual Child Logs' : 'Auto-Tracked'}');
    buffer.writeln('Total: ${_formatDuration(data['totalMinutes'] ?? 0)}');
    buffer.writeln('Limit: ${_formatDuration(_viewMode == ViewMode.day ? 120 : _viewMode == ViewMode.week ? 840 : 3600)}');
    buffer.writeln('Education: ${_formatDuration(data['educationMinutes'] ?? 0)}');
    buffer.writeln('Entertainment: ${_formatDuration(data['entertainmentMinutes'] ?? 0)}');
    buffer.writeln('First Pickup: ${firstPickupTime ?? '--:--'}');
    buffer.writeln('Points: ${pointsImpact > 0 ? '+' : ''}$pointsImpact (${_pointsSubtext})');

    if (autoTrackedApps.isNotEmpty) {
      buffer.writeln('\nTop Apps:');
      for (var app in autoTrackedApps.take(3)) {
        buffer.writeln('- ${_cleanAppName(app['appName'])}: ${_formatDuration(app['durationMinutes'])}');
      }
    }

    await Share.share(buffer.toString(), subject: '${widget.childName ?? 'Child'} Screen Time Report');
  }

  String _cleanAppName(String packageName) {
    if (packageName.contains('.')) {
      final parts = packageName.split('.');
      final name = parts.last;
      if (name.isNotEmpty) {
        return name[0].toUpperCase() + name.substring(1);
      }
    }
    return packageName;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading usage data...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final totalMinutes = data['totalMinutes'] ?? 0;
    final hasData = totalMinutes > 0 || entries.isNotEmpty || autoTrackedApps.isNotEmpty;

    return RepaintBoundary(
      key: _printKey,
      child: Container(
        color: Colors.white,
        child: Stack(
          children: [
            ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _buildHeaderWithExport(),

                if (!hasData) ...[
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.phone_android_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No Usage Data Yet',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No screen time recorded for ${widget.childName ?? 'this child'} on $_periodLabel.\nAsk your child to log their screen time!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        if (lastSyncedTime != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last check: $lastSyncedTime',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (dataSource == 'manual_logs')
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, color: Colors.teal.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Data from child\'s manual logs. Parent verification improves accuracy.',
                              style: TextStyle(
                                color: Colors.teal.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildPeakTimeHeader(),
                  _buildMainStatsCard(),
                  _buildKpiGrid(),
                  _buildContentBalance(),
                  _buildAutoTrackedAppsSection(),
                  _buildManualAppsSection(),
                  _buildInsightCard(),
                ],

                const SizedBox(height: 20),
              ],
            ),
            if (isExporting)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderWithExport() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildToggleButton('Daily', ViewMode.day),
                  _buildToggleButton('Weekly', ViewMode.week),
                  _buildToggleButton('Monthly', ViewMode.month),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'image':
                  _captureAndShareImage();
                  break;
                case 'pdf':
                  _exportPDF();
                  break;
                case 'csv':
                  _exportCSV();
                  break;
                case 'text':
                  _copyTextSummary();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image), title: Text('Share as Image'))),
              const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Export PDF'))),
              const PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.table_chart), title: Text('Export CSV'))),
              const PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.text_snippet), title: Text('Copy Text Summary'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, ViewMode mode) {
    final isSelected = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_viewMode != mode) {
            setState(() => _viewMode = mode);
            loadData();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade700,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeakTimeHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'When ${widget.childName ?? 'Your Child'} Uses Screen Device the Most',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peakTimeLabel,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                ),
                const SizedBox(width: 12),
                Text(
                  peakTimeRange,
                  style: TextStyle(fontSize: 14, color: Colors.blue.shade600),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDuration(peakTimeMinutes),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStatsCard() {
    final total = data['totalMinutes'] ?? 0;
    final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
    _viewMode == ViewMode.week ? 840 : 3600;
    final appOpens = data['sessionCount'] ?? 0;
    final percentage = (_progress * 100).toInt();
    final overage = total > limit ? total - limit : 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isOverLimit
              ? [Colors.red.shade400, Colors.red.shade600]
              : [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (_isOverLimit ? Colors.red : Colors.blue).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$appOpens sessions',
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Limit: ${_formatDuration(limit)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    color: _isOverLimit ? Colors.red : Colors.blue,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _formatDuration(total),
            style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
          ),
          Text(
            _isOverLimit
                ? '${_formatDuration(overage)} over limit ⚠️'
                : '${_formatDuration(limit - total)} remaining',
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progress > 1.0 ? 1.0 : _progress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          if (lastSyncedTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Updated: $lastSyncedTime',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Usage Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildKpiCard(Icons.timer, 'Longest Session', _formatDuration(longestSession), Colors.purple, 'without break'),
              _buildKpiCard(Icons.alarm, _viewMode == ViewMode.day ? 'First Pickup' : 'Earliest Pickup', firstPickupTime ?? '--:--', Colors.orange, _viewMode == ViewMode.day ? 'today' : 'this period'),
              if (_viewMode == ViewMode.day)
                _buildKpiCard(vsYesterdayPercent >= 0 ? Icons.trending_up : Icons.trending_down, 'vs Yesterday', '${vsYesterdayPercent.abs().toStringAsFixed(0)}%', vsYesterdayPercent >= 0 ? Colors.green : Colors.red, vsYesterdayPercent >= 0 ? 'more than yesterday' : 'less than yesterday')
              else
                _buildKpiCard(Icons.calendar_today, 'Active Days', '${data['daysWithData'] ?? 0}', Colors.teal, _viewMode == ViewMode.week ? 'of 7 days' : 'of 30 days'),
              _buildKpiCard(Icons.bar_chart, 'Daily Average', _formatDuration(weeklyAverage), Colors.indigo, 'last 7 days'),
              _buildKpiCard(
                  pointsImpact >= 0 ? Icons.add_circle : Icons.remove_circle,
                  pointsImpact >= 0 ? 'Points Earned' : 'Over Limit Penalty',
                  '${pointsImpact > 0 ? '+' : ''}$pointsImpact',
                  pointsImpact >= 0 ? Colors.green : Colors.red,
                  _pointsSubtext
              ),
              _buildKpiCard(Icons.bedtime, 'Bedtime Use', bedtimeUsage > 0 ? _formatDuration(bedtimeUsage) : 'None', bedtimeUsage > 0 ? Colors.red : Colors.green, '10pm-6am'),
              _buildKpiCard(Icons.local_fire_department, 'Learning Streak', '$learningStreak', Colors.amber.shade700, 'days with more edu than ent'),
              _buildKpiCard(Icons.category, 'Top Category', topCategory.split(' ').first, topCategory.contains('Educational') ? Colors.blue : topCategory.contains('Entertainment') ? Colors.orange : Colors.grey, 'most used type'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(IconData icon, String label, String value, Color color, String subtext) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                subtext,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContentBalance() {
    final edu = data['educationMinutes'] ?? 0;
    final ent = data['entertainmentMinutes'] ?? 0;
    final total = edu + ent;

    if (total == 0) return const SizedBox(height: 0);

    final eduRatio = total > 0 ? edu / total : 0.0;
    final entRatio = total > 0 ? ent / total : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Content Balance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            height: 32,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.grey.shade200),
            child: Row(
              children: [
                if (eduRatio > 0)
                  Flexible(
                    flex: (eduRatio * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.horizontal(left: const Radius.circular(16), right: entRatio == 0 ? const Radius.circular(16) : Radius.zero),
                      ),
                      alignment: Alignment.center,
                      child: eduRatio > 0.15 ? Text('${(eduRatio * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)) : null,
                    ),
                  ),
                if (entRatio > 0)
                  Flexible(
                    flex: (entRatio * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.shade500,
                        borderRadius: BorderRadius.horizontal(left: eduRatio == 0 ? const Radius.circular(16) : Radius.zero, right: const Radius.circular(16)),
                      ),
                      alignment: Alignment.center,
                      child: entRatio > 0.15 ? Text('${(entRatio * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)) : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildContentBalanceItem(Icons.school, Colors.blue, 'Educational', _formatDuration(edu), '${(eduRatio * 100).toInt()}%')),
              Expanded(child: _buildContentBalanceItem(Icons.videogame_asset, Colors.orange, 'Entertainment', _formatDuration(ent), '${(entRatio * 100).toInt()}%')),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Utility usage (settings, camera, etc.) not tracked automatically',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBalanceItem(IconData icon, Color color, String label, String value, String percent) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(percent, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildAutoTrackedAppsSection() {
    if (autoTrackedApps.isEmpty) return const SizedBox(height: 0);

    final top3 = autoTrackedApps.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android, color: Colors.green),
              const SizedBox(width: 8),
              const Text('Auto-Tracked Apps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('🤖', style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...top3.map((app) {
            final displayName = _cleanAppName(app['appName']);
            final mins = app['durationMinutes'] as int;
            final category = app['category'] as String;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                              Text(category.toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatDuration(mins), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildManualAppsSection() {
    final manualApps = <String, int>{};

    for (var entry in entries) {
      final appName = entry['appName'] as String? ?? 'Unknown';
      final minutes = (entry['durationMinutes'] as num?)?.toInt() ?? 0;

      if (appName.contains('.') && appName == appName.toLowerCase()) continue;

      manualApps[appName] = (manualApps[appName] ?? 0) + minutes;
    }

    if (manualApps.isEmpty) return const SizedBox(height: 0);

    final sorted = manualApps.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('Manually Logged Apps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('✏️', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...top3.map((app) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(app.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatDuration(app.value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInsightCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb, color: Colors.blue.shade600, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily Insight', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                const SizedBox(height: 4),
                Text(_getInsightMessage(), style: TextStyle(fontSize: 14, color: Colors.blue.shade900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInsightMessage() {
    final total = data['totalMinutes'] ?? 0;
    final limit = _viewMode == ViewMode.day ? (data['dailyLimit'] ?? 120) :
    _viewMode == ViewMode.week ? 840 : 3600;
    final edu = data['educationMinutes'] ?? 0;
    final ent = data['entertainmentMinutes'] ?? 0;

    if (_isOverLimit) {
      return "Over limit by ${_formatDuration(total - limit)}. Consider screen-free activities! 👟";
    } else if (edu > ent && edu > 0) {
      return "Great educational focus! Learning streak: $learningStreak days. 📚";
    } else if (total < limit * 0.5) {
      return "Excellent balance! Lots of offline time. ⭐";
    } else if (bedtimeUsage > 30) {
      return "Significant bedtime usage detected. 🌙";
    } else {
      return "Good job staying within limits! Consistency is key. 🎉";
    }
  }

  Future<void> _captureAndShareImage() async {
    setState(() => isExporting = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/report_${widget.childName ?? 'child'}_${_viewMode.name}.png');
        await file.writeAsBytes(buffer);

        await Share.shareXFiles(
          [XFile(file.path)],
          text: '${widget.childName ?? 'My child'}\'s $_periodLabel screen time report!',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing: $e')));
    } finally {
      setState(() => isExporting = false);
    }
  }

  Future<void> _exportPDF() async {
    setState(() => isExporting = true);
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${widget.childName ?? 'Child'} Screen Time Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text('$_periodLabel - ${DateFormat('MMM d, yyyy').format(DateTime.now())}'),
              pw.SizedBox(height: 20),
              pw.Text('Total Usage: ${_formatDuration(data['totalMinutes'] ?? 0)}'),
              pw.Text('Educational: ${_formatDuration(data['educationMinutes'] ?? 0)}'),
              pw.Text('Entertainment: ${_formatDuration(data['entertainmentMinutes'] ?? 0)}'),
              pw.Text('Points: ${pointsImpact > 0 ? '+' : ''}$pointsImpact (${_pointsSubtext})'),
            ],
          ),
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/report_${widget.childName ?? 'child'}_${_viewMode.name}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.childName ?? 'Child'}\'s $_periodLabel report',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isExporting = false);
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}