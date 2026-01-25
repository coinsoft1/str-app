import 'package:flutter/material.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';
import 'package:intl/intl.dart';

class RewardWheelWidget extends StatefulWidget {
  final String childId;
  const RewardWheelWidget({super.key, required this.childId});

  @override
  State<RewardWheelWidget> createState() => _RewardWheelWidgetState();
}

class _RewardWheelWidgetState extends State<RewardWheelWidget> {
  final StreamController<int> _controller = StreamController<int>();
  bool _isSpinning = false;
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _rewards = [];

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  bool _canSpin() {
    if (_config == null) return false;
    
    final isEnabled = _config!['isEnabled'] ?? true;
    final deadline = _config!['deadline']?.toDate();
    final lastSpin = _config!['lastWheelSpin']?.toDate();
    final now = DateTime.now();
    
    if (!isEnabled) return false;
    if (deadline != null && now.isAfter(deadline)) return false;
    
    if (lastSpin != null) {
      final today = DateTime(now.year, now.month, now.day);
      final lastSpinDay = DateTime(lastSpin.year, lastSpin.month, lastSpin.day);
      if (today.isAtSameMomentAs(lastSpinDay)) return false;
    }
    
    return true;
  }

  String _getDisabledReason() {
    if (_config == null) return 'Not configured';
    if (!(_config!['isEnabled'] ?? true)) return 'Wheel is disabled';
    if (_config!['deadline']?.toDate() != null && DateTime.now().isAfter(_config!['deadline'].toDate())) return 'Expired';
    if (_config!['lastWheelSpin']?.toDate() != null) {
      final lastSpinDay = DateTime(_config!['lastWheelSpin'].toDate().year, _config!['lastWheelSpin'].toDate().month, _config!['lastWheelSpin'].toDate().day);
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      if (lastSpinDay.isAtSameMomentAs(today)) return 'Already spun today';
    }
    return 'Unknown';
  }

  Future<void> _spinWheel() async {
    if (_isSpinning || !_canSpin()) return;
    
    setState(() => _isSpinning = true);
    final random = Random();
    final winningIndex = random.nextInt(_rewards.length);
    
    _controller.add(winningIndex);
    
    await Future.delayed(const Duration(seconds: 4));
    
    final winningReward = _rewards[winningIndex];
    await _awardReward(winningReward);
    
    setState(() => _isSpinning = false);
  }

  Future<void> _awardReward(Map<String, dynamic> reward) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();
    
    // ✅ Use reward ID to get full details
    final rewardDoc = await FirebaseFirestore.instance
        .collection('rewards')
        .doc(reward['id'])
        .get();
    
    final rewardData = rewardDoc.data() as Map<String, dynamic>;
    final points = rewardData['points'] ?? 0;
    final title = rewardData['title'] ?? 'Reward';
    
    // Update user points
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(user.uid),
      {
        'currentPoints': FieldValue.increment(points),
        'totalPoints': FieldValue.increment(points),
        'lastWheelSpin': FieldValue.serverTimestamp(),
      }
    );

    // Log spin
    batch.set(
      FirebaseFirestore.instance.collection('wheelSpins').doc(),
      {
        'childId': user.uid,
        'rewardId': reward['id'],
        'pointsAwarded': points,
        'timestamp': FieldValue.serverTimestamp(),
      }
    );

    await batch.commit();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 You won $title! +$points points'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const SizedBox.shrink();
        
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('wheelConfigurations')
              .doc(user.uid)
              .snapshots(),
          builder: (context, configSnapshot) {
            if (!configSnapshot.hasData || !configSnapshot.data!.exists) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.casino, color: Colors.grey),
                  title: Text('Reward Wheel'),
                  subtitle: Text('No wheel configured. Ask your parent to set it up!'),
                ),
              );
            }

            final config = configSnapshot.data!.data() as Map<String, dynamic>;
            final rewardIds = List<String>.from(config['rewardIds'] ?? []);
            
            if (rewardIds.length < 2) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline, color: Colors.orange),
                  title: Text('Wheel Not Ready'),
                  subtitle: Text('Parent needs to add more rewards'),
                ),
              );
            }

            _config = config;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('wheelRewards')
                  .where('assignedTo', arrayContains: user.uid)
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, rewardSnapshot) {
                if (!rewardSnapshot.hasData || rewardSnapshot.data!.docs.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.error_outline, color: Colors.orange),
                      title: Text('Wheel Not Ready'),
                      subtitle: Text('Parent needs to add more rewards'),
                    ),
                  );
                }

                _rewards = rewardSnapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'id': doc.id,
                    'title': data['title'] ?? 'Reward',
                    'points': data['points'] ?? 0,
                  };
                }).toList();

                final canSpin = _canSpin();
                
                return Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Header with deadline
                        Row(
                          children: [
                            const Text(
                              '🎯 Daily Spin',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            if (config['deadline'] != null) ...[
                              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                'Until ${DateFormat('yyyy-MM-dd').format(config['deadline'].toDate())}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Status message if disabled
                        if (!canSpin) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.block, color: Colors.red[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _getDisabledReason(),
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Wheel
                        SizedBox(
                          height: 300,
                          child: FortuneWheel(
                            selected: _controller.stream,
                            items: _rewards.map((reward) {
                              return FortuneItem(
                                child: Text(reward['title']!),
                                style: FortuneItemStyle(
                                  color: Colors.primaries[Random().nextInt(Colors.primaries.length)],
                                  borderWidth: 2,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Spin Button
                        ElevatedButton.icon(
                          onPressed: canSpin ? _spinWheel : null,
                          icon: _isSpinning 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.casino),
                          label: Text(_isSpinning ? 'Spinning...' : 'Spin Wheel'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}