import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/deduction_rule.dart';

class DeductionRulesScreen extends StatefulWidget {
  const DeductionRulesScreen({super.key});

  @override
  State<DeductionRulesScreen> createState() => _DeductionRulesScreenState();
}

class _DeductionRulesScreenState extends State<DeductionRulesScreen> {
  List<Map<String, dynamic>> _children = [];
  List<DeductionRule> _rules = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadChildren();
    if (_children.isNotEmpty) {
      await _loadRules();
    }
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
        _children = snapshot.docs.map((doc) => {
          'id': doc.id,
          'name': doc['name'] ?? 'Unnamed',
        }).toList();
      });
    } catch (e) {
      setState(() => _error = 'Error loading children: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRules() async {
    if (_children.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Query by parentId instead of using whereIn on childId
      final snapshot = await FirebaseFirestore.instance
          .collection('deduction_rules')
          .where('parentId', isEqualTo: user.uid)
          .get();

      // Filter locally for children belonging to this parent
      final childIds = _children.map((c) => c['id'] as String).toSet();
      
      setState(() {
        _rules = snapshot.docs
            .map((doc) => DeductionRule.fromDoc(doc))
            .where((rule) => childIds.contains(rule.childId))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rules: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createRule(DeductionRule rule) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('deduction_rules').add(rule.toMap());
      await _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rule created successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating rule: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleRule(String ruleId, bool value) async {
    try {
      await FirebaseFirestore.instance
          .collection('deduction_rules')
          .doc(ruleId)
          .update({'isActive': value});
      
      setState(() {
        final index = _rules.indexWhere((r) => r.id == ruleId);
        if (index != -1) {
          _rules[index] = DeductionRule(
            id: _rules[index].id,
            parentId: _rules[index].parentId,
            childId: _rules[index].childId,
            childName: _rules[index].childName,
            type: _rules[index].type,
            pointsPerInterval: _rules[index].pointsPerInterval,
            intervalMinutes: _rules[index].intervalMinutes,
            isActive: value,
            description: _rules[index].description,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating rule: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Screen Time Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _children.isEmpty ? null : () => _showCreateRuleDialog(),
          ),
        ],
      ),
      body: _isLoading && _rules.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _loadRules,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rules.length,
                    itemBuilder: (context, index) {
                      final rule = _rules[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.timer, color: Colors.red),
                          title: Text(rule.description),
                          subtitle: Text('${rule.pointsPerInterval} pts every ${rule.intervalMinutes} min\nChild: ${rule.childName}'),
                          trailing: Switch(
                            value: rule.isActive,
                            onChanged: (value) => _toggleRule(rule.id, value),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showCreateRuleDialog() {
    if (_children.isEmpty) return;
    
    String selectedChildId = _children.first['id'] as String;
    DeductionRuleType selectedType = DeductionRuleType.screenTime;
    int points = 1;
    int interval = 60;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Deduction Rule'),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedChildId,
                  items: _children.map((child) {
                    return DropdownMenuItem<String>(
                      value: child['id'] as String,
                      child: Text(child['name'] as String),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedChildId = value!),
                  decoration: const InputDecoration(labelText: 'Select Child', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DeductionRuleType>(
                  value: selectedType,
                  items: DeductionRuleType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedType = value!),
                  decoration: const InputDecoration(labelText: 'Rule Type', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(labelText: 'Points to deduct', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => points = int.tryParse(value) ?? 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(labelText: 'Interval (minutes)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => interval = int.tryParse(value) ?? 60,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final childName = _children.firstWhere((c) => c['id'] == selectedChildId)['name'] as String;
              final user = FirebaseAuth.instance.currentUser;
              
              if (user == null) return;
              
              final rule = DeductionRule(
                id: '',
                parentId: user.uid,
                childId: selectedChildId,
                childName: childName,
                type: selectedType,
                pointsPerInterval: points,
                intervalMinutes: interval,
                isActive: true,
                description: '${selectedType.name}: $points pts every $interval min',
              );
              _createRule(rule);
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}