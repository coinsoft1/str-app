import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class WheelConfigScreen extends StatefulWidget {
  const WheelConfigScreen({super.key});

  @override
  State<WheelConfigScreen> createState() => _WheelConfigScreenState();
}

class _WheelConfigScreenState extends State<WheelConfigScreen> {
  Map<String, dynamic>? _selectedChild;
  List<Map<String, dynamic>> _availableRewards = [];
  List<String> _selectedRewardIds = [];
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _children = [];
  
  bool _isWheelEnabled = true;
  DateTime _deadline = DateTime.now().add(const Duration(days: 7));
  final TextEditingController _deadlineController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deadlineController.text = DateFormat('yyyy-MM-dd HH:mm').format(_deadline);
    _loadData();
  }

  @override
  void dispose() {
    _deadlineController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // Load children
      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        throw Exception('No children found. Add children first.');
      }

      setState(() {
        _children = childrenSnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unnamed Child',
          };
        }).toList();
      });

      // Load rewards with PROPER error handling
      final rewardsSnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('createdBy', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .get();

      if (rewardsSnapshot.docs.isEmpty) {
        throw Exception('No rewards found. Create rewards in Reward Management first.');
      }

      setState(() {
        _availableRewards = rewardsSnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          // ✅ CRITICAL: Ensure fields exist
          if (data['title'] == null) {
            debugPrint('⚠️ Reward ${doc.id} missing title field: $data');
          }
          if (data['points'] == null) {
            debugPrint('⚠️ Reward ${doc.id} missing points field: $data');
          }
          return {
            'id': doc.id,
            'title': data['title'] ?? 'Unnamed Reward',
            'points': data['points'] ?? 0,
            'familyId': data['familyId'], // Store for verification
          };
        }).toList();
      });

      if (_selectedChild != null) {
        await _loadExistingConfig();
      }
    } catch (e) {
      debugPrint('❌ Config load error: $e');
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingConfig() async {
    if (_selectedChild == null) return;

    final configDoc = await FirebaseFirestore.instance
        .collection('wheelConfigurations')
        .doc(_selectedChild!['id'])
        .get();

    if (configDoc.exists) {
      setState(() {
        _selectedRewardIds = List<String>.from(configDoc.data()?['rewardIds'] ?? []);
        _isWheelEnabled = configDoc.data()?['isEnabled'] ?? true;
        final deadline = configDoc.data()?['deadline']?.toDate();
        if (deadline != null) {
          _deadline = deadline;
          _deadlineController.text = DateFormat('yyyy-MM-dd HH:mm').format(_deadline);
        }
      });
    }
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (date == null) return;
    
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    
    if (time == null) return;
    
    setState(() {
      _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _deadlineController.text = DateFormat('yyyy-MM-dd HH:mm').format(_deadline);
    });
  }

  Future<void> _saveConfiguration() async {
    if (_selectedChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a child')),
      );
      return;
    }

    if (_selectedRewardIds.length < 2 || _selectedRewardIds.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select 2-5 rewards for the wheel')),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // ✅ CRITICAL: Delete old wheel rewards
      final oldRewards = await FirebaseFirestore.instance
          .collection('wheelRewards')
          .where('parentId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where('assignedTo', arrayContains: _selectedChild!['id'])
          .get();
      
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in oldRewards.docs) {
        batch.delete(doc.reference);
      }

      // ✅ CRITICAL: Create NEW wheel rewards with FULL data
      for (String rewardId in _selectedRewardIds) {
        final reward = _availableRewards.firstWhere((r) => r['id'] == rewardId);
        final wheelRewardRef = FirebaseFirestore.instance.collection('wheelRewards').doc();
        
        batch.set(wheelRewardRef, {
          'title': reward['title'],
          'points': reward['points'],
          'parentId': FirebaseAuth.instance.currentUser!.uid,
          'assignedTo': [_selectedChild!['id']],
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Save configuration
      await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(_selectedChild!['id'])
          .set({
        'childId': _selectedChild!['id'],
        'childName': _selectedChild!['name'],
        'rewardIds': _selectedRewardIds,
        'isEnabled': _isWheelEnabled,
        'deadline': _deadline,
        'parentId': FirebaseAuth.instance.currentUser!.uid,
        'lastUpdated': FieldValue.serverTimestamp(),
        'maxSpinsPerDay': 1,
      }, SetOptions(merge: true));

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Wheel configured successfully!')),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Reward Wheel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildConfigurationUI(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[700]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Child Selection
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<Map<String, dynamic>>(
            decoration: const InputDecoration(
              labelText: 'Select Child',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.child_care),
            ),
            value: _selectedChild,
            items: _children.map((child) {
              return DropdownMenuItem(
                value: child,
                child: Text(child['name']!),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedChild = value;
              });
              _loadExistingConfig();
            },
            validator: (value) => value == null ? 'Required' : null,
          ),
        ),

        // TOGGLE: Enable/Disable Wheel
        SwitchListTile(
          title: const Text('Enable Wheel Spin'),
          subtitle: const Text('Allow child to spin the wheel'),
          value: _isWheelEnabled,
          onChanged: (value) {
            setState(() => _isWheelEnabled = value);
          },
        ),

        const Divider(),

        // Reward Selection Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.card_giftcard, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'Select Rewards (${_selectedRewardIds.length}/5)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Choose 2-5 rewards for the wheel',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),

        // Rewards List
        Expanded(
          child: ListView.builder(
            itemCount: _availableRewards.length,
            itemBuilder: (context, index) {
              final reward = _availableRewards[index];
              final isSelected = _selectedRewardIds.contains(reward['id']);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: CheckboxListTile(
                  title: Text(reward['title']!),
                  subtitle: Text('${reward['points']} points'),
                  secondary: Icon(Icons.star, color: Colors.amber[700]),
                  value: isSelected,
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        if (_selectedRewardIds.length < 5) {
                          _selectedRewardIds.add(reward['id']!);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Maximum 5 rewards allowed')),
                          );
                        }
                      } else {
                        _selectedRewardIds.remove(reward['id']!);
                      }
                    });
                  },
                ),
              );
            },
          ),
        ),

        // DEADLINE DATE/TIME PICKER
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Spin Deadline',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _deadlineController,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.calendar_today, color: Colors.blue[700]),
                    onPressed: _selectDateTime,
                  ),
                ),
                onTap: _selectDateTime,
              ),
              const SizedBox(height: 4),
              Text(
                'Child can spin until this date/time',
                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
              ),
            ],
          ),
        ),

        // Save Button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _saveConfiguration,
            icon: const Icon(Icons.save),
            label: const Text('Save Wheel Configuration'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.purple,
            ),
          ),
        ),
      ],
    );
  }
}