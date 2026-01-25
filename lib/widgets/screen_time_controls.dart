import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ai_service.dart';

class ParentScreenTimeControls extends StatefulWidget {
  final String childId;
  const ParentScreenTimeControls({super.key, required this.childId});

  @override
  State<ParentScreenTimeControls> createState() => _ParentScreenTimeControlsState();
}

class _ParentScreenTimeControlsState extends State<ParentScreenTimeControls> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _limitController = TextEditingController();
  final TextEditingController _deductionController = TextEditingController();
  bool _autoDeductEnabled = false;
  bool _isLoading = true;
  final AIService _aiService = AIService();
  String? _childName;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();
      
      final data = doc.data() ?? {};
      setState(() {
        _limitController.text = (data['dailyScreenTimeLimit'] ?? 120).toString();
        _deductionController.text = (data['deductionRate'] ?? 1).toString();
        _autoDeductEnabled = data['autoDeductEnabled'] ?? false;
        _childName = data['name'] ?? 'Child';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .update({
        'dailyScreenTimeLimit': int.parse(_limitController.text),
        'deductionRate': int.parse(_deductionController.text),
        'autoDeductEnabled': _autoDeductEnabled,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Settings saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _getAISuggestion() async {
    setState(() => _isLoading = true);
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();
      
      final suggestion = await _aiService.suggestScreenTimeLimit(
        childName: doc.data()?['name'] ?? 'Child',
        age: doc.data()?['age'] ?? 10,
      );
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI Suggestion'),
            content: SingleChildScrollView(child: Text(suggestion)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final regex = RegExp(r'(\d{2,3}) minutes');
                  final match = regex.firstMatch(suggestion);
                  if (match != null) {
                    setState(() => _limitController.text = match.group(1)!);
                  }
                  Navigator.pop(context);
                },
                child: const Text('Apply Suggestion'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('AI suggestion error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI error: $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer, color: Colors.blue, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Screen Time Rules${_childName != null ? " for $_childName" : ""}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.purple),
                  onPressed: _getAISuggestion,
                  tooltip: 'Get AI Suggestion',
                ),
              ],
            ),
            const Divider(height: 24),
            
            TextFormField(
              controller: _limitController,
              decoration: const InputDecoration(
                labelText: 'Daily Limit (minutes)',
                border: OutlineInputBorder(),
                suffixText: 'minutes',
                icon: Icon(Icons.timer_outlined),
                helperText: 'Recommended: 60-120 min for ages 6-12',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final value = int.tryParse(v);
                if (value == null || value < 10) return 'Minimum 10 minutes';
                if (value > 480) return 'Maximum 8 hours';
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _deductionController,
              decoration: const InputDecoration(
                labelText: 'Point Deduction Rate',
                border: OutlineInputBorder(),
                suffixText: 'points/minute over limit',
                icon: Icon(Icons.money_off),
                helperText: '1-5 points per minute is typical',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final value = int.tryParse(v);
                if (value == null || value < 0) return 'Must be positive';
                if (value > 10) return 'Too high (max 10)';
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            SwitchListTile(
              title: const Text('Enable Auto-Deduction'),
              subtitle: const Text(
                'Automatically deduct points every 5 minutes when limit exceeded',
                style: TextStyle(fontSize: 12),
              ),
              value: _autoDeductEnabled,
              activeColor: Colors.green,
              onChanged: (v) => setState(() => _autoDeductEnabled = v),
            ),
            const Divider(height: 32),
            
            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              '💡 Tap the sparkle icon to get AI-powered suggestions based on your child\'s age!',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _limitController.dispose();
    _deductionController.dispose();
    super.dispose();
  }
}