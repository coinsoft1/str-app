import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/task_templates.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pointsController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime? _dueDate;
  List<Map<String, dynamic>> _children = [];
  List<String> _selectedChildIds = [];
  bool _isLoading = false;
  bool _requireApproval = true;
  bool _requirePhotoConfirmation = false;
  TaskTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to load children: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onTemplateSelected(TaskTemplate? template) {
    if (template == null) return;
    setState(() {
      _selectedTemplate = template;
      _nameController.text = template.name;
      _pointsController.text = template.points.toString();
      _descriptionController.text = template.description;
      _requireApproval = template.requiresApproval;
      _requirePhotoConfirmation = template.requiresPhoto;
    });
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _showChildSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Children'),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _children.length,
              itemBuilder: (context, index) {
                final child = _children[index];
                final isSelected = _selectedChildIds.contains(child['id']);
                return CheckboxListTile(
                  title: Text(child['name']),
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedChildIds.add(child['id']);
                      } else {
                        _selectedChildIds.remove(child['id']);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one child')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      int taskCount = 0;
      final batch = FirebaseFirestore.instance.batch();
      
      for (final childId in _selectedChildIds) {
        final childName = _children.firstWhere((c) => c['id'] == childId)['name'];
        
        final taskRef = FirebaseFirestore.instance.collection('tasks').doc();
        batch.set(taskRef, {
          'name': _nameController.text.trim(),
          'title': _nameController.text.trim(),
          'points': int.parse(_pointsController.text),
          'description': _descriptionController.text.trim(),
          'assignedTo': childId,
          'assignedToName': childName,
          'createdBy': user.uid,
          // FIXED: Set initial status to 'assigned'
          'status': 'assigned',
          'createdAt': FieldValue.serverTimestamp(),
          'dueDate': _dueDate,
          'requireApproval': _requireApproval,
          'requirePhotoConfirmation': _requirePhotoConfirmation,
        });
        taskCount++;
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Created $taskCount tasks successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Task')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<TaskTemplate>(
                    decoration: const InputDecoration(labelText: 'Quick Select Template (Optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.flash_on)),
                    value: _selectedTemplate,
                    items: predefinedTasks.map((template) {
                      return DropdownMenuItem(value: template, child: Text('${template.name} (${template.points} pts)'));
                    }).toList(),
                    onChanged: _onTemplateSelected,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Task Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.task)),
                    validator: (value) => value!.trim().isEmpty ? 'Required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _pointsController,
                    decoration: const InputDecoration(labelText: 'Points *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.star), suffixText: 'points'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (int.tryParse(value) == null || int.parse(value) <= 0) return 'Enter valid number';
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(_dueDate == null ? 'Select Due Date (Optional)' : 'Due Date: ${DateFormat('MMM dd, yyyy').format(_dueDate!)}'),
                    trailing: const Icon(Icons.arrow_drop_down),
                    onTap: _selectDueDate,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description)),
                    maxLines: 3,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Require Parent Approval'),
                    subtitle: const Text('Child must request approval to complete'),
                    value: _requireApproval,
                    onChanged: (value) => setState(() => _requireApproval = value),
                  ),
                  
                  SwitchListTile(
                    title: const Text('Require Photo Confirmation'),
                    subtitle: const Text('Child must upload a photo as proof'),
                    value: _requirePhotoConfirmation,
                    onChanged: (value) => setState(() => _requirePhotoConfirmation = value),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('Assign to Children *'),
                      subtitle: _selectedChildIds.isEmpty
                          ? const Text('No children selected', style: TextStyle(color: Colors.red))
                          : Text('${selectedChildNames.length} child${selectedChildNames.length > 1 ? 'ren' : ''} selected'),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: _showChildSelectionDialog,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  ElevatedButton.icon(
                    onPressed: _createTask,
                    icon: const Icon(Icons.add_task),
                    label: const Text('Create Tasks'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), minimumSize: const Size(double.infinity, 50)),
                  ),
                ],
              ),
            ),
    );
  }
  
  List<String> get selectedChildNames {
    return _selectedChildIds.map<String>((id) {
      return _children.firstWhere((c) => c['id'] == id)['name'] as String;
    }).toList();
  }
}