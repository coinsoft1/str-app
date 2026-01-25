import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/screen_time_service.dart';
import '../services/deduction_service.dart';
import '../services/ai_service.dart';
import '../widgets/reward_wheel_widget.dart';

class ChildDashboard extends StatefulWidget {
  const ChildDashboard({super.key});

  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends State<ChildDashboard> {
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  final AIService _aiService = AIService();

  @override
  void initState() {
    super.initState();
    DeductionService.startMonitoring();
  }

  @override
  void dispose() {
    DeductionService.stopMonitoring();
    super.dispose();
  }

  Stream<DocumentSnapshot> _getChildData() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots();
  }

  void _navigateTo(String route) => Navigator.pushNamed(context, route);

  void _showAINegotiationDialog() {
    final TextEditingController _minutesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Negotiation Bot'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smart_toy, color: Colors.purple, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Ask AI for extra screen time!\n2 points = 1 minute',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minutesController,
                decoration: const InputDecoration(
                  labelText: 'Minutes you want',
                  border: OutlineInputBorder(),
                  suffixText: 'minutes',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final minutes = int.tryParse(_minutesController.text) ?? 0;
              if (minutes <= 0) return;
              final user = FirebaseAuth.instance.currentUser;
              final childDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
              final currentPoints = childDoc.data()?['currentPoints'] ?? 0;
              final response = await _aiService.negotiateScreenTime(
                childName: childDoc.data()?['name'] ?? 'Child',
                currentPoints: currentPoints,
                requestedMinutes: minutes,
              );
              if (mounted) {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('AI Response'),
                    content: Text(response),
                    actions: [
                      if (currentPoints >= minutes * 2)
                        ElevatedButton(
                          onPressed: () {
                            DeductionService().deductPointsAndGrantTime(
                              childId: user.uid,
                              pointsToDeduct: minutes * 2,
                              minutesToGrant: minutes,
                            );
                            Navigator.pop(context);
                            setState(() {});
                          },
                          child: const Text('Accept & Exchange'),
                        ),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    ],
                  ),
                );
              }
            },
            child: const Text('Ask AI'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, loading, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('My Dashboard'),
            centerTitle: true,
            actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout, tooltip: 'Logout')],
          ),
          body: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPointsCard(),
                const SizedBox(height: 16),
                RewardWheelWidget(childId: FirebaseAuth.instance.currentUser!.uid),
                const SizedBox(height: 16),
                _buildScreenTimeCard(),
                const Divider(height: 32),
                _buildClickableSection(icon: Icons.checklist, title: 'My Tasks', subtitle: 'View and complete your tasks', color: Colors.blue, onTap: () => _navigateTo('/tasks')),
                const SizedBox(height: 12),
                _buildClickableSection(icon: Icons.card_giftcard, title: 'Rewards', subtitle: 'Redeem your points for rewards', color: Colors.orange, onTap: () => _navigateTo('/redeem_rewards')),
                const SizedBox(height: 12),
                _buildClickableSection(icon: Icons.smart_toy, title: 'AI Negotiation', subtitle: 'Ask AI for extra screen time', color: Colors.purple, onTap: _showAINegotiationDialog),
                const Divider(height: 32),
                _buildTaskPreview(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClickableSection({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32), 
              const SizedBox(width: 16), 
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
                    const SizedBox(height: 4), 
                    Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ]
                )
              ), 
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 20)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskPreview() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tasks').where('assignedTo', isEqualTo: FirebaseAuth.instance.currentUser!.uid).where('status', whereIn: ['assigned', 'pending_approval']).orderBy('dueDate').limit(3).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final tasks = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Row(
              children: [
                const Text('Recent Tasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), 
                const Spacer(), 
                TextButton(onPressed: () => _navigateTo('/tasks'), child: const Text('View All'))
              ]
            ), 
            const SizedBox(height: 8), 
            ...tasks.map((doc) {
              final task = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 8), 
                child: ListTile(
                  dense: true, 
                  leading: Icon(Icons.star, color: Colors.amber, size: 20), 
                  title: Text(task['title'] ?? 'Task'), 
                  subtitle: Text('${task['points'] ?? 0} points'), 
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]), 
                  onTap: () => _navigateTo('/tasks')
                )
              );
            }).toList()
          ]
        );
      },
    );
  }

  Widget _buildPointsCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getChildData(), 
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildErrorCard('Error loading points');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final totalPoints = data?['totalPoints'] ?? 0;
        final currentPoints = data?['currentPoints'] ?? 0;
        return Card(
          color: Colors.green[50], 
          elevation: 2, 
          child: Padding(
            padding: const EdgeInsets.all(16), 
            child: Column(
              children: [
                const Text('My Points', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
                const SizedBox(height: 16), 
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                  children: [
                    _buildPointColumn('Total Earned', totalPoints.toString(), Colors.green), 
                    Container(height: 40, width: 1, color: Colors.grey[300]), 
                    _buildPointColumn('Available', currentPoints.toString(), Colors.blue)
                  ]
                )
              ]
            )
          )
        );
      },
    );
  }

  Widget _buildPointColumn(String label, String value, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(Icons.stars, color: color, size: 20), 
            const SizedBox(width: 4), 
            Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color))
          ]
        ), 
        const SizedBox(height: 4), 
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600]))
      ]
    );
  }

  Widget _buildScreenTimeCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getChildData(), 
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return FutureBuilder<int>(
          future: ScreenTimeService().getScreenTimeMinutes(DateTime.now()), 
          builder: (context, timeSnapshot) {
            final actualMinutes = timeSnapshot.data ?? 0;
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final dailyLimit = data?['dailyScreenTimeLimit'] ?? 120;
            final remaining = dailyLimit - actualMinutes;
            final isOver = remaining <= 0;
            return Card(
              color: isOver ? Colors.red[50] : Colors.blue[50], 
              elevation: 2, 
              child: Padding(
                padding: const EdgeInsets.all(16), 
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center, 
                      children: [
                        Icon(Icons.timer, color: isOver ? Colors.red : Colors.blue, size: 32), 
                        const SizedBox(width: 12), 
                        Text(
                          isOver ? 'Time\'s up!' : '$remaining minutes left', 
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isOver ? Colors.red : Colors.blue)
                        )
                      ]
                    ), 
                    const SizedBox(height: 8), 
                    Text('Used: $actualMinutes / $dailyLimit minutes today', style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ]
                )
              )
            );
          }
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
        title: Text(message, style: const TextStyle(color: Colors.red))
      )
    );
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
            child: const Text('Logout')
          )
        ]
      )
    );
    if (confirmed != true) return;
    _isLoading.value = true;
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red));
    } finally {
      _isLoading.value = false;
    }
  }
}