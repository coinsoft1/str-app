// lib/screens/child/redeem_rewards_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class RedeemRewardsScreen extends StatefulWidget {
  const RedeemRewardsScreen({super.key});

  @override
  State<RedeemRewardsScreen> createState() => _RedeemRewardsScreenState();
}

class _RedeemRewardsScreenState extends State<RedeemRewardsScreen> {
  bool _isRedeeming = false;
  bool _isClaiming = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Redeem Rewards'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(child: Text('Error: ${userSnapshot.error}'));
          }

          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
          final currentPoints = userData?['currentPoints'] ?? 0;
          final familyId = userData?['familyId'] as String?;
          final childId = user.uid;

          return Column(
            children: [
              // Points Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber.shade400, Colors.orange.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.stars, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Your Points: ${_formatPoints(currentPoints)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Won Bonuses from Wheel
              // FIXED: Removed .orderBy('wonAt') to avoid Firestore composite index requirement
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(childId)
                    .collection('wonRewards')
                    .where('claimed', isEqualTo: false)
                    .snapshots(),
                builder: (context, wonSnapshot) {
                  if (wonSnapshot.hasData && wonSnapshot.data!.docs.isNotEmpty) {
                    // NEW: Sort client-side instead of Firestore orderBy
                    final wonDocs = wonSnapshot.data!.docs.toList()
                      ..sort((a, b) {
                        final aTime = ((a.data() as Map<String, dynamic>)['wonAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                        final bTime = ((b.data() as Map<String, dynamic>)['wonAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                        return bTime.compareTo(aTime);
                      });

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.emoji_events, color: Colors.purple.shade700),
                              const SizedBox(width: 8),
                              Text(
                                '🎉 Wheel Prizes (${wonDocs.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...wonDocs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final rewardName = data['rewardName'] ?? 'Bonus Reward';
                            final rewardData = data['rewardData'] as Map<String, dynamic>?;
                            final description = rewardData?['description'] ?? '';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: Colors.purple.shade100,
                              child: ListTile(
                                leading: const Icon(Icons.card_giftcard, color: Colors.purple),
                                title: Text(
                                  rewardName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  description.isNotEmpty ? description : 'Won from the bonus wheel!',
                                  style: TextStyle(fontSize: 12, color: Colors.purple.shade900),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: _isClaiming ? null : () => _claimWonReward(doc.id, rewardName, childId, userData?['parentId'] as String?, userData?['name'] ?? 'Child'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: _isClaiming
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Claim'),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rewards')
                      .where('childId', isEqualTo: childId)
                      .where('isAvailable', isEqualTo: true)
                      .snapshots(),
                  builder: (context, goalRewardsSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: familyId != null
                          ? FirebaseFirestore.instance
                          .collection('rewards')
                          .where('familyId', isEqualTo: familyId)
                          .where('isActive', isEqualTo: true)
                          .snapshots()
                          : Stream<QuerySnapshot>.empty(),
                      builder: (context, familyRewardsSnapshot) {
                        if (goalRewardsSnapshot.connectionState == ConnectionState.waiting &&
                            familyRewardsSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final List<QueryDocumentSnapshot> allRewards = [];

                        if (goalRewardsSnapshot.hasData) {
                          allRewards.addAll(goalRewardsSnapshot.data!.docs);
                        }

                        if (familyRewardsSnapshot.hasData && familyRewardsSnapshot.data != null) {
                          final existingIds = allRewards.map((r) => r.id).toSet();
                          for (var doc in familyRewardsSnapshot.data!.docs) {
                            if (!existingIds.contains(doc.id)) {
                              final data = doc.data() as Map<String, dynamic>;
                              final isWheelOnly = data['isWheelOnly'] as bool? ?? false;
                              final isSystemDefault = data['isSystemDefault'] as bool? ?? false;
                              final isCustomWheelBonus = data['isCustomWheelBonus'] as bool? ?? false;
                              if (!isWheelOnly && !isSystemDefault && !isCustomWheelBonus) {
                                allRewards.add(doc);
                              }
                            }
                          }
                        }

                        if (allRewards.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.card_giftcard, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text(
                                  'No rewards available',
                                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Complete tasks to earn rewards!',
                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: allRewards.length,
                          itemBuilder: (context, index) {
                            final reward = allRewards[index];
                            final data = reward.data() as Map<String, dynamic>;
                            final isGoalReward = data['goalId'] != null;
                            final isBonus = data['isBonus'] == true;
                            final cost = isBonus ? 0 : (data['pointCost'] ?? data['pointsCost'] ?? data['points'] ?? 0);
                            final name = data['name'] ?? data['title'] ?? 'Unnamed Reward';
                            final description = data['description'] ?? '';
                            final canAfford = isBonus || (currentPoints as num) >= cost;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (isGoalReward)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.flag, size: 14, color: Colors.teal.shade800),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Goal Reward',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (isBonus)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '⭐ BONUS',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.purple.shade800,
                                              ),
                                            ),
                                          ),
                                        const Spacer(),
                                        if (!canAfford && !isBonus)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Need $cost',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      name,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        description,
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: canAfford ? Colors.amber.shade100 : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            isBonus ? 'FREE' : '$cost points',
                                            style: TextStyle(
                                              color: canAfford ? Colors.amber.shade800 : Colors.grey.shade600,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: canAfford && !_isRedeeming
                                              ? () => _redeemReward(reward.id, data, isBonus: isBonus)
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isBonus
                                                ? Colors.purple
                                                : canAfford
                                                ? Colors.green
                                                : Colors.grey.shade400,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: _isRedeeming
                                              ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                              : Text(isBonus ? 'Claim!' : 'Redeem'),
                                        ),
                                      ],
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatPoints(dynamic points) {
    if (points == null) return '0';
    final double val = (points is num) ? points.toDouble() : 0.0;
    final rounded = double.parse(val.toStringAsFixed(2));
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    return rounded.toStringAsFixed(2);
  }

  Future<void> _claimWonReward(String wonRewardDocId, String rewardName, String childId, String? parentId, String childName) async {
    setState(() => _isClaiming = true);

    try {
      final wonRewardRef = FirebaseFirestore.instance
          .collection('users')
          .doc(childId)
          .collection('wonRewards')
          .doc(wonRewardDocId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.update(wonRewardRef, {
          'claimed': true,
          'claimedAt': FieldValue.serverTimestamp(),
        });

        final redemptionRef = FirebaseFirestore.instance.collection('redemptions').doc();
        transaction.set(redemptionRef, {
          'rewardId': wonRewardDocId,
          'rewardName': rewardName,
          'childId': childId,
          'childName': childName,
          'parentId': parentId,
          'pointCost': 0,
          'isBonus': true,
          'isWheelWin': true,
          'status': 'completed',
          'redeemedAt': FieldValue.serverTimestamp(),
          'completedAt': FieldValue.serverTimestamp(),
        });
      });

      if (parentId != null && parentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('notifications').add({
            'type': 'bonus_claimed',
            'title': '🎉 Wheel Bonus Claimed!',
            'message': '$childName claimed their wheel bonus: "$rewardName". Please prepare the tangible reward.',
            'parentId': parentId,
            'childId': childId,
            'childName': childName,
            'rewardName': rewardName,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          print('Notification failed: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Claimed "$rewardName"!'),
            backgroundColor: Colors.purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  Future<void> _redeemReward(String rewardId, Map<String, dynamic> reward, {required bool isBonus}) async {
    setState(() => _isRedeeming = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final cost = isBonus ? 0 : (reward['pointCost'] ?? reward['pointsCost'] ?? reward['points'] ?? 0);
      final rewardName = reward['name'] ?? reward['title'] ?? 'Reward';

      final childDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final childData = childDoc.data() as Map<String, dynamic>?;
      final parentId = childData?['parentId'] as String?;
      final childName = childData?['name'] ?? 'Child';
      final currentPoints = childData?['currentPoints'] ?? 0;

      if (!isBonus && (currentPoints as num) < cost) {
        throw Exception('Not enough points (need $cost, have $currentPoints)');
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        if (!isBonus) {
          transaction.update(childDoc.reference, {
            'currentPoints': FieldValue.increment(-cost),
          });
        }

        final redemptionRef = FirebaseFirestore.instance.collection('redemptions').doc();
        transaction.set(redemptionRef, {
          'rewardId': rewardId,
          'rewardName': rewardName,
          'childId': user.uid,
          'childName': childName,
          'parentId': parentId,
          'pointCost': cost,
          'isBonus': isBonus,
          'status': 'completed',
          'redeemedAt': FieldValue.serverTimestamp(),
          'completedAt': FieldValue.serverTimestamp(),
        });

        transaction.update(
          FirebaseFirestore.instance.collection('rewards').doc(rewardId),
          {'isAvailable': false, 'redeemedAt': FieldValue.serverTimestamp()},
        );
      });

      if (parentId != null && parentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('notifications').add({
            'type': isBonus ? 'bonus_redeemed' : 'reward_redeemed',
            'title': isBonus ? '🎉 Bonus Claimed!' : '🎁 Reward Redeemed',
            'message': '$childName redeemed "$rewardName" ${isBonus ? '(FREE)' : 'for $cost points'}. Please prepare the tangible reward.',
            'parentId': parentId,
            'childId': user.uid,
            'childName': childName,
            'rewardName': rewardName,
            'pointCost': cost,
            'isBonus': isBonus,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          print('Notification failed: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBonus
                ? '🎉 Bonus reward "$rewardName" claimed!'
                : '✅ "$rewardName" redeemed for $cost points!'),
            backgroundColor: isBonus ? Colors.purple : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }
}