// lib/screens/child/goal_review_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoalReviewScreen extends StatefulWidget {
  const GoalReviewScreen({super.key});

  @override
  State<GoalReviewScreen> createState() => _GoalReviewScreenState();
}

class _GoalReviewScreenState extends State<GoalReviewScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  Map<String, dynamic>? _goal;
  String? _goalId;

  @override
  void initState() {
    super.initState();
    _loadPendingGoal();
  }

  Future<void> _loadPendingGoal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('goals')
          .where('childId', isEqualTo: user.uid)
          .limit(10)
          .get();

      final goals = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        return status == 'pending_child' || status == 'active';
      }).toList();

      goals.sort((a, b) {
        final aTime = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bTime = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      if (goals.isNotEmpty) {
        setState(() {
          _goal = goals.first.data() as Map<String, dynamic>;
          _goalId = goals.first.id;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _respondToGoal(bool agreed) async {
    if (_goalId == null) return;
    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final batch = FirebaseFirestore.instance.batch();

      final goalRef = FirebaseFirestore.instance.collection('goals').doc(_goalId);

      if (agreed) {
        batch.update(goalRef, {
          'status': 'active',
          'agreedByChild': true,
          'childSignedAt': Timestamp.now(),
        });

        final goalEndDate = _goal?['endDate'] as Timestamp?;
        final dueDate = goalEndDate ?? Timestamp.now();

        final tasks = _goal?['tasks'] as List<dynamic>? ?? [];
        for (var task in tasks) {
          final taskRef = FirebaseFirestore.instance.collection('tasks').doc();
          batch.set(taskRef, {
            'title': task['title'],
            'description': task['description'] ?? '',
            'points': task['points'],
            'assignedTo': user.uid,
            'createdBy': _goal?['parentId'],
            'goalId': _goalId,
            'status': 'pending',
            'dueDate': dueDate,
            'createdAt': Timestamp.now(),
          });
        }

        final rewards = _goal?['rewards'] as List<dynamic>? ?? [];
        for (var reward in rewards) {
          final rewardRef = FirebaseFirestore.instance.collection('rewards').doc();
          batch.set(rewardRef, {
            'title': reward['title'],
            'description': reward['description'] ?? '',
            'pointsCost': reward['pointsCost'],
            'createdBy': _goal?['parentId'],
            'childId': user.uid,
            'goalId': _goalId,
            'isAvailable': true,
            'createdAt': Timestamp.now(),
          });
        }
      } else {
        batch.update(goalRef, {
          'status': 'declined',
          'agreedByChild': false,
          'declinedAt': Timestamp.now(),
        });

        await FirebaseFirestore.instance.collection('notifications').add({
          'parentId': _goal?['parentId'],
          'childId': user.uid,
          'type': 'goal_declined',
          'goalId': _goalId,
          'message': 'Your child declined the goal "${_goal?['title'] ?? 'New Goal'}". Create a new goal?',
          'read': false,
          'createdAt': Timestamp.now(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(agreed ? '✅ Goal accepted! Tasks and rewards added.' : 'Goal declined. Parent notified.'),
            backgroundColor: agreed ? Colors.green : Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _formatShortDate(DateTime date) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[date.month]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_goal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Goal'), backgroundColor: const Color(0xFFF3E5F5)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('No Active Goal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Text('Ask your parent to set a goal!', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final isPending = _goal?['status'] == 'pending_child';
    final tasks = (_goal?['tasks'] as List<dynamic>?) ?? [];
    final rewards = (_goal?['rewards'] as List<dynamic>?) ?? [];
    final title = _goal?['title'] ?? 'New Goal';
    final description = _goal?['description'] ?? '';
    final limit = (_goal?['dailyScreenTimeLimit'] ?? 0) as int;

    final startDate = (_goal?['startDate'] as Timestamp?)?.toDate();
    final endDate = (_goal?['endDate'] as Timestamp?)?.toDate();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Goal'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 14),
                    ),
                  ],
                  if (startDate != null && endDate != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatShortDate(startDate)} — ${_formatShortDate(endDate)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (limit > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Screen Time: $limit min/day',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Tasks to Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...tasks.map((task) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Icon(Icons.check_circle_outline, color: Colors.blue.shade700),
                  ),
                  title: Text(task['title'] ?? 'Task'),
                  subtitle: Text('${task['points']} points'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/tasks'),
                ),
              );
            }),

            const SizedBox(height: 24),

            const Text('Rewards You Can Earn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...rewards.map((reward) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: Icon(Icons.card_giftcard, color: Colors.amber.shade800),
                  ),
                  title: Text(reward['title'] ?? 'Reward'),
                  subtitle: Text('${reward['pointsCost']} points'),
                ),
              );
            }),

            const SizedBox(height: 24),

            if (isPending) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : () => _respondToGoal(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Accept Goal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : () => _respondToGoal(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Goal active! Complete tasks to earn your rewards.',
                        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}