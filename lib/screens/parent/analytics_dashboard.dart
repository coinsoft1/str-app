import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  String? _familyId;
  String? _selectedChildId;
  List<Map<String, dynamic>> _children = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final familyId = userDoc.data()?['familyId'];

    final childrenSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();

    setState(() {
      _familyId = familyId;
      _children = childrenSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // FIXED: Check multiple possible name fields
        final name = data['name'] ?? data['displayName'] ?? data['username'] ?? 'Unnamed Child';
        return {
          'id': doc.id,
          'name': name,
        };
      }).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Analytics'),
        centerTitle: true,
        actions: [
          if (_children.length > 1)
            PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Select Child',
              onSelected: (childId) => setState(() => _selectedChildId = childId),
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('All Children')),
                ..._children.map((child) => PopupMenuItem(
                  value: child['id'] as String,
                  child: Text(child['name'] as String),
                )),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChildSelector(),
              const SizedBox(height: 16),
              _buildSummaryCards(),
              const SizedBox(height: 24),
              _buildTaskAnalytics(),
              const SizedBox(height: 24),
              _buildRewardsAnalytics(),
              const SizedBox(height: 24),
              _buildScreenTimeAnalytics(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildSelector() {
    if (_children.isEmpty) return const SizedBox.shrink();
    if (_children.length == 1) {
      _selectedChildId = _children.first['id'] as String;
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.people, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _selectedChildId,
                isExpanded: true, // FIXED: Prevent overflow
                decoration: const InputDecoration(
                  labelText: 'View Analytics For',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Children')),
                  ..._children.map((child) => DropdownMenuItem(
                    value: child['id'] as String,
                    child: Text(child['name'] as String),
                  )),
                ],
                onChanged: (val) => setState(() => _selectedChildId = val),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getTasksStream(),
      builder: (context, taskSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _getRedemptionsStream(),
          builder: (context, redemptionSnapshot) {
            final tasks = taskSnapshot.data?.docs ?? [];
            final redemptions = redemptionSnapshot.data?.docs ?? [];

            // Calculate stats
            final completedTasks = tasks.where((t) {
              final status = (t.data() as Map<String, dynamic>)['status'] ?? '';
              return status == 'completed' || status == 'approved';
            }).length;

            final pendingTasks = tasks.where((t) {
              final status = (t.data() as Map<String, dynamic>)['status'] ?? '';
              return status == 'assigned';
            }).length;

            final totalPointsEarned = tasks.fold<int>(0, (sum, t) {
              final data = t.data() as Map<String, dynamic>;
              if (data['status'] == 'completed' || data['status'] == 'approved') {
                return sum + ((data['points'] ?? 0) as int);
              }
              return sum;
            });

            final totalPointsSpent = redemptions.fold<int>(0, (sum, r) {
              final data = r.data() as Map<String, dynamic>;
              return sum + ((data['pointCost'] ?? 0) as int);
            });

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _SummaryCard(
                  title: 'Tasks Completed',
                  value: '$completedTasks',
                  subtitle: '$pendingTasks pending',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                _SummaryCard(
                  title: 'Points Earned',
                  value: '$totalPointsEarned',
                  subtitle: '$totalPointsSpent spent',
                  icon: Icons.stars,
                  color: Colors.amber,
                ),
                _SummaryCard(
                  title: 'Net Balance',
                  value: '${totalPointsEarned - totalPointsSpent}',
                  subtitle: 'Available now',
                  icon: Icons.account_balance,
                  color: Colors.blue,
                ),
                _SummaryCard(
                  title: 'Rewards Redeemed',
                  value: '${redemptions.length}',
                  subtitle: 'Total redemptions',
                  icon: Icons.card_giftcard,
                  color: Colors.purple,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTaskAnalytics() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getTasksStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingCard();

        final tasks = snapshot.data!.docs;
        if (tasks.isEmpty) return const _EmptyCard(message: 'No task data yet');

        // Group by status
        final statusCounts = <String, int>{};
        for (var task in tasks) {
          final status = (task.data() as Map<String, dynamic>)['status'] ?? 'unknown';
          statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        }

        final completed = statusCounts['completed'] ?? 0;
        final approved = statusCounts['approved'] ?? 0;
        final pending = statusCounts['assigned'] ?? 0;
        final pendingApproval = statusCounts['pending_approval'] ?? 0;
        final rejected = statusCounts['rejected'] ?? 0;

        final total = tasks.length;
        final completionRate = total > 0 ? ((completed + approved) / total * 100).toStringAsFixed(1) : '0';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Task Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Chip(label: Text('$completionRate% completion'), backgroundColor: Colors.green[100]),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Colors.green,
                          value: (completed + approved).toDouble(),
                          title: '${completed + approved}',
                          radius: 60,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        PieChartSectionData(
                          color: Colors.orange,
                          value: pending.toDouble(),
                          title: '$pending',
                          radius: 60,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        PieChartSectionData(
                          color: Colors.blue,
                          value: pendingApproval.toDouble(),
                          title: '$pendingApproval',
                          radius: 60,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        PieChartSectionData(
                          color: Colors.red,
                          value: rejected.toDouble(),
                          title: '$rejected',
                          radius: 60,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _LegendItem(color: Colors.green, label: 'Completed'),
                    _LegendItem(color: Colors.orange, label: 'Pending'),
                    _LegendItem(color: Colors.blue, label: 'Awaiting Approval'),
                    _LegendItem(color: Colors.red, label: 'Rejected'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRewardsAnalytics() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getRedemptionsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingCard();

        final redemptions = snapshot.data!.docs;
        if (redemptions.isEmpty) return const _EmptyCard(message: 'No redemption data yet');

        // Group by month
        final monthlyData = <String, int>{};
        for (var redemption in redemptions) {
          final data = redemption.data() as Map<String, dynamic>;
          final timestamp = data['redeemedAt'] ?? data['completedAt'] ?? data['createdAt'];
          if (timestamp != null) {
            final date = (timestamp as Timestamp).toDate();
            final key = DateFormat('MMM').format(date);
            monthlyData[key] = (monthlyData[key] ?? 0) + 1;
          }
        }

        final sortedMonths = monthlyData.keys.toList()..sort();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rewards Redemptions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${redemptions.length} total redemptions', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (monthlyData.values.isEmpty ? 0 : monthlyData.values.reduce((a, b) => a > b ? a : b)) + 1,
                      barGroups: sortedMonths.asMap().entries.map((entry) {
                        return BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: monthlyData[entry.value]!.toDouble(),
                              color: Colors.purple,
                              width: 20,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() < sortedMonths.length) {
                                return Text(sortedMonths[value.toInt()], style: const TextStyle(fontSize: 10));
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScreenTimeAnalytics() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getChildrenStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingCard();

        final children = snapshot.data!.docs;
        if (children.isEmpty) return const _EmptyCard(message: 'No children data');

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Screen Time Limits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...children.map((child) {
                  final data = child.data() as Map<String, dynamic>;
                  // FIXED: Check multiple name fields
                  final name = data['name'] ?? data['displayName'] ?? data['username'] ?? 'Unnamed Child';
                  final limit = data['dailyScreenTimeLimit'] ?? 120;
                  final autoDeduct = data['autoDeductEnabled'] ?? false;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(name),
                    subtitle: Text('Limit: ${limit}min/day • Auto-deduct: ${autoDeduct ? 'ON' : 'OFF'}'),
                    trailing: Icon(
                      autoDeduct ? Icons.check_circle : Icons.cancel,
                      color: autoDeduct ? Colors.green : Colors.grey,
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentActivity() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('parentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final notifications = snapshot.data!.docs;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...notifications.map((doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final message = data['message'] ?? 'Activity';
                  final timestamp = data['createdAt'] as Timestamp?;
                  final isBonus = data['isBonus'] ?? false;

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isBonus ? Icons.card_giftcard : Icons.notifications,
                      color: isBonus ? Colors.purple : Colors.blue,
                      size: 20,
                    ),
                    title: Text(message, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      _formatTimestamp(timestamp),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot> _getTasksStream() {
    var query = FirebaseFirestore.instance
        .collection('tasks')
        .where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser?.uid);

    if (_selectedChildId != null) {
      query = query.where('assignedTo', isEqualTo: _selectedChildId);
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot> _getRedemptionsStream() {
    var query = FirebaseFirestore.instance
        .collection('redemptions')
        .where('parentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid);

    if (_selectedChildId != null) {
      query = query.where('childId', isEqualTo: _selectedChildId);
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot> _getChildrenStream() {
    if (_selectedChildId != null) {
      return FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, isEqualTo: _selectedChildId)
          .snapshots();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .snapshots();
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}