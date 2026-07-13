//this should be deleted, not in use. I was told to delete this. I am only using the one in widget.
// lib/widgets/daily_usage_summary.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/usage_sync_service.dart';

class DailyUsageSummary extends StatefulWidget {
  final String childId;
  final String? childName;
  final bool showHistory;

  const DailyUsageSummary({
    Key? key,
    required this.childId,
    this.childName,
    this.showHistory = false,
  }) : super(key: key);

  @override
  State<DailyUsageSummary> createState() => _DailyUsageSummaryState();
}

class _DailyUsageSummaryState extends State<DailyUsageSummary> {
  Map<String, dynamic> todayData = {};
  List<Map<String, dynamic>> historyData = [];
  bool isLoading = true;
  bool isRefreshing = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    
    try {
      // Load today
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      final today = await UsageSyncService.getUsageForDate(widget.childId, dateStr);
      if (today != null) {
        todayData = today;
      }

      // Load history if requested
      if (widget.showHistory) {
        historyData = await UsageSyncService.getLast7Days(widget.childId);
      }

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> refreshData() async {
    setState(() => isRefreshing = true);
    await loadData();
    setState(() => isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!widget.showHistory) {
      // Single day view
      final hasData = _hasRealData(todayData);
      
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: isRefreshing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
                onPressed: isRefreshing ? null : refreshData,
                tooltip: 'Refresh Data',
              ),
            ],
          ),
          if (hasData)
            _buildContent(todayData, isToday: true)
          else
            _buildEmptyState(),
        ],
      );
    } else {
      // History view (7 days)
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Last 7 Days',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: isRefreshing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
                onPressed: isRefreshing ? null : refreshData,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (historyData.isEmpty)
            _buildEmptyState()
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: historyData.length,
              itemBuilder: (context, index) {
                final day = historyData[index];
                return _buildDayCard(day);
              },
            ),
        ],
      );
    }
  }

  bool _hasRealData(Map<String, dynamic> d) {
    final totalMinutes = d['totalMinutes'] ?? 0;
    return (totalMinutes > 0);
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_off_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Usage Data',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            'Data will appear here once ${widget.childName ?? "your child"} uses their device and the app syncs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Check for Updates'),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final totalMinutes = day['totalMinutes'] ?? 0;
    final educationMinutes = day['educationMinutes'] ?? 0;
    final entertainmentMinutes = day['entertainmentMinutes'] ?? 0;
    final dateLabel = day['dateLabel'] ?? 'Unknown';
    final dailyLimit = day['dailyLimit'] ?? 120;
    
    final progress = totalMinutes > 0 ? (totalMinutes / dailyLimit).clamp(0.0, 1.0) : 0.0;
    final percentage = (progress * 100).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(progress),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$percentage%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$totalMinutes min total • $educationMinutes edu • $entertainmentMinutes ent'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(progress)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data, {bool isToday = true}) {
    final totalMinutes = data['totalMinutes'] ?? 0;
    final educationMinutes = data['educationMinutes'] ?? 0;
    final entertainmentMinutes = data['entertainmentMinutes'] ?? 0;
    final sessionCount = data['sessionCount'] ?? 0;
    final dailyLimit = data['dailyLimit'] ?? 120;
    
    final progress = totalMinutes > 0 ? (totalMinutes / dailyLimit).clamp(0.0, 1.0) : 0.0;
    final percentage = (progress * 100).toInt();
    
    final educationRatio = totalMinutes > 0 ? educationMinutes / totalMinutes : 0.0;
    final entertainmentRatio = totalMinutes > 0 ? entertainmentMinutes / totalMinutes : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Progress Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _getStatusColor(progress).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _getStatusColor(progress).withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$sessionCount sessions', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('Limit: ${dailyLimit}m', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(progress),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$percentage%',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(progress)),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text('$totalMinutes of $dailyLimit minutes used', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),

        // Content Balance
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.orange.shade50], begin: Alignment.topLeft, end: Alignment.topRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Content Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                height: 28,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.grey.shade200),
                child: Row(
                  children: [
                    if (educationRatio > 0)
                      Flexible(
                        flex: (educationRatio * 100).toInt().clamp(1, 100),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            borderRadius: BorderRadius.horizontal(left: const Radius.circular(14), right: educationRatio > 0.95 ? const Radius.circular(14) : Radius.zero),
                          ),
                          alignment: Alignment.center,
                          child: educationRatio > 0.15 ? Text('${(educationRatio * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)) : null,
                        ),
                      ),
                    if (entertainmentRatio > 0)
                      Flexible(
                        flex: (entertainmentRatio * 100).toInt().clamp(1, 100),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.shade500,
                            borderRadius: BorderRadius.horizontal(right: const Radius.circular(14), left: entertainmentRatio > 0.95 ? const Radius.circular(14) : Radius.zero),
                          ),
                          alignment: Alignment.center,
                          child: entertainmentRatio > 0.15 ? Text('${(entertainmentRatio * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)) : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatItem(icon: Icons.school, color: Colors.blue, label: 'Educational', value: '$educationMinutes min')),
                  Container(height: 40, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  Expanded(child: _buildStatItem(icon: Icons.videogame_asset, color: Colors.orange, label: 'Entertainment', value: '$entertainmentMinutes min')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({required IconData icon, required Color color, required String label, required String value}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(double progress) {
    if (progress < 0.5) return Colors.green;
    if (progress < 0.8) return Colors.orange;
    return Colors.red;
  }
}



//this should be deleted, not in use. I was told to delete this. I am only using the one in widget.