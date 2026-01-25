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

  @override
  void initState() {
    super.initState();
    _loadChildren();
    _loadRules();
  }

  Future<void> _loadChildren() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();

    setState(() {
      _children = snapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc['name'],
      }).toList();
    });
  }

  Future<void> _loadRules() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('deduction_rules')
        .where('childId', whereIn: _children.map((c) => c['id']).toList())
        .get();

    setState(() {
      _rules = snapshot.docs.map((doc) => DeductionRule.fromDoc(doc)).toList();
    });
  }

  Future<void> _createRule(DeductionRule rule) async {
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance.collection('deduction_rules').add(rule.toMap());
    await _loadRules();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deduction Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateRuleDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final rule = _rules[index];
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.remove_circle, color: Colors.red),
                    title: Text(rule.description),
                    subtitle: Text('${rule.pointsPerInterval} pts every ${rule.intervalMinutes} min\nChild: ${rule.childName}'),
                    trailing: Switch(
                      value: rule.isActive,
                      onChanged: (value) {
                        FirebaseFirestore.instance
                            .collection('deduction_rules')
                            .doc(rule.id)
                            .update({'isActive': value});
                        setState(() {
                          _rules[index] = DeductionRule(
                            id: rule.id,
                            childId: rule.childId,
                            childName: rule.childName,
                            type: rule.type,
                            pointsPerInterval: rule.pointsPerInterval,
                            intervalMinutes: rule.intervalMinutes,
                            isActive: value,
                            description: rule.description,
                          );
                        });
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showCreateRuleDialog() {
    String selectedChildId = _children.first['id'];
    DeductionRuleType selectedType = DeductionRuleType.screenTime;
    int points = 1;
    int interval = 60;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Deduction Rule'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedChildId,
                items: _children.map((child) {
                  return DropdownMenuItem<String>( // ✅ FIX: Add explicit type
                    value: child['id'],
                    child: Text(child['name']),
                  );
                }).toList(),
                onChanged: (value) => selectedChildId = value!,
                decoration: const InputDecoration(labelText: 'Select Child'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DeductionRuleType>(
                value: selectedType,
                items: DeductionRuleType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.toString().split('.').last),
                  );
                }).toList(),
                onChanged: (value) => selectedType = value!,
                decoration: const InputDecoration(labelText: 'Rule Type'),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Points per interval'),
                keyboardType: TextInputType.number,
                onChanged: (value) => points = int.tryParse(value) ?? 1,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Interval (minutes)'),
                keyboardType: TextInputType.number,
                onChanged: (value) => interval = int.tryParse(value) ?? 60,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final childName = _children.firstWhere((c) => c['id'] == selectedChildId)['name'];
              final rule = DeductionRule(
                id: '',
                childId: selectedChildId,
                childName: childName,
                type: selectedType,
                pointsPerInterval: points,
                intervalMinutes: interval,
                isActive: true,
                description: '${selectedType.toString().split('.').last}: $points pts every $interval min',
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