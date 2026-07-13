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
  String? _selectedChildId;
  Map<String, String> _childNames = {};
  List<Map<String, dynamic>> _availableRewards = [];
  List<String> _selectedRewardIds = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  List<Map<String, dynamic>> _children = [];

  Map<String, dynamic>? _familyData;
  String? _familyId;

  // NEW: Maps to link systemDefaultId <-> Firestore doc ID
  Map<String, String> _defaultBonusDocIds = {}; // sysId -> docId
  Map<String, String> _docIdToDefaultBonus = {}; // docId -> sysId

  final List<Map<String, dynamic>> _defaultBonuses = [
    {
      'id': 'sys_outdoor_play',
      'name': '30 Minutes Outdoor Play',
      'description': 'Time to run, bike, or play outside!',
      'icon': '🏃',
      'color': Colors.green,
    },
    {
      'id': 'sys_family_game',
      'name': 'Family Game Night (No Screens)',
      'description': 'Choose a board game for the whole family',
      'icon': '🎲',
      'color': Colors.orange,
    },
    {
      'id': 'sys_new_book',
      'name': 'Choose Any Book',
      'description': 'Pick a new book from the store or library',
      'icon': '📚',
      'color': Colors.blue,
    },
    {
      'id': 'sys_cooking_lesson',
      'name': 'Cooking Lesson with Parent',
      'description': 'Learn to cook a healthy recipe together',
      'icon': '👨‍🍳',
      'color': Colors.red,
    },
    {
      'id': 'sys_skip_chore',
      'name': 'Skip One Chore Today',
      'description': 'Take a break from one household task',
      'icon': '✨',
      'color': Colors.purple,
    },
  ];

  List<String> _selectedDefaultBonusIds = [];
  List<Map<String, dynamic>> _customBonuses = [];

  bool _isWheelEnabled = false;
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
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final parentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (parentDoc.exists) {
        _familyId = parentDoc.data()?['familyId'] as String?;

        if (_familyId != null) {
          final familyDoc = await FirebaseFirestore.instance
              .collection('families')
              .doc(_familyId)
              .get();
          if (familyDoc.exists) {
            _familyData = familyDoc.data();
          }
        }
      }

      // FIXED: Load children by familyId (consistent with rest of app)
      if (_familyId == null) {
        throw Exception('No family found. Please set up your family first.');
      }

      final childrenSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('familyId', isEqualTo: _familyId)
          .where('role', isEqualTo: 'child')
          .get();

      if (childrenSnapshot.docs.isEmpty) {
        throw Exception('No children found. Add children first.');
      }

      setState(() {
        _children = childrenSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? data['displayName'] ?? 'Unnamed Child',
          };
        }).toList();

        _childNames = {
          for (var child in _children) child['id'] as String: child['name'] as String
        };

        if (_selectedChildId == null && _children.isNotEmpty) {
          _selectedChildId = _children[0]['id'] as String;
        }
      });

      await _ensureDefaultBonusesExist();
      await _loadRewards();
      await _loadCustomBonuses();

      if (_selectedChildId != null) {
        await _loadExistingConfig();
      }
    } catch (e) {
      debugPrint('❌ Config load error: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // FIXED: Populate _defaultBonusDocIds and _docIdToDefaultBonus
  Future<void> _ensureDefaultBonusesExist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      bool needsBatch = false;

      for (final bonus in _defaultBonuses) {
        final existing = await FirebaseFirestore.instance
            .collection('rewards')
            .where('createdBy', isEqualTo: user.uid)
            .where('systemDefaultId', isEqualTo: bonus['id'])
            .limit(1)
            .get();

        if (existing.docs.isEmpty) {
          final docRef = FirebaseFirestore.instance.collection('rewards').doc();
          batch.set(docRef, {
            'name': bonus['name'],
            'description': bonus['description'],
            'pointCost': 0,
            'points': 0,
            'isBonus': true,
            'isWheelOnly': true,
            'isSystemDefault': true,
            'systemDefaultId': bonus['id'],
            'icon': bonus['icon'],
            'color': bonus['color'].value,
            'createdBy': user.uid,
            'familyId': _familyId,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
          needsBatch = true;
          _defaultBonusDocIds[bonus['id']] = docRef.id;
          _docIdToDefaultBonus[docRef.id] = bonus['id'];
          debugPrint('Creating default bonus: ${bonus['name']}');
        } else {
          final docId = existing.docs.first.id;
          _defaultBonusDocIds[bonus['id']] = docId;
          _docIdToDefaultBonus[docId] = bonus['id'];
          debugPrint('Found existing default bonus: ${bonus['name']} -> $docId');
        }
      }

      if (needsBatch) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error creating default bonuses: $e');
    }
  }

  Future<void> _loadRewards() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final rewardsSnapshot = await FirebaseFirestore.instance
          .collection('rewards')
          .where('createdBy', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .where('isSystemDefault', isEqualTo: false)
          .get();

      setState(() {
        _availableRewards = rewardsSnapshot.docs.map((doc) {
          final data = doc.data();
          final name = data['name'] ?? data['title'] ?? 'Unnamed Reward';
          final points = data['pointCost'] ?? data['points'] ?? 0;
          final isWheelOnly = data['isWheelOnly'] as bool? ?? false;

          return {
            'id': doc.id,
            'title': name,
            'name': name,
            'points': points,
            'isWheelOnly': isWheelOnly,
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading rewards: $e');
    }
  }

  Future<void> _loadCustomBonuses() async {
    if (_selectedChildId == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      Query query = FirebaseFirestore.instance
          .collection('rewards')
          .where('createdBy', isEqualTo: user.uid)
          .where('isWheelOnly', isEqualTo: true)
          .where('isSystemDefault', isEqualTo: false)
          .where('isCustomWheelBonus', isEqualTo: true);

      if (_selectedChildId == 'all') {
        query = query.where('appliesToAll', isEqualTo: true);
      } else {
        query = query.where('childId', isEqualTo: _selectedChildId);
      }

      final customSnapshot = await query.get();

      setState(() {
        _customBonuses = customSnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Custom Bonus',
            'description': data['description'] ?? '',
            'icon': data['icon'] ?? '🎁',
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading custom bonuses: $e');
    }
  }

  // FIXED: Map real doc IDs back to sysIds when loading config
  Future<void> _loadExistingConfig() async {
    if (_selectedChildId == null) return;

    try {
      String docId = _selectedChildId == 'all' ? '${_familyId}_all_children' : _selectedChildId!;

      final configDoc = await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(docId)
          .get();

      if (configDoc.exists && mounted) {
        final data = configDoc.data() as Map<String, dynamic>;
        setState(() {
          _isWheelEnabled = data['isEnabled'] as bool? ?? false;

          final allRewardIds = List<String>.from(data['rewardIds'] ?? []);
          _selectedRewardIds = [];
          _selectedDefaultBonusIds = [];

          for (final id in allRewardIds) {
            if (id.startsWith('sys_')) {
              // Legacy config
              _selectedDefaultBonusIds.add(id);
            } else if (_docIdToDefaultBonus.containsKey(id)) {
              // New config with real doc IDs
              _selectedDefaultBonusIds.add(_docIdToDefaultBonus[id]!);
            } else {
              _selectedRewardIds.add(id);
            }
          }

          final deadline = data['deadline']?.toDate();
          if (deadline != null) {
            _deadline = deadline;
            _deadlineController.text = DateFormat('yyyy-MM-dd HH:mm').format(_deadline);
          }
        });
      } else {
        setState(() {
          _isWheelEnabled = false;
          _selectedRewardIds = [];
          _selectedDefaultBonusIds = [];
        });
      }
    } catch (e) {
      debugPrint('Error loading config: $e');
    }
  }

  Future<void> _showCreateCustomBonusDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String selectedIcon = '🎁';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Custom Wheel Bonus'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create a special bonus that only appears on the wheel (costs 0 points)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Bonus Name *',
                  hintText: 'e.g., Ice Cream Treat',
                  border: OutlineInputBorder(),
                ),
                maxLength: 30,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g., Choose any ice cream flavor',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                maxLength: 100,
              ),
              const SizedBox(height: 12),
              const Text('Choose Icon:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['🎁', '🍦', '🎮', '🎬', '🍕', '🎯', '🏆', '🌟', '🎨', '⚽']
                    .map((icon) => InkWell(
                  onTap: () {
                    selectedIcon = icon;
                    Navigator.pop(context, {
                      'name': nameController.text,
                      'desc': descController.text,
                      'icon': selectedIcon,
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(icon, style: const TextStyle(fontSize: 24)),
                  ),
                ))
                    .toList(),
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
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }
              Navigator.pop(context, {
                'name': nameController.text.trim(),
                'desc': descController.text.trim(),
                'icon': selectedIcon,
              });
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result['name']!.isNotEmpty) {
      await _createCustomBonus(result['name']!, result['desc']!, result['icon']!);
    }
  }

  Future<void> _createCustomBonus(String name, String description, String icon) async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docData = {
        'name': name,
        'description': description.isEmpty ? 'Custom wheel bonus' : description,
        'pointCost': 0,
        'points': 0,
        'isBonus': true,
        'isWheelOnly': true,
        'isCustomWheelBonus': true,
        'isSystemDefault': false,
        'icon': icon,
        'createdBy': user.uid,
        'familyId': _familyId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (_selectedChildId == 'all') {
        docData['appliesToAll'] = true;
        docData['childId'] = 'all';
      } else {
        docData['childId'] = _selectedChildId;
      }

      final docRef = await FirebaseFirestore.instance.collection('rewards').add(docData);

      setState(() {
        _customBonuses.add({
          'id': docRef.id,
          'name': name,
          'description': description,
          'icon': icon,
        });
        _selectedRewardIds.add(docRef.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Custom bonus created and added to wheel')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDateTime() async {
    FocusScope.of(context).unfocus();

    final date = await showDatePicker(
      context: context,
      initialDate: _deadline.isAfter(DateTime.now()) ? _deadline : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );

    if (time == null || !mounted) return;

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
    if (_selectedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a child')),
      );
      return;
    }

    // FIXED: Map default bonus sysIds to real Firestore doc IDs
    final mappedDefaultIds = _selectedDefaultBonusIds
        .map((sysId) => _defaultBonusDocIds[sysId] ?? sysId)
        .toList();

    final allSelectedIds = [
      ..._selectedRewardIds,
      ...mappedDefaultIds,
    ];

    if (_isWheelEnabled && (allSelectedIds.length < 2 || allSelectedIds.length > 8)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select 2-8 items for the wheel (rewards + bonuses)')),
      );
      return;
    }

    if (_isWheelEnabled && _deadline.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deadline must be in the future'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final isAllChildren = _selectedChildId == 'all';
      final childName = isAllChildren ? 'All Children' : (_childNames[_selectedChildId] ?? 'Child');
      final docId = isAllChildren ? '${_familyId}_all_children' : _selectedChildId!;

      final saveData = {
        'childId': _selectedChildId,
        'childName': childName,
        'isEnabled': _isWheelEnabled,
        'parentId': FirebaseAuth.instance.currentUser!.uid,
        'lastUpdated': FieldValue.serverTimestamp(),
        'rewardIds': allSelectedIds,
        'defaultBonusIds': _selectedDefaultBonusIds,
        'appliesToAll': isAllChildren,
      };

      if (_isWheelEnabled) {
        saveData['deadline'] = Timestamp.fromDate(_deadline);
        saveData['hasBeenSpun'] = false;
        saveData['createdAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(docId)
          .set(saveData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isWheelEnabled
                ? '✅ Wheel configured for ${isAllChildren ? "ALL children" : childName} with ${allSelectedIds.length} rewards!'
                : '✅ Wheel disabled'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteConfiguration() async {
    if (_selectedChildId == null) return;

    final isAllChildren = _selectedChildId == 'all';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wheel Configuration?'),
        content: Text(isAllChildren
            ? 'This will remove the reward wheel for ALL children. Continue?'
            : 'This will remove the reward wheel for this child. Continue?'),
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
      final docId = isAllChildren ? '${_familyId}_all_children' : _selectedChildId!;

      await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(docId)
          .delete();

      Query query = FirebaseFirestore.instance
          .collection('rewards')
          .where('isCustomWheelBonus', isEqualTo: true);

      if (isAllChildren) {
        query = query.where('appliesToAll', isEqualTo: true);
      } else {
        query = query.where('childId', isEqualTo: _selectedChildId);
      }

      final customToDelete = await query.get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in customToDelete.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration deleted'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Reward Wheel'),
        actions: [
          if (_selectedChildId != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteConfiguration,
              tooltip: 'Delete configuration',
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
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
    final dropdownItems = [
      DropdownMenuItem<String>(
        value: 'all',
        child: Row(
          children: [
            Icon(Icons.people, color: Colors.blue[700]),
            const SizedBox(width: 8),
            const Text(
              'All Children',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      ..._children.map((child) {
        return DropdownMenuItem<String>(
          value: child['id'] as String,
          child: Row(
            children: [
              const Icon(Icons.person, color: Colors.grey),
              const SizedBox(width: 8),
              Text(child['name'] as String),
            ],
          ),
        );
      }).toList(),
    ];

    final bool isAllChildren = _selectedChildId == 'all';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Select Child *',
              border: const OutlineInputBorder(),
              prefixIcon: Icon(
                isAllChildren ? Icons.people : Icons.child_care,
                color: isAllChildren ? Colors.blue : Colors.grey,
              ),
            ),
            value: _selectedChildId,
            items: dropdownItems,
            onChanged: (value) async {
              setState(() {
                _selectedChildId = value;
                _isWheelEnabled = false;
                _selectedRewardIds = [];
                _selectedDefaultBonusIds = [];
                _customBonuses = [];
                _deadline = DateTime.now().add(const Duration(days: 7));
                _deadlineController.text = DateFormat('yyyy-MM-dd HH:mm').format(_deadline);
              });
              await _loadCustomBonuses();
              await _loadExistingConfig();
            },
            hint: const Text('Choose a child'),
          ),
        ),

        if (isAllChildren)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This configuration will apply to ALL children in your family',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isWheelEnabled ? Colors.green[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isWheelEnabled ? Colors.green : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.casino,
                    color: _isWheelEnabled ? Colors.green : Colors.grey,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reward Wheel',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _isWheelEnabled ? Colors.green[800] : Colors.grey[800],
                          ),
                        ),
                        Text(
                          _isWheelEnabled
                              ? 'Wheel is ENABLED - child can see and spin'
                              : 'Wheel is DISABLED - child cannot see it',
                          style: TextStyle(
                            color: _isWheelEnabled ? Colors.green[600] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isWheelEnabled,
                    onChanged: (value) => setState(() => _isWheelEnabled = value),
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ],
          ),
        ),

        if (_isWheelEnabled) ...[
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
                      'Spin Deadline *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _deadlineController,
                  readOnly: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.calendar_today, color: Colors.blue[700]),
                      onPressed: _selectDateTime,
                    ),
                  ),
                  onTap: _selectDateTime,
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.health_and_safety, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Healthy Default Bonuses',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Always free - promote healthy habits!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._defaultBonuses.map((bonus) {
                          final isSelected = _selectedDefaultBonusIds.contains(bonus['id']);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isSelected ? Colors.white : Colors.grey[100],
                            child: CheckboxListTile(
                              title: Row(
                                children: [
                                  Text(bonus['icon'], style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      bonus['name'],
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                bonus['description'],
                                style: TextStyle(fontSize: 12),
                              ),
                              value: isSelected,
                              activeColor: Colors.green,
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedDefaultBonusIds.add(bonus['id']);
                                  } else {
                                    _selectedDefaultBonusIds.remove(bonus['id']);
                                  }
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.add_circle, color: Colors.purple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your Custom Bonuses',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple[800],
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showCreateCustomBonusDialog,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  if (_customBonuses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No custom bonuses yet. Tap +Add to create special rewards!',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    )
                  else
                    ..._customBonuses.map((bonus) {
                      final isSelected = _selectedRewardIds.contains(bonus['id']);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        color: isSelected ? Colors.purple[50] : Colors.grey[50],
                        child: CheckboxListTile(
                          title: Row(
                            children: [
                              Text(bonus['icon'] ?? '🎁', style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(bonus['name'])),
                            ],
                          ),
                          subtitle: Text(bonus['description'] ?? 'Custom bonus',
                              style: TextStyle(fontSize: 12)),
                          value: isSelected,
                          activeColor: Colors.purple,
                          secondary: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('rewards')
                                  .doc(bonus['id'])
                                  .delete();
                              setState(() {
                                _customBonuses.removeWhere((b) => b['id'] == bonus['id']);
                                _selectedRewardIds.remove(bonus['id']);
                              });
                            },
                          ),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedRewardIds.add(bonus['id']);
                              } else {
                                _selectedRewardIds.remove(bonus['id']);
                              }
                            });
                          },
                        ),
                      );
                    }).toList(),

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Regular Rewards (${_selectedRewardIds.where((id) => !_customBonuses.any((b) => b['id'] == id)).length} selected)',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_availableRewards.where((r) => !(r['isWheelOnly'] as bool? ?? false)).isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        color: Colors.orange[50],
                        child: const ListTile(
                          leading: Icon(Icons.info, color: Colors.orange),
                          title: Text('No regular rewards'),
                          subtitle: Text('Create rewards in Reward Management to add them here'),
                        ),
                      ),
                    )
                  else
                    ..._availableRewards.where((r) => !(r['isWheelOnly'] as bool? ?? false)).map((reward) {
                      final isSelected = _selectedRewardIds.contains(reward['id']);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: CheckboxListTile(
                          title: Text(reward['title'] as String),
                          subtitle: Text('${reward['points']} points'),
                          secondary: Icon(Icons.star, color: Colors.amber[700]),
                          value: isSelected,
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                if (_selectedRewardIds.length + _selectedDefaultBonusIds.length < 8) {
                                  _selectedRewardIds.add(reward['id'] as String);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Maximum 8 items allowed on wheel')),
                                  );
                                }
                              } else {
                                _selectedRewardIds.remove(reward['id'] as String);
                              }
                            });
                          },
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],

        if (!_isWheelEnabled) const Expanded(child: SizedBox()),

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isWheelEnabled) ...[
                Text(
                  'Total: ${_selectedDefaultBonusIds.length} default + ${_selectedRewardIds.where((id) => _customBonuses.any((b) => b['id'] == id)).length} custom + ${_selectedRewardIds.where((id) => !_customBonuses.any((b) => b['id'] == id)).length} regular = ${_selectedDefaultBonusIds.length + _selectedRewardIds.length} items',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton.icon(
                onPressed: (_isSaving || _selectedChildId == null) ? null : _saveConfiguration,
                icon: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : Icon(_isWheelEnabled ? Icons.check_circle : Icons.block),
                label: Text(_isSaving
                    ? 'Saving...'
                    : _isWheelEnabled
                    ? (isAllChildren ? 'Save for All Children' : 'Save Wheel Configuration')
                    : 'Disable Wheel'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: _isWheelEnabled ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}