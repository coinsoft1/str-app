// lib/screens/parent/verification_queue_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/trust_ladder_service.dart';
import '../../services/settings_service.dart';

class VerificationQueueScreen extends StatefulWidget {
  const VerificationQueueScreen({super.key});

  @override
  State<VerificationQueueScreen> createState() => _VerificationQueueScreenState();
}

class _VerificationQueueScreenState extends State<VerificationQueueScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingLogs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPendingLogs();
  }

  Future<void> _loadPendingLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final logs = await TrustLadderService.getPendingLogs(user.uid);
      setState(() => _pendingLogs = logs);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approveAll() async {
    if (_pendingLogs.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve All Logs'),
        content: Text('Approve all ${_pendingLogs.length} pending logs? Children will receive ${SettingsService.instance.pointsPerVerify} points for each verified entry.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    int approved = 0;
    int failed = 0;
    final user = FirebaseAuth.instance.currentUser!;

    for (final log in _pendingLogs) {
      try {
        await TrustLadderService.verifyLog(
          childId: log['childId'] as String,
          parentId: user.uid,
          logId: log['id'] as String,
          action: 'verify',
          verifyPointsOverride: SettingsService.instance.pointsPerVerify,
        );
        approved++;
      } catch (e) {
        failed++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Approved $approved logs${failed > 0 ? ' ($failed failed)' : ''}'),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
        ),
      );
    }

    await _loadPendingLogs();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleAction(String logId, String childId, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (action == 'correct') {
      await _showCorrectDialog(logId, childId, user.uid);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await TrustLadderService.verifyLog(
        childId: childId,
        parentId: user.uid,
        logId: logId,
        action: action,
        verifyPointsOverride: action == 'verify' ? SettingsService.instance.pointsPerVerify : null,
      );

      if (mounted) {
        final message = action == 'verify'
            ? '✅ Verified! Child gets +${result['pointsAwarded']} points'
            : '❌ Rejected. Child notified to re-log.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: action == 'verify' ? Colors.green : Colors.red,
          ),
        );
      }

      await _loadPendingLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCorrectDialog(String logId, String childId, String parentId) async {
    final log = _pendingLogs.firstWhere((l) => l['id'] == logId);
    final currentDuration = (log['durationMinutes'] ?? 0) as int;
    final controller = TextEditingController(text: currentDuration.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App: ${log['appName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Current duration: $currentDuration minutes'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Corrected Duration (minutes)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final correctedDuration = int.tryParse(controller.text.trim()) ?? currentDuration;
    if (correctedDuration <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duration must be greater than 0')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await TrustLadderService.verifyLog(
        childId: childId,
        parentId: parentId,
        logId: logId,
        action: 'correct',
        correctedDuration: correctedDuration,
        correctPointsOverride: SettingsService.instance.pointsPerCorrect,
        parentNote: 'Duration corrected to $correctedDuration minutes',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Corrected. Child gets +${result['pointsAwarded']} points'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await _loadPendingLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Review Logs'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
        actions: [
          if (_pendingLogs.isNotEmpty)
            TextButton.icon(
              onPressed: _isLoading ? null : _approveAll,
              icon: const Icon(Icons.done_all, color: Colors.green),
              label: Text(
                'Approve All (${_pendingLogs.length})',
                style: const TextStyle(color: Colors.green),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPendingLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _pendingLogs.isEmpty
          ? _buildEmptyState()
          : _buildLogList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
          const SizedBox(height: 16),
          const Text(
            'All Caught Up!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending logs to review.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadPendingLogs,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingLogs.length,
      itemBuilder: (context, index) {
        final log = _pendingLogs[index];
        final childName = log['childName'] ?? 'Child';
        final appName = log['appName'] ?? 'Unknown';
        final category = log['category'] ?? 'Unknown';
        final duration = log['durationMinutes'] ?? 0;

        final startTimeRaw = log['startTime'];
        DateTime? startTime;
        if (startTimeRaw is Timestamp) {
          startTime = startTimeRaw.toDate();
        }
        final timeAgo = startTime != null
            ? DateFormat('MMM d, h:mm a').format(startTime)
            : 'Unknown time';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getCategoryColor(category).withOpacity(0.2),
                      child: Icon(_getCategoryIcon(category), color: _getCategoryColor(category)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$childName logged:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '$appName ($category)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$duration min • $timeAgo',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleAction(log['id'], log['childId'], 'verify'),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleAction(log['id'], log['childId'], 'correct'),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Correct'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleAction(log['id'], log['childId'], 'reject'),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'educational': return Colors.blue;
      case 'entertainment': return Colors.orange;
      case 'social': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'educational': return Icons.school;
      case 'entertainment': return Icons.videogame_asset;
      case 'social': return Icons.people;
      default: return Icons.devices;
    }
  }
}