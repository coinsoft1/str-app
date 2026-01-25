import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  bool _isProcessing = false;

  Stream<QuerySnapshot> _getPendingTasks() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('tasks')
        .where('createdBy', isEqualTo: user!.uid)
        .where('status', isEqualTo: 'pending_approval')
        .snapshots();
  }

  Future<void> _approveTask(String taskId, Map<String, dynamic> task) async {
    setState(() => _isProcessing = true);
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      final taskRef = FirebaseFirestore.instance.collection('tasks').doc(taskId);
      final childRef = FirebaseFirestore.instance.collection('users').doc(task['assignedTo']);
      
      final points = task['points'] ?? 0;
      
      batch.update(taskRef, {
        'status': 'completed',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser!.uid,
      });
      
      batch.update(childRef, {
        'currentPoints': FieldValue.increment(points),
        'totalPoints': FieldValue.increment(points),
      });
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Approved: ${task['title']} (+$points pts)')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectTask(String taskId, Map<String, dynamic> task, String reason) async {
    setState(() => _isProcessing = true);
    
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': FirebaseAuth.instance.currentUser!.uid,
        'rejectionReason': reason,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Rejected: ${task['title']}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRejectDialog(String taskId, Map<String, dynamic> task) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Task'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectTask(taskId, task, controller.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Tasks'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getPendingTasks(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final tasks = snapshot.data!.docs;
          
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('No tasks pending approval', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index].data() as Map<String, dynamic>;
              final childName = task['assignedToName'] ?? 'Child';
              final points = task['points'] ?? 0;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['title'] ?? 'Task',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text('Child: $childName • $points points'),
                              ],
                            ),
                          ),
                          if (task['requirePhotoConfirmation'] == true)
                            const Icon(Icons.camera_alt, color: Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      if (task['description'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(task['description'], style: TextStyle(color: Colors.grey[600])),
                        ),
                      
                      if (task['verificationPhotoUrl'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Verification Photo:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Image.network(task['verificationPhotoUrl'], height: 100, fit: BoxFit.cover),
                            ],
                          ),
                        ),
                      
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () => _approveTask(tasks[index].id, task),
                              icon: _isProcessing ? const CircularProgressIndicator() : const Icon(Icons.check),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing ? null : () => _showRejectDialog(tasks[index].id, task),
                              icon: const Icon(Icons.close),
                              label: const Text('Reject'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
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
        },
      ),
    );
  }
}