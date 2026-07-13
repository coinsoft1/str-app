// lib/screens/parent_dashboard.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/settings_service.dart';
import 'create_task.dart';
import 'parent/reward_management_screen.dart';
import 'parent/analytics_dashboard.dart';
import 'parent/verification_queue_screen.dart';
import 'parent/goal_creation_screen.dart';
import 'parent/parent_goals_screen.dart';
import 'parent/wheel_config_screen.dart';
import 'parent/approve_tasks_screen.dart';
import 'usage_analytics_screen.dart';
import 'settings_screen.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});
  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _familyData;
  List<Map<String, dynamic>> _children = [];
  Map<String, String> _childNames = {};
  String? _errorMessage;
  int _pendingUsageCount = 0;
  int _pendingSessionLogsCount = 0;
  int _pendingTaskApprovalsCount = 0;
  int _activeGoalsCount = 0;
  int? _activeGoalLimit;
  int _todayLoggedMinutes = 0;
  int _todayEducationalMinutes = 0;
  int _todayEntertainmentMinutes = 0;
  List<StreamSubscription<QuerySnapshot>> _entrySubs = [];
  List<StreamSubscription<QuerySnapshot>> _sessionLogSubs = [];
  StreamSubscription<QuerySnapshot>? _goalsSub;
  StreamSubscription<QuerySnapshot>? _notificationsSub;
  StreamSubscription<QuerySnapshot>? _taskApprovalsSub;
  bool _familyCreated = false;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenPending();
    _listenGoals();
    _listenNotifications();
    _listenSessionLogs();
    _listenTaskApprovals();
  }

  @override
  void dispose() {
    for (var s in _entrySubs) s.cancel();
    for (var s in _sessionLogSubs) s.cancel();
    _goalsSub?.cancel();
    _notificationsSub?.cancel();
    _taskApprovalsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        setState(() => _errorMessage = 'User not found');
        return;
      }
      _userData = doc.data();
      final fid = _userData?['familyId'];
      if (fid != null && fid.isNotEmpty) {
        await _loadFamily(fid, user.uid);
      } else if (!_familyCreated) {
        _familyCreated = true;
        final existing = await FirebaseFirestore.instance.collection('families').where('members', arrayContains: user.uid).limit(1).get();
        if (existing.docs.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'familyId': existing.docs.first.id});
          await _loadFamily(existing.docs.first.id, user.uid);
        } else {
          await _createFamily(user.uid);
        }
      }
      await _loadActiveGoalLimit();
      await _loadTodayUsageBreakdown();
      await _autoArchiveExpiredGoals();
      await _autoVerifyOldEntries();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _errorMessage = 'Error: $e');
    }
  }

  Future<void> _loadFamily(String fid, String uid) async {
    final fdoc = await FirebaseFirestore.instance.collection('families').doc(fid).get();
    if (fdoc.exists) {
      _familyData = fdoc.data();
      if (!List.from(_familyData?['members'] ?? []).contains(uid)) {
        await fdoc.reference.update({'members': FieldValue.arrayUnion([uid])});
      }
      await _loadChildren(fid);
    } else {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'familyId': FieldValue.delete()});
      if (!_familyCreated) _loadData();
    }
  }

  Future<void> _loadChildren(String fid) async {
    final snap = await FirebaseFirestore.instance.collection('users').where('familyId', isEqualTo: fid).where('role', isEqualTo: 'child').get();
    _children = snap.docs.map((d) { final data = d.data(); data['id'] = d.id; return data; }).toList();
    _childNames = { for (var c in _children) c['id'] as String: c['displayName'] as String? ?? c['name'] as String? ?? c['username'] as String? ?? 'Child' };
  }

  Future<void> _createFamily(String uid) async {
    final ref = FirebaseFirestore.instance.collection('families').doc();
    final code = String.fromCharCodes(Iterable.generate(6, (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.codeUnitAt(Random().nextInt(36))));
    await ref.set({'createdBy': uid, 'members': [uid], 'familyCode': code, 'createdAt': FieldValue.serverTimestamp(), 'name': 'My Family'});
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'familyId': ref.id});
    await _loadFamily(ref.id, uid);
  }

  Future<void> _loadActiveGoalLimit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('goals').where('parentId', isEqualTo: user.uid).get();
      if (snap.docs.isNotEmpty) {
        final sorted = snap.docs.toList()..sort((a, b) {
          final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        final latest = sorted.first.data() as Map<String, dynamic>;
        final status = latest['status'] as String?;
        if (status == 'active' || status == 'pending_child') {
          setState(() => _activeGoalLimit = (latest['dailyScreenTimeLimit'] ?? 0) as int);
        }
      }
    } catch (e) {
      debugPrint('Error loading goal limit: $e');
    }
  }

  Future<void> _loadTodayUsageBreakdown() async {
    if (_children.isEmpty) return;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final childId = _children.first['id'] as String;
      final snap = await FirebaseFirestore.instance
          .collection('usage_entries')
          .where('childId', isEqualTo: childId)
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();
      int total = 0, edu = 0, ent = 0;
      for (var doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final mins = (data['durationMinutes'] ?? 0) as int;
        final category = data['category'] as String? ?? 'Entertainment';
        total += mins;
        if (category == 'Educational') edu += mins; else ent += mins;
      }
      setState(() {
        _todayLoggedMinutes = total;
        _todayEducationalMinutes = edu;
        _todayEntertainmentMinutes = ent;
      });
    } catch (e) {
      debugPrint('Error loading usage breakdown: $e');
    }
  }

  Future<void> _autoArchiveExpiredGoals() async {
    final fid = _userData?['familyId'] as String?;
    if (fid == null || fid.isEmpty) return;
    try {
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection('goals')
          .where('familyId', isEqualTo: fid)
          .where('status', isEqualTo: 'active')
          .get();
      final expired = snap.docs.where((doc) {
        final endDate = (doc.data() as Map<String, dynamic>)['endDate'] as Timestamp?;
        return endDate != null && endDate.toDate().isBefore(now);
      }).toList();
      if (expired.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in expired) {
        batch.update(doc.reference, {'status': 'expired', 'expiredAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
      debugPrint('Auto-archived ${expired.length} expired goals');
    } catch (e) {
      debugPrint('Error auto-archiving goals: $e');
    }
  }

  Future<void> _autoVerifyOldEntries() async {
    final fid = _userData?['familyId'] as String?;
    if (fid == null || fid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('usage_entries').where('familyId', isEqualTo: fid).get();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final oldPending = snap.docs.where((doc) {
        final data = doc.data();
        final status = data['status'] as String? ?? (data['verified'] == true ? 'verified' : 'pending');
        if (status == 'verified') return false;
        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt == null) return false;
        return createdAt.toDate().isBefore(cutoff);
      }).toList();
      if (oldPending.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in oldPending) {
        batch.update(doc.reference, {
          'verified': true,
          'status': 'verified',
          'autoVerified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      debugPrint('Auto-verified ${oldPending.length} entries older than 24h');
    } catch (e) {
      debugPrint('Auto-verify error: $e');
    }
  }

  void _listenPending() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;
      final fid = (snap.data() as Map<String, dynamic>?)?['familyId'] as String?;
      if (fid == null) return;
      for (var s in _entrySubs) s.cancel();
      _entrySubs.clear();
      final sub = FirebaseFirestore.instance.collection('usage_entries').where('familyId', isEqualTo: fid).where('status', isEqualTo: 'pending').snapshots().listen((s) {
        if (mounted) setState(() => _pendingUsageCount = s.docs.length);
      });
      _entrySubs.add(sub);
    });
  }

  void _listenSessionLogs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((userSnap) {
      if (!userSnap.exists || !mounted) return;
      final fid = (userSnap.data() as Map<String, dynamic>?)?['familyId'] as String?;
      if (fid == null) return;
      for (var s in _sessionLogSubs) s.cancel();
      _sessionLogSubs.clear();
      FirebaseFirestore.instance.collection('users').where('familyId', isEqualTo: fid).where('role', isEqualTo: 'child').snapshots().listen((childrenSnap) {
        if (!mounted) return;
        for (var s in _sessionLogSubs) s.cancel();
        _sessionLogSubs.clear();
        if (childrenSnap.docs.isEmpty) {
          setState(() => _pendingSessionLogsCount = 0);
          return;
        }
        final Map<String, int> pendingByChild = {};
        for (var child in childrenSnap.docs) {
          pendingByChild[child.id] = 0;
          final sub = FirebaseFirestore.instance.collection('users').doc(child.id).collection('sessionLogs').where('status', isEqualTo: 'pending').snapshots().listen((logsSnap) {
            if (!mounted) return;
            pendingByChild[child.id] = logsSnap.docs.length;
            final total = pendingByChild.values.fold(0, (a, b) => a + b);
            setState(() => _pendingSessionLogsCount = total);
          });
          _sessionLogSubs.add(sub);
        }
      });
    });
  }

  void _listenGoals() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _goalsSub = FirebaseFirestore.instance.collection('goals').where('parentId', isEqualTo: user.uid).where('status', isEqualTo: 'active').snapshots().listen((s) {
      if (mounted) setState(() => _activeGoalsCount = s.docs.length);
    });
  }

  void _listenNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _notificationsSub = FirebaseFirestore.instance.collection('notifications').where('parentId', isEqualTo: user.uid).snapshots().listen((snap) {
      if (!mounted) return;
      final unread = snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['read'] != true;
      }).length;
      setState(() => _unreadNotificationCount = unread);
    });
  }

  void _listenTaskApprovals() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _taskApprovalsSub = FirebaseFirestore.instance
        .collection('tasks')
        .where('createdBy', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending_approval')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _pendingTaskApprovalsCount = snap.docs.length);
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    // AuthWrapper handles routing automatically
  }

  String _fmt(dynamic p) {
    if (p == null) return '0';
    final v = (p is num) ? p.toDouble() : 0.0;
    final r = double.parse(v.toStringAsFixed(2));
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(2);
  }

  int _getMinimumRequired() {
    if (_activeGoalLimit == null || _activeGoalLimit == 0) return 0;
    return max(5, (_activeGoalLimit! * 0.1).round());
  }

  String _getUsageInsight() {
    final min = _getMinimumRequired();
    if (_todayLoggedMinutes == 0) return 'No sessions logged today. Bonus unavailable.';
    if (_todayLoggedMinutes < min) return 'Logged time ($_todayLoggedMinutes min) is below the minimum required ($min min). Bonus unavailable.';
    if (_activeGoalLimit != null && _todayLoggedMinutes >= _activeGoalLimit!) return 'Daily limit reached or exceeded. No savings bonus.';
    return 'Usage is within the expected range. Bonus eligible.';
  }

  bool _isBonusEligible() {
    final min = _getMinimumRequired();
    return _activeGoalLimit != null && _activeGoalLimit! > 0 && _todayLoggedMinutes >= min && _todayLoggedMinutes < _activeGoalLimit!;
  }

  int _getSavedMinutes() {
    if (_activeGoalLimit == null) return 0;
    return max(0, _activeGoalLimit! - _todayLoggedMinutes);
  }

  int _getBonusPoints() {
    return (_getSavedMinutes() / 2).round();
  }

  Future<void> _giveBonus() async {
    if (_children.isEmpty) return;
    final childId = _children.first['id'] as String;
    final childName = _childNames[childId] ?? 'Child';
    final points = _getBonusPoints();
    try {
      await FirebaseFirestore.instance.collection('users').doc(childId).update({
        'currentPoints': FieldValue.increment(points),
        'totalPoints': FieldValue.increment(points),
      });
      await FirebaseFirestore.instance.collection('pointTransactions').add({
        'childId': childId,
        'childName': childName,
        'type': 'screen_time_savings_bonus',
        'points': points,
        'description': 'Saved ${_getSavedMinutes()} minutes of screen time',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Gave $points bonus points to $childName!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editGoal(String goalId, Map<String, dynamic> goalData) async {
    final status = goalData['status'] as String?;
    if (status == 'active') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit Active Goal'),
          content: const Text('This goal is already active. Your child will see the changes immediately. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Edit')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalCreationScreen(editGoalId: goalId, existingGoal: goalData)),
    );
  }

  Future<void> _deleteGoal(String goalId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal'),
        content: Text('Delete "$title"? This will archive the goal and unlink its tasks.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final tasksSnap = await FirebaseFirestore.instance.collection('tasks').where('goalId', isEqualTo: goalId).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in tasksSnap.docs) {
        batch.update(doc.reference, {'goalId': FieldValue.delete()});
      }
      await batch.commit();
      await FirebaseFirestore.instance.collection('goals').doc(goalId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': FirebaseAuth.instance.currentUser!.uid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goal deleted and archived to history')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting goal: $e'), backgroundColor: Colors.red));
      }
    }
  }

  String _formatShortDate(DateTime date) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[date.month]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (_errorMessage != null) {
          return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)), const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ])));
        }

        final accentColor = SettingsService.instance.accentColor;
        final appBarBg = Color.lerp(Colors.white, accentColor, 0.12)!;
        final headerBg1 = Color.lerp(Colors.white, accentColor, 0.18)!;
        final headerBg2 = Color.lerp(Colors.white, accentColor, 0.08)!;
        final headerBorder = Color.lerp(Colors.white, accentColor, 0.35)!;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: appBarBg,
            title: Text('Parent Dashboard', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: Icon(Icons.settings, color: accentColor),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                tooltip: 'Settings',
              ),
              IconButton(icon: Icon(Icons.refresh, color: accentColor), onPressed: _loadData),
              IconButton(icon: Icon(Icons.logout, color: accentColor), onPressed: _logout),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _familyHeader(accentColor, headerBg1, headerBg2, headerBorder),
                  const SizedBox(height: 16),
                  if (_children.isNotEmpty) ...[
                    _childrenSection(accentColor),
                    const SizedBox(height: 16),
                  ],
                  _goalsSection(accentColor),
                  const SizedBox(height: 16),
                  _grid(accentColor),
                  const SizedBox(height: 16),
                  _activityReportCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _familyHeader(Color accent, Color bg1, Color bg2, Color border) {
    final name = _familyData?['name'] ?? 'My Family';
    final code = _familyData?['familyCode'] ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [bg1, bg2]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.family_restroom, color: accent),
              const SizedBox(width: 8),
              Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
            ],
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Family Code: ', style: TextStyle(fontSize: 14, color: accent.withAlpha(180))),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withAlpha(100)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(code, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: accent, letterSpacing: 1)),
                        const SizedBox(width: 4),
                        Icon(Icons.copy, size: 14, color: accent.withAlpha(180)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _childrenSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Children', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _children.length,
            itemBuilder: (context, i) {
              final c = _children[i];
              final id = c['id'] as String;
              final name = _childNames[id] ?? 'Child';
              final pts = c['currentPoints'] ?? 0;
              final limit = c['dailyScreenTimeLimit'] ?? 0;
              return Container(
                width: 160,
                margin: EdgeInsets.only(right: i < _children.length - 1 ? 12 : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Color.lerp(Colors.white, accent, 0.15)!,
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.stars, size: 14, color: Colors.amber.shade600),
                        const SizedBox(width: 4),
                        Text('${_fmt(pts)} pts', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 4),
                        Text(limit > 0 ? '${limit}m limit' : 'No limit', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _goalsSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/goal_history'),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalCreationScreen())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('goals')
              .where('familyId', isEqualTo: _userData?['familyId'] ?? '')
              .where('status', isEqualTo: 'active')
              .limit(3)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Create goals to see them here', style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
                  ],
                ),
              );
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Expanded(child: Text('No active goals. Create one!', style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
                  ],
                ),
              );
            }
            return Column(
              children: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final title = d['title'] ?? 'Goal';
                final desc = d['description'] ?? '';
                final target = (d['targetValue'] ?? 0).toDouble();
                final current = (d['currentValue'] ?? 0).toDouble();
                final prog = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
                final startTs = d['startDate'] as Timestamp?;
                final endTs = d['endDate'] as Timestamp?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyan.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag, size: 16, color: Colors.cyan.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                          Text('${current.toInt()} / ${target.toInt()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.edit, size: 18, color: Colors.cyan.shade700),
                            onPressed: () => _editGoal(doc.id, d),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                            onPressed: () => _deleteGoal(doc.id, title),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      if (startTs != null && endTs != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('${_formatShortDate(startTs.toDate())} — ${_formatShortDate(endTs.toDate())}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: prog,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(prog >= 1.0 ? Colors.green : Colors.cyan),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _grid(Color accent) {
    final items = [
      _Item(Icons.assignment, 'Tasks', Colors.blue, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTaskScreen()));
      }),
      _Item(Icons.card_giftcard, 'Rewards', Colors.amber, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardManagementScreen()));
      }),
      _Item(Icons.fact_check, 'Approvals', Colors.purple, () {
        Navigator.pushNamed(context, '/approve_tasks');
      }, _pendingTaskApprovalsCount > 0 ? _pendingTaskApprovalsCount : null),
      _Item(Icons.notifications, 'Notifications', Colors.green, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentNotificationsScreen()));
      }, _unreadNotificationCount > 0 ? _unreadNotificationCount : null),
      _Item(Icons.analytics, 'Analytics', Colors.indigo, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsDashboard()));
      }),
      _Item(Icons.verified_user, 'Verify', Colors.teal, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationQueueScreen()));
      }, _pendingSessionLogsCount > 0 ? _pendingSessionLogsCount : null),
      _Item(Icons.casino, 'Wheel', Colors.orange, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WheelConfigScreen()));
      }),
    ];
    final w = (MediaQuery.of(context).size.width - 44) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) {
            return SizedBox(
              width: w,
              height: 100,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: item.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: item.color.withAlpha(76)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: item.color.withAlpha(25), shape: BoxShape.circle),
                            child: Icon(item.icon, color: item.color, size: 28),
                          ),
                          if (item.badge != null && item.badge! > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: Text('${item.badge}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(item.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _activityReportCard() {
    if (_children.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            Icon(Icons.insert_chart_outlined, color: Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(child: Text('Add children to view activity reports.', style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _showChildSelectorBottomSheet,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.blue.shade50], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.insert_chart, color: Colors.indigo.shade700, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Screen Time Activity Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                  const SizedBox(height: 4),
                  Text('View educational vs entertainment trends, charts, and export reports', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.indigo.shade400),
          ],
        ),
      ),
    );
  }

  void _showChildSelectorBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                Text('Select Child', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                const SizedBox(height: 4),
                Text('Choose which child to view the activity report for', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                ..._children.map((child) {
                  final id = child['id'] as String;
                  final name = _childNames[id] ?? 'Child';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade100,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => UsageAnalyticsScreen(childId: id, childName: name)));
                    },
                  );
                }).toList(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
  _Item(this.icon, this.label, this.color, this.onTap, [this.badge]);
}

