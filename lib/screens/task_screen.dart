// lib/screens/task_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final String userId = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Tasks'),
          backgroundColor: const Color(0xFFF3E5F5),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.pending_actions), text: 'To Do'),
              Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTaskList(statusFilter: ['assigned', 'pending'], emptyMessage: 'No tasks assigned!'),
            _buildTaskList(statusFilter: ['completed', 'approved', 'rejected', 'pending_approval'], emptyMessage: 'No completed tasks yet'),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList({required List<String> statusFilter, required String emptyMessage}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .where('status', whereIn: statusFilter)
          .orderBy('dueDate', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final tasks = snapshot.data?.docs ?? [];
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: tasks.length,
          itemBuilder: (context, index) => TaskCard(task: tasks[index], userId: userId),
        );
      },
    );
  }
}

class TaskCard extends StatefulWidget {
  final DocumentSnapshot task;
  final String userId;
  const TaskCard({super.key, required this.task, required this.userId});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _isProcessing = false;
  String? _processingStep;

  Future<void> _completeTask() async {
    final taskData = widget.task.data() as Map<String, dynamic>;
    final bool requiresApproval = taskData['requiresApproval'] ?? true;
    final bool requiresPhoto = taskData['requiresPhoto'] ?? false;
    final int points = taskData['points'] ?? 0;

    setState(() {
      _isProcessing = true;
      _processingStep = 'Initializing...';
    });

    try {
      String? photoUrl;
      if (requiresPhoto) {
        setState(() => _processingStep = 'Checking camera permission...');
        final currentStatus = await Permission.camera.status;
        if (currentStatus.isDenied) {
          final permission = await Permission.camera.request();
          if (permission.isDenied) {
            throw Exception('Camera permission is required to complete this task.');
          }
        } else if (currentStatus.isPermanentlyDenied) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Camera Permission Required'),
              content: const Text('Camera permission is permanently denied. Please enable it in your device settings.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open Settings')),
              ],
            ),
          );
          if (shouldOpenSettings == true) await openAppSettings();
          setState(() { _isProcessing = false; _processingStep = null; });
          return;
        }

        setState(() => _processingStep = 'Opening camera...');
        final picker = ImagePicker();
        final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1024, maxHeight: 1024);
        if (photo == null) {
          setState(() { _isProcessing = false; _processingStep = null; });
          return;
        }

        final file = File(photo.path);
        final fileSizeMB = await file.length() / (1024 * 1024);
        if (fileSizeMB > 10) throw Exception('Photo is too large (${fileSizeMB.toStringAsFixed(1)} MB). Max size is 10 MB.');

        setState(() => _processingStep = 'Uploading photo...');
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('verification_photos')
            .child(widget.userId)
            .child('${widget.task.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final uploadTask = storageRef.putFile(
          file,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'taskId': widget.task.id, 'userId': widget.userId, 'timestamp': DateTime.now().toIso8601String()},
          ),
        );

        final snapshot = await uploadTask.timeout(
          const Duration(seconds: 30),
          onTimeout: () { uploadTask.cancel(); throw Exception('Upload timed out after 30 seconds.'); },
        );

        if (snapshot.state == TaskState.success) {
          photoUrl = await storageRef.getDownloadURL();
        } else {
          throw Exception('Upload failed with state: ${snapshot.state}');
        }
      }

      if (requiresApproval) {
        setState(() => _processingStep = 'Submitting for approval...');
        await widget.task.reference.update({
          'status': 'pending_approval',
          'completedAt': FieldValue.serverTimestamp(),
          'verificationPhotoUrl': photoUrl,
        });

        final goalId = taskData['goalId'] as String?;
        if (goalId != null) await _updateGoalProgress(goalId);

        // Notify parent
        final parentId = taskData['createdBy'] as String?;
        if (parentId != null) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'parentId': parentId,
            'childId': widget.userId,
            'type': 'task_approval',
            'title': 'Task Pending Approval',
            'message': '${taskData['title'] ?? 'A task'} completed by ${taskData['assignedToName'] ?? 'your child'}',
            'taskId': widget.task.id,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Task submitted for parent approval!'), backgroundColor: Colors.orange),
          );
        }
      } else {
        setState(() => _processingStep = 'Awarding points...');
        final batch = FirebaseFirestore.instance.batch();
        batch.update(widget.task.reference, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': 'auto',
          'verificationPhotoUrl': photoUrl,
          'pointsAwarded': points,
        });
        final childRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);
        batch.update(childRef, {'currentPoints': FieldValue.increment(points), 'totalPoints': FieldValue.increment(points)});
        final transRef = FirebaseFirestore.instance.collection('pointTransactions').doc();
        batch.set(transRef, {
          'childId': widget.userId,
          'type': 'task_completion',
          'points': points,
          'taskId': widget.task.id,
          'timestamp': FieldValue.serverTimestamp(),
          'description': 'Completed task: ${taskData['title']}',
        });
        await batch.commit();

        final goalId = taskData['goalId'] as String?;
        if (goalId != null) await _updateGoalProgress(goalId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🎉 Task completed! Earned $points points'), backgroundColor: Colors.green, duration: const Duration(seconds: 3)),
          );
        }
      }
    } catch (e, stackTrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStep = null; });
    }
  }

  Future<void> _updateGoalProgress(String goalId) async {
    try {
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where('goalId', isEqualTo: goalId)
          .where('status', whereIn: ['pending_approval', 'completed', 'approved'])
          .get();
      final completedCount = tasksSnapshot.docs.length;
      final goalDoc = await FirebaseFirestore.instance.collection('goals').doc(goalId).get();
      if (!goalDoc.exists) return;
      final totalTasks = (goalDoc.data()?['totalTasks'] ?? 0) as int;
      final progress = totalTasks > 0 ? (completedCount / totalTasks * 100).round() : 0;
      await FirebaseFirestore.instance.collection('goals').doc(goalId).update({
        'tasksCompleted': completedCount,
        'progressPercent': progress,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error updating goal progress: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
      case 'completed': return Colors.green;
      case 'pending_approval': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Colors.blue;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending_approval': return 'PENDING APPROVAL';
      case 'approved': return 'APPROVED';
      case 'completed': return 'COMPLETED (Auto)';
      case 'rejected': return 'REJECTED';
      case 'pending': return 'PENDING';
      default: return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.task.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'assigned';
    final title = data['title'] ?? 'Untitled Task';
    final points = data['points'] ?? 0;
    final bool requiresApproval = data['requiresApproval'] ?? true;
    final bool requiresPhoto = data['requiresPhoto'] ?? false;
    final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
    final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now()) && (status == 'assigned' || status == 'pending');
    final isGoalTask = data['goalId'] != null;
    final statusColor = _getStatusColor(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: isOverdue ? 4 : 1,
      color: isOverdue ? Colors.red[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  status == 'assigned' || status == 'pending' ? Icons.circle_outlined : Icons.check_circle,
                  color: statusColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 16, color: Colors.amber[700]),
                              const SizedBox(width: 4),
                              Text('$points points'),
                            ],
                          ),
                          if (isGoalTask)
                            Chip(
                              label: const Text('Goal Task', style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.teal[100],
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (!requiresApproval)
                            Chip(
                              label: const Text('Auto-approve', style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.green[100],
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (requiresPhoto)
                            Chip(
                              label: const Text('Photo required', style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.blue[100],
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (dueDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Due: ${_formatDate(dueDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOverdue ? Colors.red : Colors.grey[600],
                            fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (status == 'assigned' || status == 'pending') ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _completeTask,
                  icon: _isProcessing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(requiresPhoto ? Icons.camera_alt : Icons.check, size: 20),
                  label: Text(_isProcessing ? (_processingStep ?? 'Processing...') : requiresPhoto ? 'Complete & Take Photo' : 'Complete Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: requiresPhoto ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (_isProcessing && _processingStep != null) ...[
                const SizedBox(height: 4),
                Text(
                  _processingStep!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            if (status == 'rejected' && data['rejectionReason'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Feedback: ${data['rejectionReason']}', style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}