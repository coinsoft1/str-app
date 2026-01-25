import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'create_task.dart';
import 'ai_bot_screen.dart';
import 'parent/reward_management_screen.dart';
import 'parent/admin_review_screen.dart';
import '../widgets/screen_time_controls.dart';
import '../services/ai_service.dart';
import 'parent/wheel_config_screen.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  late Stream<DocumentSnapshot> _familyStream;
  late Stream<QuerySnapshot> _pendingTasksStream;

  @override
  void initState() {
    super.initState();
    _initializeStreams();
    _checkAndRepairFamilyData();
  }

  void _initializeStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _handleAuthError();
      return;
    }

    _familyStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    _pendingTasksStream = FirebaseFirestore.instance
        .collection('tasks')
        .where('createdBy', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending_approval')
        .snapshots();
  }

  Future<void> _checkAndRepairFamilyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isLoading.value = true;
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final userData = userDoc.data() ?? {};
      String? familyId = userData['familyId'];

      if (familyId == null) {
        await _createFamilyForUser(user.uid);
      } else {
        final familyDoc = await FirebaseFirestore.instance
            .collection('families')
            .doc(familyId)
            .get();
        
        if (!familyDoc.exists) {
          await _createFamilyForUser(user.uid);
        } else {
          final members = List.from(familyDoc.data()?['members'] ?? []);
          if (!members.contains(user.uid)) {
            await familyDoc.reference.update({
              'members': FieldValue.arrayUnion([user.uid])
            });
          }
        }
      }

      await _repairParentChildLinks(user.uid, userData['familyId']);
    } catch (e) {
      debugPrint('Error in data repair: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _repairParentChildLinks(String parentId, String? familyId) async {
    final children = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: parentId)
        .get();

    if (children.docs.isEmpty && familyId != null) {
      final familyChildren = await FirebaseFirestore.instance
          .collection('users')
          .where('familyId', isEqualTo: familyId)
          .where('role', isEqualTo: 'child')
          .get();
      
      if (familyChildren.docs.isNotEmpty) {
        for (var child in familyChildren.docs) {
          await child.reference.update({'parentId': parentId});
        }
      }
    }
  }

  Future<void> _createFamilyForUser(String userId) async {
    final familyRef = FirebaseFirestore.instance.collection('families').doc();
    final familyCode = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    
    await familyRef.set({
      'familyCode': familyCode,
      'createdBy': userId,
      'members': [userId],
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'familyId': familyRef.id,
      'role': 'parent',
    });
  }

  void _handleAuthError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    });
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _isLoading.value = true;
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _copyFamilyCode(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied: $code'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy failed: $e')),
      );
    }
  }

  Future<void> _showScreenTimeControls() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final children = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();

    if (children.docs.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No children found'), backgroundColor: Colors.red),
      );
      return;
    }

    if (children.docs.length == 1) {
      _openScreenTimeDialog(children.docs.first.id);
      return;
    }

    final options = <Widget>[
      SimpleDialogOption(
        onPressed: () {
          Navigator.pop(context);
          _openMultiChildScreenTimeDialog(children.docs);
        },
        child: ListTile(
          leading: const Icon(Icons.people, color: Colors.blue),
          title: const Text('All Children'),
          subtitle: Text('Apply to ${children.docs.length} children'),
        ),
      ),
      const Divider(),
    ];

    for (var child in children.docs) {
      final data = child.data() as Map<String, dynamic>;
      final name = data['name'] as String?;
      options.add(
        SimpleDialogOption(
          onPressed: () {
            Navigator.pop(context);
            _openScreenTimeDialog(child.id);
          },
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              child: Text(name?.isNotEmpty == true ? name!.substring(0, 1) : 'C', 
                         style: const TextStyle(color: Colors.white)),
            ),
            title: Text(name ?? 'Child'),
          ),
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select Child'),
          children: options,
        );
      },
    );
  }

  void _openScreenTimeDialog(String childId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ParentScreenTimeControls(childId: childId),
      ),
    );
  }

  Future<void> _openMultiChildScreenTimeDialog(List<QueryDocumentSnapshot> children) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply to All Children'),
        content: const Text('This will apply the same screen time rules to all children.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showMultiChildSettingsDialog(children);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMultiChildSettingsDialog(List<QueryDocumentSnapshot> children) async {
    showDialog(
      context: context,
      builder: (context) => _MultiChildScreenTimeEditor(children: children),
    );
  }

  Future<void> _handleNavigation(Widget screen) async {
    _isLoading.value = true;
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen))
          .then((_) => _isLoading.value = false);
    }
  }

  Widget _buildFamilyCodeCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _familyStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) return _buildErrorCard('Error loading family code');
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final familyId = userData?['familyId'];
        if (familyId == null) return _buildErrorCard('Family not found');

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('families').doc(familyId).snapshots(),
          builder: (context, familySnapshot) {
            if (familySnapshot.hasError) return _buildErrorCard('Error loading family details');
            
            final familyData = familySnapshot.data?.data() as Map<String, dynamic>?;
            final familyCode = familyData?['familyCode'] ?? 'ERROR';
            final memberCount = (familyData?['members'] as List?)?.length ?? 1;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue[50],
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.qr_code, color: Colors.blue, size: 32),
                title: const Text('Family Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text('Share with child: $familyCode\n$memberCount member${memberCount > 1 ? 's' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, color: Colors.blue),
                  onPressed: () => _copyFamilyCode(familyCode),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingTasksCount() {
    return StreamBuilder<QuerySnapshot>(
      stream: _pendingTasksStream,
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        );
      },
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.red[50],
      child: ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: Text(message, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, loading, child) {
        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Parent Dashboard'),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: _handleLogout,
                    tooltip: 'Logout',
                  ),
                ],
              ),
              body: RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _buildFamilyCodeCard(),
                    const SizedBox(height: 16),
                    _buildActionCard(
                      icon: Icons.check_circle,
                      color: Colors.green,
                      title: 'Approve Completed Tasks',
                      subtitle: 'Review pending tasks',
                      onTap: () => _handleNavigation(const AdminReviewScreen()),
                      trailing: _buildPendingTasksCount(),
                    ),
                    _buildActionCard(
                      icon: Icons.checklist,
                      color: Colors.blue,
                      title: 'Manage Tasks',
                      subtitle: 'Create and edit tasks',
                      onTap: () => _handleNavigation(const CreateTaskScreen()),
                    ),
                    _buildActionCard(
                      icon: Icons.card_giftcard,
                      color: Colors.orange,
                      title: 'Manage Rewards',
                      subtitle: 'Create reward options',
                      onTap: () => _handleNavigation(const RewardManagementScreen()),
                    ),
                    _buildActionCard(
                      icon: Icons.smart_toy,
                      color: Colors.purple,
                      title: 'AI Negotiation Bot',
                      subtitle: 'Chat with AI',
                      onTap: () => _handleNavigation(const AIBotScreen()),
                    ),
                    _buildActionCard(
                      icon: Icons.timer,
                      color: Colors.red,
                      title: 'Manage Screen Time Rules',
                      subtitle: 'Set limits & auto-deduct',
                      onTap: _showScreenTimeControls,
                    ),
                    _buildActionCard(
                      icon: Icons.casino,
                      color: Colors.purple,
                      title: 'Configure Reward Wheel',
                      subtitle: 'Set up spin-the-wheel rewards',
                      onTap: () => _handleNavigation(const WheelConfigScreen()),
                    ),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _handleNavigation(const CreateTaskScreen()),
                tooltip: 'Create Task',
                child: const Icon(Icons.add),
              ),
            ),
            if (loading)
              Container(
                color: Colors.black.withOpacity(0.1),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }
}

