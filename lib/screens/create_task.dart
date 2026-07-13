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
  bool _requiresApproval = true;
  bool _requiresPhoto = false;
  TaskTemplate? _selectedTemplate;
  String? _familyId;

  @override
  void initState() {
    super.initState();
    _loadFamilyData();
  }

  Future<void> _loadFamilyData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      _familyId = userDoc.data()?['familyId'];
      await _loadChildren();
    } catch (e) {
      debugPrint('Error loading family: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChildren() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .get();
      
      setState(() {
        _children = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          // FIXED: Check multiple possible name fields
          final name = data['name'] ?? data['displayName'] ?? data['username'] ?? 'Unnamed Child';
          debugPrint('Loaded child: ${doc.id} with name: $name');
          return {
            'id': doc.id,
            'name': name,
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to load children: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onTemplateSelected(TaskTemplate? template) {
    if (template == null) return;
    setState(() {
      _selectedTemplate = template;
      _nameController.text = template.name;
      _pointsController.text = template.points.toString();
      _descriptionController.text = template.description;
      _requiresApproval = template.requiresApproval;
      _requiresPhoto = template.requiresPhoto;
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
          builder: (context, setDialogState) => SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _children.length,
              itemBuilder: (context, index) {
                final child = _children[index];
                final isSelected = _selectedChildIds.contains(child['id']);
                return CheckboxListTile(
                  title: Text(child['name'] as String),
                  value: isSelected,
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        _selectedChildIds.add(child['id'] as String);
                      } else {
                        _selectedChildIds.remove(child['id'] as String);
                      }
                    });
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Done')
          ),
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
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a due date')),
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
        final childData = _children.firstWhere((c) => c['id'] == childId);
        final childName = childData['name'] as String;
        
        final taskRef = FirebaseFirestore.instance.collection('tasks').doc();
        
        batch.set(taskRef, {
          'name': _nameController.text.trim(),
          'title': _nameController.text.trim(),
          'points': int.parse(_pointsController.text),
          'description': _descriptionController.text.trim(),
          'assignedTo': childId,
          'assignedToName': childName,
          'createdBy': user.uid,
          'familyId': _familyId,
          'status': 'assigned',
          'createdAt': FieldValue.serverTimestamp(),
          'dueDate': Timestamp.fromDate(_dueDate!),
          'requiresApproval': _requiresApproval,
          'requiresPhoto': _requiresPhoto,
        });
        taskCount++;
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Created $taskCount task${taskCount > 1 ? 's' : ''} successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error creating task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
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
                  // FIXED: Added isExpanded and changed item layout to prevent overflow
                  DropdownButtonFormField<TaskTemplate>(
                    decoration: const InputDecoration(
                      labelText: 'Quick Select Template (Optional)', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.flash_on)
                    ),
                    value: _selectedTemplate,
                    isExpanded: true, // FIXED: Prevents overflow
                    items: predefinedTasks.map((template) {
                      return DropdownMenuItem(
                        value: template, 
                        child: Text(
                          '${template.name} (${template.points} pts)',
                          overflow: TextOverflow.ellipsis, // FIXED: Truncate long names
                        )
                      );
                    }).toList(),
                    onChanged: _onTemplateSelected,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Task Name *', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.task)
                    ),
                    validator: (value) => value!.trim().isEmpty ? 'Required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _pointsController,
                    decoration: const InputDecoration(
                      labelText: 'Points *', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.star), 
                      suffixText: 'points'
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (int.tryParse(value) == null || int.parse(value) <= 0) {
                        return 'Enter valid number';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(_dueDate == null 
                      ? 'Select Due Date *' 
                      : 'Due Date: ${DateFormat('MMM dd, yyyy').format(_dueDate!)}'
                    ),
                    trailing: const Icon(Icons.arrow_drop_down),
                    tileColor: _dueDate == null ? Colors.red[50] : null,
                    onTap: _selectDueDate,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.description)
                    ),
                    maxLines: 3,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Require Parent Approval'),
                    subtitle: const Text('Child must request approval to complete'),
                    value: _requiresApproval,
                    onChanged: (value) => setState(() => _requiresApproval = value),
                  ),
                  
                  SwitchListTile(
                    title: const Text('Require Photo Confirmation'),
                    subtitle: const Text('Child must upload a photo as proof'),
                    value: _requiresPhoto,
                    onChanged: (value) => setState(() => _requiresPhoto = value),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Card(
                    color: _selectedChildIds.isEmpty ? Colors.orange[50] : null,
                    child: ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('Assign to Children *'),
                      subtitle: _selectedChildIds.isEmpty
                          ? const Text('No children selected', style: TextStyle(color: Colors.red))
                          : Text('${_selectedChildIds.length} child${_selectedChildIds.length > 1 ? 'ren' : ''} selected'),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: _showChildSelectionDialog,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _createTask,
                    icon: const Icon(Icons.add_task),
                    label: Text(_isLoading ? 'Creating...' : 'Create Tasks'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16), 
                      minimumSize: const Size(double.infinity, 50)
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}