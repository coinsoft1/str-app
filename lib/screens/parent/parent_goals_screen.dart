// lib/screens/parent/parent_goals_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'goal_creation_screen.dart';

class ParentGoalsScreen extends StatefulWidget {
  const ParentGoalsScreen({super.key});

  @override
  State<ParentGoalsScreen> createState() => _ParentGoalsScreenState();
}

class _ParentGoalsScreenState extends State<ParentGoalsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _goals = [];
  List<Map<String, dynamic>> _children = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Get children
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .where('role', isEqualTo: 'child')
          .get();

      _children = childrenSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Get goals
      final goalsSnapshot = await FirebaseFirestore.instance
          .collection('goals')
          .where('parentId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      _goals = goalsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _getChildName(String childId) {
    final child = _children.firstWhere(
          (c) => c['id'] == childId,
      orElse: () => {'displayName': 'Child'},
    );
    return child['displayName'] ?? child['name'] ?? 'Child';
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending_child':
        return 'Pending Child';
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending_child':
        return Colors.orange;
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'declined':
        return Colors.red;
      case 'expired':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _deleteGoal(String goalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: const Text('This will remove the goal and all associated tasks/rewards. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete associated tasks
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where('goalId', isEqualTo: goalId)
          .get();
      for (var task in tasksSnapshot.docs) {
        await task.reference.delete();
      }

      // Delete associated rewards
      final rewardsSnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('goalId', isEqualTo: goalId)
          .get();
      for (var reward in rewardsSnapshot.docs) {
        await reward.reference.delete();
      }

      // Delete goal
      await FirebaseFirestore.instance.collection('goals').doc(goalId).delete();

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal deleted'), backgroundColor: Colors.green),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Manage Goals'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No goals yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GoalCreationScreen()),
              ).then((_) => _loadData()),
              icon: const Icon(Icons.add),
              label: const Text('Create Goal'),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _goals.length,
        itemBuilder: (context, index) {
          final goal = _goals[index];
          final goalId = goal['id'] as String;
          final title = goal['title'] ?? 'Goal';
          final status = goal['status'] ?? 'unknown';
          final childName = _getChildName(goal['childId'] ?? '');
          final period = goal['period'] ?? 'weekly';
          final progress = goal['progressPercent'] ?? 0;
          final tasksCompleted = goal['tasksCompleted'] ?? 0;
          final totalTasks = goal['totalTasks'] ?? 0;
          final endDate = (goal['endDate'] as Timestamp?)?.toDate();

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '$childName • ${period[0].toUpperCase() + period.substring(1)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getStatusColor(status)),
                        ),
                        child: Text(
                          _getStatusText(status),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (status == 'active') ...[
                    LinearProgressIndicator(
                      value: totalTasks > 0 ? tasksCompleted / totalTasks : 0,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$tasksCompleted / $totalTasks tasks completed ($progress%)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  if (endDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ends: ${DateFormat('MMM d, yyyy').format(endDate)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (status == 'pending_child' || status == 'declined')
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GoalCreationScreen(
                                  editGoalId: goalId,
                                  existingGoal: goal,
                                ),
                              ),
                            ).then((_) => _loadData()),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      if (status == 'active') ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _deleteGoal(goalId),
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            label: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GoalCreationScreen()),
        ).then((_) => _loadData()),
        child: const Icon(Icons.add),
      ),
    );
  }
}