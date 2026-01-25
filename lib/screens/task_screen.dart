import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';

class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key});

  DateTime _getStartOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime _getEndOfWeek(DateTime date) {
    return _getStartOfWeek(date).add(const Duration(days: 6, hours: 23, minutes: 59));
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Tasks'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.today), text: 'Today'),
              Tab(icon: Icon(Icons.view_week), text: 'This Week'),
              Tab(icon: Icon(Icons.history), text: 'Overdue'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TODAY VIEW
            _buildTaskList(
              context,
              userId: userId,
              startDate: DateTime(now.year, now.month, now.day),
              endDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
              emptyMessage: 'No tasks due today!',
            ),
            
            // THIS WEEK VIEW
            _buildTaskList(
              context,
              userId: userId,
              startDate: _getStartOfWeek(now),
              endDate: _getEndOfWeek(now),
              emptyMessage: 'No tasks this week!',
            ),
            
            // OVERDUE VIEW
            _buildTaskList(
              context,
              userId: userId,
              startDate: DateTime(2000), // Far past
              endDate: DateTime(now.year, now.month, now.day - 1, 23, 59, 59),
              emptyMessage: 'No overdue tasks. Great job!',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, {required String userId, required DateTime startDate, required DateTime endDate, required String emptyMessage}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('dueDate')
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(emptyMessage),
              ],
            ),
          );
        }
        
        return ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            final data = task.data() as Map<String, dynamic>;
            return TaskCard(task: task, data: data);
          },
        );
      },
    );
  }
}

class TaskCard extends StatefulWidget {
  final DocumentSnapshot task;
  final Map<String, dynamic> data;

  const TaskCard({super.key, required this.task, required this.data});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _isCompleting = false;

  Future<void> _completeTask() async {
  setState(() => _isCompleting = true);
  
  try {
    final requiresPhoto = widget.data['requiresPhoto'] ?? false;
    String? photoUrl;
    
    if (requiresPhoto) {
      print("🎥 STEP 1: Requesting camera permission...");
      
      final permission = await Permission.camera.request();
      if (permission.isDenied) {
        print("❌ Camera permission DENIED");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission required!')),
        );
        setState(() => _isCompleting = false);
        return;
      }
      
      print("✅ Camera permission GRANTED");
      print("📷 STEP 2: Opening camera...");
      
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      
      if (photo == null) {
        print("❌ User cancelled camera");
        setState(() => _isCompleting = false);
        return;
      }
      
      print("✅ Photo captured: ${photo.path}");
      print("⬆️ STEP 3: Uploading to Firebase Storage...");
      
      final file = File(photo.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('verification_photos')
          .child('${widget.task.id}.jpg');
      
      // Add progress listener
      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        print("📈 Upload progress: ${progress.toStringAsFixed(1)}%");
      });
      
      await uploadTask;
      photoUrl = await storageRef.getDownloadURL();
      
      print("✅ STEP 4: Upload complete!");
      print("🔗 Download URL: $photoUrl");
    }
    
    print("🔄 STEP 5: Updating Firestore...");
    
    await widget.task.reference.update({
      'status': 'completed',
      'verificationPhotoUrl': photoUrl,
      'completedAt': FieldValue.serverTimestamp(),
    });
    
    print("✅ STEP 6: Task updated successfully!");
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Task completed!')),
    );
  } catch (e, stackTrace) {
    print("❌ ERROR at STEP: $e");
    print("📍 Stack trace: $stackTrace");
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Error: $e')),
    );
  }
  
  setState(() => _isCompleting = false);
}
  @override
  Widget build(BuildContext context) {
    final status = widget.data['status'] ?? 'pending';
    final dueDate = (widget.data['dueDate'] as Timestamp?)?.toDate();
    final isOverdue = dueDate?.isBefore(DateTime.now()) ?? false;
    final isToday = dueDate?.day == DateTime.now().day && dueDate?.month == DateTime.now().month && dueDate?.year == DateTime.now().year;
    
    return Card(
      margin: const EdgeInsets.all(8),
      color: isOverdue ? Colors.red[50] : null,
      child: ListTile(
        leading: _getStatusIcon(status),
        title: Row(
          children: [
            Expanded(child: Text(widget.data['title'])),
            if (isToday) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 10)),
                backgroundColor: Colors.orange,
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.data['points']} points'),
            if (dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Due: ${_formatDate(dueDate)}',
                style: TextStyle(
                  color: isOverdue ? Colors.red : Colors.grey,
                  fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
            if (status != 'pending' && widget.data['approvalReason'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Note: ${widget.data['approvalReason']}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ],
        ),
        trailing: status == 'pending'
            ? _isCompleting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _completeTask,
                    child: const Text('Complete'),
                  )
            : Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: status == 'approved' ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'completed':
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case 'rejected':
        return const Icon(Icons.cancel, color: Colors.red);
      default:
        return const Icon(Icons.circle_outlined);
    }
  }
}