class _MultiChildScreenTimeEditor extends StatefulWidget {
  final List<QueryDocumentSnapshot> children;

  const _MultiChildScreenTimeEditor({required this.children});

  @override
  State<_MultiChildScreenTimeEditor> createState() => _MultiChildScreenTimeEditorState();
}

class _MultiChildScreenTimeEditorState extends State<_MultiChildScreenTimeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _limitController = TextEditingController(text: '120');
  final _deductionController = TextEditingController(text: '1');
  bool _autoDeductEnabled = false;
  bool _isLoading = false;

  Future<void> _saveToAll() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      
      for (var childDoc in widget.children) {
        batch.update(childDoc.reference, {
          'dailyScreenTimeLimit': int.parse(_limitController.text),
          'deductionRate': int.parse(_deductionController.text),
          'autoDeductEnabled': _autoDeductEnabled,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Applied to all children')),
        );
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply to All Children'),
      content: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('This will update ${widget.children.length} children'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _limitController,
                    decoration: const InputDecoration(labelText: 'Daily Limit (minutes)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final val = int.tryParse(v);
                      if (val == null || val <= 0) return 'Invalid number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deductionController,
                    decoration: const InputDecoration(labelText: 'Penalty Rate', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final val = int.tryParse(v);
                      if (val == null || val < 0) return 'Invalid number';
                      return null;
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Auto-deduct'),
                    value: _autoDeductEnabled,
                    onChanged: (v) => setState(() => _autoDeductEnabled = v),
                  ),
                ],
              ),
            ),
          ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saveToAll, child: const Text('Apply to All')),
      ],
    );
  }
}