class ParentNotificationsScreen extends StatefulWidget {
  const ParentNotificationsScreen({super.key});
  @override
  State<ParentNotificationsScreen> createState() => _ParentNotificationsScreenState();
}

class _ParentNotificationsScreenState extends State<ParentNotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    final accent = SettingsService.instance.accentColor;
    final appBarBg = Color.lerp(Colors.white, accent, 0.12)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: appBarBg,
        elevation: 0,
        actions: [
          TextButton(onPressed: _markAllAsRead, child: const Text('Mark All Read')),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('notifications').where('parentId', isEqualTo: user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs.toList()..sort((a, b) {
            final aTime = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final bTime = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No notifications yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final title = data['title'] ?? 'Notification';
              final message = data['message'] ?? '';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => doc.reference.delete(),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: isRead ? 0 : 2,
                  color: isRead ? Colors.grey.shade50 : Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isRead ? Colors.grey.shade200 : Color.lerp(Colors.white, accent, 0.15)!,
                      child: Icon(_getIconForType(data['type'] as String?), color: isRead ? Colors.grey : accent),
                    ),
                    title: Text(title, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                    subtitle: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!isRead) Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                        const SizedBox(height: 4),
                        Text(_formatTime(createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                    onTap: () => _markAsRead(doc.reference, isRead),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final unread = await FirebaseFirestore.instance.collection('notifications').where('parentId', isEqualTo: user.uid).get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in unread.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['read'] != true) batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _markAsRead(DocumentReference ref, bool isRead) async {
    if (!isRead) await ref.update({'read': true});
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'reward_redeemed': return Icons.card_giftcard;
      case 'bonus_redeemed': return Icons.emoji_events;
      case 'bonus_claimed': return Icons.emoji_events;
      case 'wheel_win': return Icons.casino;
      case 'goal_declined': return Icons.flag;
      case 'task_approval': return Icons.assignment_turned_in;
      case 'task_approved': return Icons.check_circle;
      case 'task_rejected': return Icons.cancel;
      default: return Icons.notifications;
    }
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}