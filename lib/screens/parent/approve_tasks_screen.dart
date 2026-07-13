// lib/screens/parent/approve_tasks_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApproveTasksScreen extends StatefulWidget {
  const ApproveTasksScreen({super.key});

  @override
  State<ApproveTasksScreen> createState() => _ApproveTasksScreenState();
}

class _ApproveTasksScreenState extends State<ApproveTasksScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(title: const Text('Approve Tasks'), elevation: 0),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tasks')
            .where('createdBy', isEqualTo: user.uid)
            .where('status', isEqualTo: 'pending_approval')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final tasks = snapshot.data!.docs;
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No tasks pending approval', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final data = task.data() as Map<String, dynamic>;
              return _buildTaskCard(task, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildTaskCard(DocumentSnapshot task, Map<String, dynamic> data) {
    final title = data['title'] ?? 'Untitled';
    final points = (data['points'] ?? 0) as int;
    final childName = data['assignedToName'] ?? 'Child';
    final photoUrl = data['verificationPhotoUrl'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('$points points • $childName', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text('PENDING', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            if (photoUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  photoUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 180,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _processTask(task, data, true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _processTask(task, data, false),
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('Reject', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processTask(DocumentSnapshot task, Map<String, dynamic> data, bool isApproved) async {
    final childId = data['assignedTo'] as String?;
    final points = (data['points'] ?? 0) as int;

    try {
      if (isApproved && childId != null) {
        await FirebaseFirestore.instance.collection('users').doc(childId).update({
          'currentPoints': FieldValue.increment(points),
          'totalPoints': FieldValue.increment(points),
        });
      }

      await task.reference.update({
        'status': isApproved ? 'approved' : 'rejected',
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser!.uid,
      });

      if (childId != null) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'childId': childId,
          'parentId': FirebaseAuth.instance.currentUser!.uid,
          'type': isApproved ? 'task_approved' : 'task_rejected',
          'title': isApproved ? 'Task Approved!' : 'Task Rejected',
          'message': isApproved
              ? 'Your task "${data['title']}" was approved! You earned $points points.'
              : 'Your task "${data['title']}" was rejected. Please try again.',
          'taskId': task.id,
          'points': isApproved ? points : 0,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isApproved ? '✅ Task approved' : '❌ Task rejected'),
            backgroundColor: isApproved ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}