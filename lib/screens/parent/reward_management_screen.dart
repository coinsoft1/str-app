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
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pointCostController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedCategory = 'Screen Time';
  String? _selectedChildId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _children = [];
  late final List<String> _categories;

  @override
  void initState() {
    super.initState();
    _categories = predefinedRewards.map((r) => r.category).toSet().toList();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .get();
      
      setState(() {
        _children = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Child',
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading children: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pointCostController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createReward() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final rewardData = {
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'pointCost': int.parse(_pointCostController.text),
        'description': _descriptionController.text.trim(),
        'createdBy': user.uid,
        'assignedChild': _selectedChildId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'redeemedCount': 0,
      };
      
      await FirebaseFirestore.instance.collection('rewards').add(rewardData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('Reward created successfully!')]),
            backgroundColor: Colors.green,
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Reward'), actions: [
        IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.pushNamed(context, '/reward_history')),
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<RewardTemplate>(
                    decoration: const InputDecoration(labelText: 'Quick Select (Optional)', border: OutlineInputBorder()),
                    items: predefinedRewards.map((template) {
                      return DropdownMenuItem(value: template, child: Text('${template.name} (${template.pointCost} pts)'));
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
                  
                  const SizedBox(height: 20),
                  
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Reward Name *', border: OutlineInputBorder()),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // ✅ FIXED: Use initialValue instead of value
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                    items: _categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedCategory = value!),
                    validator: (value) => value == null ? 'Please select a category' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
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
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  if (_children.isNotEmpty) ...[
                    // ✅ FIXED: Use initialValue instead of value
                    DropdownButtonFormField<String>(
                      initialValue: _selectedChildId,
                      decoration: const InputDecoration(
                        labelText: 'Assign to Child (Optional)',
                        border: OutlineInputBorder(),
                        helperText: 'Leave empty for all children',
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Children')),
                        ..._children.map((child) => DropdownMenuItem(value: child['id'], child: Text(child['name']))),
                      ],
                      onChanged: (value) => setState(() => _selectedChildId = value),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  const SizedBox(height: 20),
                  
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_card),
                    label: const Text('Create Reward'),
                    onPressed: _isLoading ? null : _createReward,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  ),
                ],
              ),
            ),
    );
  }
}