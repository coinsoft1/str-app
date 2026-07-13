// lib/screens/parent/goal_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoalCreationScreen extends StatefulWidget {
  final String? editGoalId;
  final Map<String, dynamic>? existingGoal;
  const GoalCreationScreen({super.key, this.editGoalId, this.existingGoal});

  @override
  State<GoalCreationScreen> createState() => _GoalCreationScreenState();
}

class _GoalCreationScreenState extends State<GoalCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _screenTimeLimitController = TextEditingController(text: '60');

  List<Map<String, dynamic>> _children = [];
  String? _selectedChildId;
  String _goalDuration = 'daily'; // daily, weekly, monthly
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _rewards = [];

  bool _isSubmitting = false;
  bool _isLoading = false;

  // NEW: Date fields
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _customEndDate = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
    if (widget.existingGoal != null) {
      _populateFromExisting(widget.existingGoal!);
    } else if (widget.editGoalId != null) {
      _loadGoalForEditing();
    } else {
      _calculateEndDate();
    }
  }

  Future<void> _loadChildren() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final familyId = userDoc.data()?['familyId'] as String?;
      if (familyId == null) return;
      final snap = await FirebaseFirestore.instance.collection('users').where('familyId', isEqualTo: familyId).where('role', isEqualTo: 'child').get();
      setState(() {
        _children = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
        if (_children.isNotEmpty && _selectedChildId == null) {
          _selectedChildId = _children.first['id'] as String;
        }
      });
    } catch (e) {
      debugPrint('Error loading children: $e');
    }
  }

  void _populateFromExisting(Map<String, dynamic> data) {
    _titleController.text = data['title'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _screenTimeLimitController.text = (data['dailyScreenTimeLimit'] ?? 60).toString();
    _selectedChildId = data['childId'] as String?;
    _goalDuration = data['duration'] ?? 'daily';

    // NEW: Parse dates
    final startTs = data['startDate'];
    if (startTs is Timestamp) {
      _startDate = startTs.toDate();
    }
    final endTs = data['endDate'];
    if (endTs is Timestamp) {
      _endDate = endTs.toDate();
      _customEndDate = true;
    } else {
      _calculateEndDate();
    }

    setState(() {
      _tasks = List<Map<String, dynamic>>.from(data['tasks'] ?? []);
      _rewards = List<Map<String, dynamic>>.from(data['rewards'] ?? []);
    });
  }

  Future<void> _loadGoalForEditing() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('goals').doc(widget.editGoalId).get();
      if (doc.exists) {
        _populateFromExisting(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Error loading goal: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // NEW: Auto-calculate end date from duration
  void _calculateEndDate() {
    switch (_goalDuration) {
      case 'daily':
        _endDate = _startDate.add(const Duration(days: 1));
        break;
      case 'weekly':
        _endDate = _startDate.add(const Duration(days: 7));
        break;
      case 'monthly':
        _endDate = _startDate.add(const Duration(days: 30));
        break;
      default:
        _endDate = _startDate.add(const Duration(days: 1));
    }
  }

  // NEW: Pick start date
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (!_customEndDate) _calculateEndDate();
      });
    }
  }

  // NEW: Pick / override end date
  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 1)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _customEndDate = true;
      });
    }
  }

  void _addTask() {
    setState(() {
      _tasks.add({'title': '', 'description': '', 'points': 10});
    });
  }

  void _addReward() {
    setState(() {
      _rewards.add({'title': '', 'description': '', 'pointsCost': 50});
    });
  }

  void _removeTask(int index) {
    setState(() => _tasks.removeAt(index));
  }

  void _removeReward(int index) {
    setState(() => _rewards.removeAt(index));
  }

  Future<void> _submitGoal() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a child for this goal'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one task'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_rewards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one reward'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final familyId = (userDoc.data()?['familyId'] ?? '') as String;

      final childData = _children.firstWhere((c) => c['id'] == _selectedChildId);
      final childName = childData['displayName'] as String? ?? childData['name'] as String? ?? childData['username'] as String? ?? 'Child';

      final goalData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'dailyScreenTimeLimit': int.parse(_screenTimeLimitController.text.trim()),
        'duration': _goalDuration,
        'childId': _selectedChildId,
        'childName': childName,
        'tasks': _tasks,
        'rewards': _rewards,
        'parentId': user.uid,
        'familyId': familyId,
        'startDate': Timestamp.fromDate(_startDate),
        'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final editId = widget.editGoalId ?? widget.existingGoal?['id'];

      if (editId != null) {
        await FirebaseFirestore.instance.collection('goals').doc(editId).update(goalData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Goal updated!'), backgroundColor: Colors.green),
          );
        }
      } else {
        goalData['status'] = 'pending_child';
        goalData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('goals').add(goalData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Goal created!'), backgroundColor: Colors.green),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text((widget.editGoalId != null || widget.existingGoal != null) ? 'Edit Goal' : 'Create Goal'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Child Selector
            if (_children.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Assign to Child',
                  prefixIcon: Icon(Icons.child_care),
                ),
                items: _children.map((child) {
                  final name = child['displayName'] as String? ?? child['name'] as String? ?? child['username'] as String? ?? 'Child';
                  return DropdownMenuItem(value: child['id'] as String, child: Text(name));
                }).toList(),
                onChanged: (value) => setState(() => _selectedChildId = value),
                validator: (v) => v == null ? 'Select a child' : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Goal Title',
                hintText: 'e.g., Weekly Learning Challenge',
                prefixIcon: Icon(Icons.flag),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this goal about?',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            // Goal Duration
            DropdownButtonFormField<String>(
              value: _goalDuration,
              decoration: const InputDecoration(
                labelText: 'Goal Duration',
                prefixIcon: Icon(Icons.calendar_today),
              ),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _goalDuration = value;
                    if (!_customEndDate) _calculateEndDate();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _screenTimeLimitController,
              decoration: const InputDecoration(
                labelText: 'Daily Screen Time Limit (minutes)',
                hintText: 'e.g., 60',
                prefixIcon: Icon(Icons.timer),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final n = int.tryParse(v);
                if (n == null || n < 1) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // NEW: Start Date Picker
            InkWell(
              onTap: _pickStartDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            '${_startDate.month}/${_startDate.day}/${_startDate.year}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // NEW: End Date (auto or custom)
            InkWell(
              onTap: _pickEndDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: _customEndDate ? Colors.purple : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('End Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            _endDate != null
                                ? '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}'
                                : 'Auto-calculated',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _customEndDate ? Colors.purple : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_customEndDate)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _customEndDate = false;
                            _calculateEndDate();
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                TextButton.icon(onPressed: _addTask, icon: const Icon(Icons.add), label: const Text('Add')),
              ],
            ),
            ..._tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final task = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(labelText: 'Task Title'),
                        controller: TextEditingController(text: task['title'] ?? '')..selection = TextSelection.collapsed(offset: (task['title'] ?? '').length),
                        onChanged: (v) => task['title'] = v,
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Description'),
                        controller: TextEditingController(text: task['description'] ?? '')..selection = TextSelection.collapsed(offset: (task['description'] ?? '').length),
                        onChanged: (v) => task['description'] = v,
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Points'),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: (task['points'] ?? 10).toString())..selection = TextSelection.collapsed(offset: (task['points'] ?? 10).toString().length),
                        onChanged: (v) => task['points'] = int.tryParse(v) ?? 10,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _removeTask(i),
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rewards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                TextButton.icon(onPressed: _addReward, icon: const Icon(Icons.add), label: const Text('Add')),
              ],
            ),
            ..._rewards.asMap().entries.map((entry) {
              final i = entry.key;
              final reward = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(labelText: 'Reward Title'),
                        controller: TextEditingController(text: reward['title'] ?? '')..selection = TextSelection.collapsed(offset: (reward['title'] ?? '').length),
                        onChanged: (v) => reward['title'] = v,
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Description'),
                        controller: TextEditingController(text: reward['description'] ?? '')..selection = TextSelection.collapsed(offset: (reward['description'] ?? '').length),
                        onChanged: (v) => reward['description'] = v,
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Points Cost'),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: (reward['pointsCost'] ?? 50).toString())..selection = TextSelection.collapsed(offset: (reward['pointsCost'] ?? 50).toString().length),
                        onChanged: (v) => reward['pointsCost'] = int.tryParse(v) ?? 50,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _removeReward(i),
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitGoal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text((widget.editGoalId != null || widget.existingGoal != null) ? 'Update Goal' : 'Create Goal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}