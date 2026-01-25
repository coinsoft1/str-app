import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RedeemRewardsScreen extends StatefulWidget {
  const RedeemRewardsScreen({super.key});

  @override
  State<RedeemRewardsScreen> createState() => _RedeemRewardsScreenState();
}

class _RedeemRewardsScreenState extends State<RedeemRewardsScreen> {
  bool _isRedeeming = false;

  Future<void> _redeemReward(Map<String, dynamic> reward) async {
    setState(() => _isRedeeming = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // Check if child has enough points
      final childDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final childData = childDoc.data() as Map<String, dynamic>?;
      final currentPoints = childData?['currentPoints'] ?? 0;
      final cost = reward['pointCost'] ?? 0;

      if (currentPoints < cost) {
        throw Exception('Not enough points (need $cost, have $currentPoints)');
      }

      // Create redemption transaction
      final batch = FirebaseFirestore.instance.batch();
      
      // Deduct points from child
      final childRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      batch.update(childRef, {
        'currentPoints': FieldValue.increment(-cost),
      });
      
      // Create redemption record
      final redemptionRef = FirebaseFirestore.instance.collection('redemptions').doc();
      batch.set(redemptionRef, {
        'rewardId': reward['id'],
        'rewardName': reward['name'],
        'childId': user.uid,
        'childName': childData?['name'],
        'pointCost': cost,
        'status': 'pending', // Parent must approve
        'requestedAt': FieldValue.serverTimestamp(),
      });
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Redemption requested! ${reward['name']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem Rewards')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
          final currentPoints = userData?['currentPoints'] ?? 0;
          final familyId = userData?['familyId'];

          return Column(
            children: [
              // Points display
              Card(
                margin: const EdgeInsets.all(16),
                color: Colors.green[50],
                child: ListTile(
                  leading: const Icon(Icons.star, color: Colors.green),
                  title: const Text('Available Points'),
                  trailing: Text(
                    '$currentPoints',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              // Rewards list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rewards')
                      .where('familyId', isEqualTo: familyId) // Show family rewards
                      .where('isActive', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    if (snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.card_giftcard, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No rewards available yet'),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final reward = snapshot.data!.docs[index];
                        final data = reward.data() as Map<String, dynamic>;
                        final cost = data['pointCost'] ?? 0;
                        final canAfford = currentPoints >= cost;

                        return Card(
                          child: ListTile(
                            title: Text(data['name'] ?? 'Unnamed Reward'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['description'] ?? ''),
                                const SizedBox(height: 4),
                                Text(
                                  'Cost: $cost points',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: canAfford ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            trailing: _isRedeeming
                                ? const CircularProgressIndicator()
                                : ElevatedButton(
                                    onPressed: canAfford ? () => _redeemReward(data) : null,
                                    child: const Text('Redeem'),
                                  ),
                          ),
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
}