// lib/screens/child_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/usage_sync_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../widgets/reward_wheel_widget.dart';
import 'settings_screen.dart';

class ChildDashboard extends StatefulWidget {
  const ChildDashboard({super.key});
  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends State<ChildDashboard> with WidgetsBindingObserver {
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  final ScrollController _scrollController = ScrollController();
  Timer? _syncTimer;
  String? _lastUpdateKey;
  Timer? _updateBannerTimer;
  bool _showUpdateBanner = true;
  StreamSubscription<QuerySnapshot>? _rejectedLogNotifSub;
  Map<String, dynamic>? _rejectedLogNotification;
  String? _rejectedLogNotifDocId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAutoSync();
    NotificationService.init().then((_) => NotificationService.refreshReminders());
    _listenRejectedLogNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _scrollController.dispose();
    _updateBannerTimer?.cancel();
    _rejectedLogNotifSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      UsageSyncService.syncTodayUsage();
      NotificationService.refreshReminders();
    }
  }

  Future<void> _setupAutoSync() async {
    await UsageSyncService.syncTodayUsage();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) { UsageSyncService.syncTodayUsage(); } else { timer.cancel(); }
    });
  }

  void _listenRejectedLogNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _rejectedLogNotifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('childId', isEqualTo: user.uid)
        .where('type', isEqualTo: 'log_rejected')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        setState(() {
          _rejectedLogNotification = doc.data() as Map<String, dynamic>;
          _rejectedLogNotifDocId = doc.id;
        });
      } else {
        setState(() { _rejectedLogNotification = null; _rejectedLogNotifDocId = null; });
      }
    });
  }

  Future<void> _onRejectedLogTapped() async {
    if (_rejectedLogNotifDocId != null) {
      try {
        await FirebaseFirestore.instance.collection('notifications').doc(_rejectedLogNotifDocId!).update({'read': true});
      } catch (e) { debugPrint('Error marking notif read: $e'); }
    }
    if (mounted) Navigator.pushNamed(context, '/session_logging');
  }

  Future<void> _dismissRejectedLogBanner() async {
    if (_rejectedLogNotifDocId != null) {
      try {
        await FirebaseFirestore.instance.collection('notifications').doc(_rejectedLogNotifDocId!).update({'read': true});
      } catch (e) { debugPrint('Error dismissing notif: $e'); }
    }
    setState(() { _rejectedLogNotification = null; _rejectedLogNotifDocId = null; });
  }

  Stream<DocumentSnapshot> _getChildData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  Stream<QuerySnapshot> _getGoalStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('goals').where('childId', isEqualTo: user.uid).limit(10).snapshots();
  }

  void _navigateTo(String route) => Navigator.pushNamed(context, route);

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Safely cancel reminders — never let this block logout
    try {
      await NotificationService.cancelGoalReminders();
    } catch (e) {
      debugPrint('cancelGoalReminders failed: $e');
    }

    // Safely sign out — never let this block logout
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('signOut failed: $e');
    }

    // Force navigation to login no matter what
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  String _formatPoints(dynamic points) {
    if (points == null) return '0';
    final double val = (points is num) ? points.toDouble() : 0.0;
    final rounded = double.parse(val.toStringAsFixed(2));
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    return rounded.toStringAsFixed(2);
  }

  String _getMotivationalMessage(int completed, int total, String rewardTitle) {
    final remaining = total - completed;
    if (remaining <= 0) return '🎉 Goal complete! Amazing work!';
    if (completed == 0) return 'Let\'s get started! Complete your task today.';
    if (completed == 1) return 'You\'re on fire! $remaining more tasks to earn $rewardTitle.';
    if (remaining == 1) return 'So close! Just 1 more task to unlock $rewardTitle!';
    return 'Keep going! $remaining more tasks to earn $rewardTitle.';
  }

  String _getDurationLabel(String? duration) {
    switch (duration) {
      case 'weekly': return 'Weekly Goal';
      case 'monthly': return 'Monthly Goal';
      case 'daily': default: return 'Daily Goal';
    }
  }

  String _formatShortDate(DateTime date) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[date.month]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final userId = user.uid;

    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final accent = SettingsService.instance.accentColor;
        final appBarBg = Color.lerp(Colors.white, accent, 0.12)!;
        return ValueListenableBuilder<bool>(
          valueListenable: _isLoading,
          builder: (context, loading, child) {
            return Scaffold(
              backgroundColor: Colors.grey.shade50,
              appBar: AppBar(
                elevation: 0,
                backgroundColor: appBarBg,
                title: Text('My Dashboard', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                centerTitle: true,
                actions: [
                  IconButton(icon: Icon(Icons.settings, color: accent), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), tooltip: 'Settings'),
                  IconButton(icon: Icon(Icons.logout, color: accent), onPressed: _handleLogout, tooltip: 'Logout'),
                ],
              ),
              body: RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (_rejectedLogNotification != null) ...[
                      _buildRejectedLogBanner(),
                      const SizedBox(height: 12),
                    ],
                    _buildProfileHeader(),
                    const SizedBox(height: 16),
                    _buildGoalBanner(),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Quick Actions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildActionCard(icon: Icons.checklist, title: 'My Tasks', subtitle: 'View & Complete', color: Colors.blue, gradient: [Colors.blue.shade400, Colors.blue.shade600], onTap: () => _navigateTo('/tasks'))),
                              const SizedBox(width: 12),
                              Expanded(child: _buildActionCard(icon: Icons.card_giftcard, title: 'Rewards', subtitle: 'Redeem Points', color: Colors.orange, gradient: [Colors.orange.shade400, Colors.orange.shade600], onTap: () => _navigateTo('/redeem_rewards'))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _buildActionCard(icon: Icons.add_chart, title: 'Log Time', subtitle: 'Screen Use', color: Colors.green, gradient: [Colors.green.shade400, Colors.green.shade600], onTap: () => _navigateTo('/session_logging'))),
                              const SizedBox(width: 12),
                              Expanded(child: _buildActionCard(icon: Icons.flag, title: 'My Goal', subtitle: 'View Progress', color: Colors.purple, gradient: [Colors.purple.shade400, Colors.purple.shade600], onTap: () => _navigateTo('/goal_review'))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    RewardWheelWidget(childId: userId),
                    const SizedBox(height: 16),
                    _buildScreenTimeLimitCard(),
                    const SizedBox(height: 16),
                    _buildTodaysActivityCard(),
                    const SizedBox(height: 16),
                    _buildTaskPreview(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRejectedLogBanner() {
    final appName = _rejectedLogNotification?['message']?.toString().split('rejected your ')?.last?.split(' log')?.first ?? 'your app';
    return GestureDetector(
      onTap: _onRejectedLogTapped,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Log Rejected by Parent', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Your $appName log was rejected. Tap to re-log.', style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.red.shade400, size: 20),
              onPressed: _dismissRejectedLogBanner,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getChildData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.amber.shade400, Colors.orange.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20)),
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final points = data?['currentPoints'] ?? 0;
        final lifetime = data?['lifetimePoints'] ?? data?['totalPoints'] ?? 0;
        final name = data?['name'] ?? data?['username'] ?? 'Child';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.amber.shade400, Colors.orange.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.orange.withAlpha(76), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _showAvatarPicker(),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(color: Colors.white.withAlpha(76), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                  child: Center(child: Text(_getAvatarEmoji(data?['avatar'] ?? '👤'), style: const TextStyle(fontSize: 28))),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hi, $name! 👋', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Your Points: ${_formatPoints(points)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    Text('Lifetime: ${_formatPoints(lifetime)}', style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getAvatarEmoji(String avatar) {
    const emojis = ['👤', '🦁', '🐯', '🐻', '🐼', '🐨', '🐸', '🐙', '🦄', '🦊', '🐰', '🐱'];
    if (emojis.contains(avatar)) return avatar;
    return '👤';
  }

  void _showAvatarPicker() {
    final emojis = ['👤', '🦁', '🐯', '🐻', '🐼', '🐨', '🐸', '🐙', '🦄', '🦊', '🐰', '🐱'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Your Avatar'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: emojis.map((emoji) {
            return GestureDetector(
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'avatar': emoji});
                }
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                child: Text(emoji, style: const TextStyle(fontSize: 32)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGoalBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getGoalStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, color: Colors.grey.shade600, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No Active Goal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      Text('Ask your parent to set a goal!', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final goals = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String?;
          return status == 'pending_child' || status == 'active';
        }).toList();

        goals.sort((a, b) {
          final aTime = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bTime = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });

        if (goals.isEmpty) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, color: Colors.grey.shade600, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No Active Goal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      Text('Ask your parent to set a goal!', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final goalDoc = goals.first;
        final goalId = goalDoc.id;
        final goal = goalDoc.data() as Map<String, dynamic>;
        final isPending = goal['status'] == 'pending_child';
        final tasks = (goal['tasks'] as List<dynamic>?) ?? [];
        final completed = tasks.where((t) => t['completed'] == true).length;
        final total = tasks.length;
        final progress = total > 0 ? completed / total : 0.0;
        final rewardTitle = goal['reward']?['title'] ?? 'your reward';
        final duration = goal['duration'] as String? ?? 'daily';
        final durationLabel = _getDurationLabel(duration);
        final startDate = (goal['startDate'] as Timestamp?)?.toDate();
        final endDate = (goal['endDate'] as Timestamp?)?.toDate();
        final childSignedAt = (goal['childSignedAt'] as Timestamp?)?.toDate();
        final updatedAt = (goal['updatedAt'] as Timestamp?)?.toDate();
        final wasUpdated = childSignedAt != null && updatedAt != null && updatedAt.isAfter(childSignedAt);
        final currentUpdatedAt = (goal['updatedAt'] as Timestamp?)?.toDate();
        final currentKey = '$goalId|${currentUpdatedAt?.millisecondsSinceEpoch ?? 0}';

        if (wasUpdated && !isPending && _lastUpdateKey != currentKey) {
          _lastUpdateKey = currentKey;
          _updateBannerTimer?.cancel();
          _showUpdateBanner = true;
          _updateBannerTimer = Timer(const Duration(minutes: 3), () {
            if (mounted) setState(() => _showUpdateBanner = false);
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(child: Text('New goal from your parent! Review it below.', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600, fontSize: 14))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (wasUpdated && !isPending && _showUpdateBanner) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                child: Row(
                  children: [
                    Icon(Icons.update, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Your parent updated this goal! Review the changes below.', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600, fontSize: 14))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.teal.shade400, Colors.teal.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.teal.withAlpha(76), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(51), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.flag, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(goal['title'] ?? durationLabel, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                          child: const Text('PENDING', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(durationLabel, style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 12, fontWeight: FontWeight.w500)),
                  if (startDate != null && endDate != null) ...[
                    const SizedBox(height: 4),
                    Text('${_formatShortDate(startDate)} — ${_formatShortDate(endDate)}', style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                  const SizedBox(height: 12),
                  if (isPending) ...[
                    Text('Your parent set a new goal! Tap "My Goal" to review and accept.', style: TextStyle(color: Colors.white.withAlpha(242), fontSize: 14, height: 1.5)),
                  ] else ...[
                    Text(_getMotivationalMessage(completed, total, rewardTitle), style: TextStyle(color: Colors.white.withAlpha(242), fontSize: 14, height: 1.5)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white.withAlpha(76), valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 8),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({required IconData icon, required String title, required String subtitle, required Color color, required List<Color> gradient, required VoidCallback onTap}) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withAlpha(76), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenTimeLimitCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final userId = user.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final childName = userData?['name'] ?? userData?['username'] ?? 'there';

        return StreamBuilder<QuerySnapshot>(
          stream: _getGoalStream(),
          builder: (context, goalSnapshot) {
            String goalTitle = '';
            int limitMinutes = 0;

            if (goalSnapshot.hasData && goalSnapshot.data!.docs.isNotEmpty) {
              final goals = goalSnapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] as String?;
                return status == 'pending_child' || status == 'active';
              }).toList();

              goals.sort((a, b) {
                final aTime = ((a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                final bTime = ((b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                return bTime.compareTo(aTime);
              });

              if (goals.isNotEmpty) {
                final goalData = goals.first.data() as Map<String, dynamic>;
                goalTitle = goalData['title'] ?? 'your goal';
                limitMinutes = (goalData['dailyScreenTimeLimit'] ?? 0) as int;
              }
            }

            if (limitMinutes <= 0) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.timer, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi $childName,', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'To achieve your goal '),
                              TextSpan(text: '"$goalTitle"', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const TextSpan(text: ', make sure you don\'t use more than '),
                              TextSpan(text: '$limitMinutes minutes', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                              const TextSpan(text: ' of screen time today.'),
                            ],
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.lightbulb, size: 14, color: Colors.amber.shade600),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Tip: Log your screen time to stay on track!', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTodaysActivityCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final userId = user.uid;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('sessionLogs')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final logs = snapshot.data?.docs ?? [];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text('Today\'s Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                ],
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                Text('No screen time logged today', style: TextStyle(color: Colors.grey.shade500, fontSize: 14))
              else
                ...logs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final appName = data['appName'] ?? 'Unknown';
                  final duration = (data['durationMinutes'] ?? 0) as int;
                  final category = data['category'] ?? 'Unknown';
                  final status = data['status'] ?? 'pending';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _getCategoryColor(category).withAlpha(30),
                          child: Icon(_getCategoryIcon(category), size: 16, color: _getCategoryColor(category)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(appName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              Text('$duration min • ${_capitalize(category)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        _buildStatusIndicator(status),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'educational': return Colors.blue;
      case 'entertainment': return Colors.orange;
      case 'social': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'educational': return Icons.school;
      case 'entertainment': return Icons.videogame_asset;
      case 'social': return Icons.people;
      default: return Icons.devices;
    }
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    IconData icon;
    String label;
    switch (status) {
      case 'verified': color = Colors.green; icon = Icons.check_circle; label = 'Verified'; break;
      case 'corrected': color = Colors.orange; icon = Icons.edit; label = 'Corrected'; break;
      case 'rejected': color = Colors.red; icon = Icons.cancel; label = 'Rejected'; break;
      default: color = Colors.grey; icon = Icons.hourglass_empty; label = 'Pending';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Widget _buildTaskPreview() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final userId = user.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final tasks = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Pending Tasks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                  TextButton(onPressed: () => _navigateTo('/tasks'), child: const Text('View All')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blue.shade100, child: Icon(Icons.task, color: Colors.blue.shade700)),
                    title: Text(task['title'] ?? 'Task'),
                    subtitle: Text('${task['points']} points • Due: ${_formatDate(task['deadline'])}', style: TextStyle(color: Colors.grey.shade600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _navigateTo('/tasks'),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'No deadline';
    if (date is Timestamp) {
      final dt = date.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return 'No deadline';
  }
}