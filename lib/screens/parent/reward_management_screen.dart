import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/reward_templates.dart';

class RewardManagementScreen extends StatefulWidget {
  const RewardManagementScreen({super.key});

  @override
  State<RewardManagementScreen> createState() => _RewardManagementScreenState();
}

class _RewardManagementScreenState extends State<RewardManagementScreen> {
  String? _familyId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _children = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final familyId = doc.data()?['familyId'];
    
    final childrenSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();
    
    setState(() {
      _familyId = familyId;
      _children = childrenSnapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        // FIXED: Check multiple possible name fields
        final name = data['name'] ?? data['displayName'] ?? data['username'] ?? 'Unnamed Child';
        return {
          'id': d.id,
          'name': name,
        };
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteReward(String rewardId, String rewardName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reward?'),
        content: Text('Delete "$rewardName"? This cannot be undone.'),
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
      await FirebaseFirestore.instance.collection('rewards').doc(rewardId).update({
        'isActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reward deleted'), backgroundColor: Colors.green),
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

  Future<void> _editReward(String rewardId, Map<String, dynamic> currentData) async {
    final nameController = TextEditingController(text: currentData['name'] ?? currentData['title'] ?? '');
    final pointController = TextEditingController(text: (currentData['pointCost'] ?? currentData['points'] ?? 0).toString());
    final descController = TextEditingController(text: currentData['description'] ?? '');
    String category = currentData['category'] ?? 'Screen Time';
    String? assignedChildId = currentData['assignedChild'];

    final categories = predefinedRewards.map((r) => r.category).toSet().toList();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Reward Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (val) => setDialogState(() => category = val!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointController,
                  decoration: const InputDecoration(labelText: 'Point Cost', border: OutlineInputBorder(), suffixText: 'points'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                if (_children.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    value: assignedChildId,
                    isExpanded: true, // FIXED: Prevent overflow
                    decoration: const InputDecoration(
                      labelText: 'Assign to Child (Optional)',
                      border: OutlineInputBorder(),
                      helperText: 'Leave empty for all children',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Children')),
                      ..._children.map((child) => DropdownMenuItem(
                        value: child['id'] as String, 
                        child: Text(child['name'] as String),
                      )),
                    ],
                    onChanged: (val) => setDialogState(() => assignedChildId = val),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('rewards').doc(rewardId).update({
                    'name': nameController.text,
                    'title': nameController.text,
                    'category': category,
                    'pointCost': int.tryParse(pointController.text) ?? 0,
                    'points': int.tryParse(pointController.text) ?? 0,
                    'description': descController.text,
                    'assignedChild': assignedChildId,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reward updated'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createReward() async {
    await showDialog(
      context: context,
      builder: (context) => const CreateRewardDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_familyId == null) return const Scaffold(body: Center(child: Text('No family found')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Rewards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createReward,
            tooltip: 'Create New Reward',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rewards')
            .where('familyId', isEqualTo: _familyId)
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var rewards = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isWheelOnly = data['isWheelOnly'] as bool? ?? false;
            final isSystemDefault = data['isSystemDefault'] as bool? ?? false;
            final isCustomWheelBonus = data['isCustomWheelBonus'] as bool? ?? false;
            return !isWheelOnly && !isSystemDefault && !isCustomWheelBonus;
          }).toList();
          
          rewards.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>? ?? {};
            final bData = b.data() as Map<String, dynamic>? ?? {};
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return -1;
            if (bTime == null) return 1;
            
            return bTime.compareTo(aTime);
          });
          
          if (rewards.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_giftcard, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No active rewards', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _createReward,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Reward'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: rewards.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final reward = rewards[index];
              final data = reward.data() as Map<String, dynamic>;
              final name = data['name'] ?? data['title'] ?? 'Unnamed';
              final cost = data['pointCost'] ?? data['points'] ?? 0;
              final assignedChild = data['assignedChild'];
              final category = data['category'] ?? 'General';
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple[100],
                    child: Text('$cost', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$category • $cost points'),
                      if ((data['description'] ?? '').isNotEmpty)
                        Text(
                          data['description'], 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      if (assignedChild != null)
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(assignedChild).get(),
                          builder: (context, childSnap) {
                            if (!childSnap.hasData) return const SizedBox();
                            final childData = childSnap.data!.data() as Map<String, dynamic>?;
                            final childName = childData?['name'] ?? childData?['displayName'] ?? 'Unknown';
                            return Text(
                              'Assigned to: $childName', 
                              style: const TextStyle(fontSize: 12, color: Colors.blue),
                            );
                          },
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editReward(reward.id, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteReward(reward.id, name),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createReward,
        tooltip: 'Create Reward',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateRewardDialog extends StatefulWidget {
  const CreateRewardDialog({super.key});

  @override
  State<CreateRewardDialog> createState() => _CreateRewardDialogState();
}

class _CreateRewardDialogState extends State<CreateRewardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pointCostController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCategory = 'Screen Time';
  String? _selectedChildId;
  List<Map<String, dynamic>> _children = [];
  List<String> _categories = [];
  bool _isLoading = false;
  String? _familyId;

  @override
  void initState() {
    super.initState();
    _categories = predefinedRewards.map((r) => r.category).toSet().toList();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    _familyId = userDoc.data()?['familyId'];
    
    final childrenSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();
    
    setState(() {
      _children = childrenSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // FIXED: Check multiple possible name fields
        final name = data['name'] ?? data['displayName'] ?? data['username'] ?? 'Unnamed Child';
        return {
          'id': doc.id,
          'name': name,
        };
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Reward'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RewardTemplate>(
                decoration: const InputDecoration(labelText: 'Quick Select (Optional)', border: OutlineInputBorder()),
                isExpanded: true, // FIXED: Prevent overflow
                items: predefinedRewards.map((template) {
                  return DropdownMenuItem(
                    value: template, 
                    child: Text(
                      '${template.name} (${template.pointCost} pts)',
                      overflow: TextOverflow.ellipsis,
                    )
                  );
                }).toList(),
                onChanged: (template) {
                  if (template != null) {
                    setState(() {
                      _nameController.text = template.name;
                      _selectedCategory = template.category;
                      _pointCostController.text = template.pointCost.toString();
                      _descriptionController.text = template.description;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Reward Name *', border: OutlineInputBorder()),
                validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (value) => setState(() => _selectedCategory = value!),
                validator: (value) => value == null ? 'Please select a category' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pointCostController,
                decoration: const InputDecoration(labelText: 'Point Cost *', border: OutlineInputBorder(), suffixText: 'points'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final cost = int.tryParse(value ?? '');
                  if (cost == null || cost <= 0) return 'Please enter valid points';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              if (_children.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: _selectedChildId,
                  isExpanded: true, // FIXED: Prevent overflow
                  decoration: const InputDecoration(
                    labelText: 'Assign to Child (Optional)',
                    border: OutlineInputBorder(),
                    helperText: 'Leave empty for all children',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Children')),
                    ..._children.map((child) => DropdownMenuItem(
                      value: child['id'], 
                      child: Text(child['name'])
                    )),
                  ],
                  onChanged: (value) => setState(() => _selectedChildId = value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isLoading ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            if (_familyId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Family ID not loaded'), backgroundColor: Colors.red),
              );
              return;
            }
            
            setState(() => _isLoading = true);
            
            try {
              final user = FirebaseAuth.instance.currentUser;
              await FirebaseFirestore.instance.collection('rewards').add({
                'name': _nameController.text.trim(),
                'title': _nameController.text.trim(),
                'category': _selectedCategory,
                'pointCost': int.parse(_pointCostController.text),
                'points': int.parse(_pointCostController.text),
                'description': _descriptionController.text.trim(),
                'createdBy': user!.uid,
                'familyId': _familyId,
                'assignedChild': _selectedChildId,
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
                'redeemedCount': 0,
                'isWheelOnly': false,
                'isSystemDefault': false,
                'isCustomWheelBonus': false,
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reward created'), backgroundColor: Colors.green),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
              );
            } finally {
              setState(() => _isLoading = false);
            }
          },
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pointCostController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}