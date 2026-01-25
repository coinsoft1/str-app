import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApproveTasksScreen extends StatelessWidget {
  const ApproveTasksScreen({super.key});

  Future<void> _showReasonDialog({
    required BuildContext context,
    required DocumentSnapshot task,
    required Map<String, dynamic> data,
    required bool isApproved,
  }) async {
    final reasonController = TextEditingController();

    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isApproved ? '✅ Approve Task' : '❌ Reject Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Task: ${data['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Points: ${data['points']}'),
            const SizedBox(height: 8),
            Text('Child: ${data['assignedToName'] ?? 'Unknown'}'),
            if (data['verificationPhotoUrl'] != null) ...[
              const SizedBox(height: 8),
              const Text('📸 Photo verification attached', style: TextStyle(color: Colors.blue)),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Great job! or Please try again...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _processTask(
                context: context,
                task: task,
                data: data,
                isApproved: isApproved,
                reason: reasonController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproved ? Colors.green : Colors.red,
            ),
            child: Text(isApproved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _processTask({
    required BuildContext context,
    required DocumentSnapshot task,
    required Map<String, dynamic> data,
    required bool isApproved,
    required String reason,
  }) async {
    try {
      final childId = data['assignedTo'];
      final points = data['points'] as int;
      final pointsChange = isApproved ? points : -points;

      // Update task status
      await task.reference.update({
        'status': isApproved ? 'approved' : 'rejected',
        if (reason.isNotEmpty) 'approvalReason': reason,
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser!.uid,
      });

      // Update child's points
      await FirebaseFirestore.instance.collection('users').doc(childId).update({
        'totalPoints': FieldValue.increment(pointsChange),
      });

      // Create notification for child
      final message = isApproved
          ? '✅ Task approved: ${data['title']}${reason.isNotEmpty ? ' - $reason' : ''}'
          : '❌ Task rejected: ${data['title']}${reason.isNotEmpty ? ' - $reason' : ''}';

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': childId,
        'message': message,
        'type': isApproved ? 'approval' : 'rejection',
        'pointsChange': pointsChange,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });

      // Show success message to parent
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Task ${isApproved ? 'approved' : 'rejected'}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tasks')
            .where('createdBy', isEqualTo: user.uid)
            .where('status', isEqualTo: 'completed')
            .snapshots(),
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
              child: Text('No tasks to approve'),
            );
          }

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final data = task.data() as Map<String, dynamic>;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  leading: const Icon(Icons.task, color: Colors.blue),
                  title: Row(
                    children: [
                      Expanded(child: Text(data['title'])),
                      Text('${data['points']} pts', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  subtitle: Text('Child: ${data['assignedToName'] ?? 'Unknown'}'),
                  children: [
                    // PHOTO VERIFICATION PREVIEW
                    if (data['verificationPhotoUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            data['verificationPhotoUrl']!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.broken_image, size: 48, color: Colors.grey);
                            },
                          ),
                        ),
                      ),
                    
                    // ACTION BUTTONS
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => _showReasonDialog(
                              context: context,
                              task: task,
                              data: data,
                              isApproved: true,
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cancel),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: () => _showReasonDialog(
                              context: context,
                              task: task,
                              data: data,
                              isApproved: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}