// lib/widgets/reward_wheel_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class RewardWheelWidget extends StatefulWidget {
  final String childId;

  const RewardWheelWidget({super.key, required this.childId});

  @override
  State<RewardWheelWidget> createState() => _RewardWheelWidgetState();
}

class _RewardWheelWidgetState extends State<RewardWheelWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentRotation = 0;
  List<Map<String, dynamic>> _rewards = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  String? _lastRewardIdsHash;
  String? _familyId;
  bool _isLoadingFamily = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _loadFamilyId();
  }

  Future<void> _loadFamilyId() async {
    try {
      debugPrint('Loading familyId for child ${widget.childId}');
      final childDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();

      if (childDoc.exists) {
        final data = childDoc.data();
        setState(() {
          _familyId = data?['familyId'];
          _isLoadingFamily = false;
        });
        debugPrint('FamilyId loaded: $_familyId');
      } else {
        debugPrint('Child document not found!');
        setState(() => _isLoadingFamily = false);
      }
    } catch (e) {
      debugPrint('Error loading familyId: $e');
      setState(() => _isLoadingFamily = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRewardsIfNeeded(List<String> rewardIds) async {
    final currentHash = rewardIds.join(',');

    if (_isLoading || (_hasLoaded && _lastRewardIdsHash == currentHash)) {
      return;
    }

    if (rewardIds.isEmpty) {
      setState(() {
        _rewards = [];
        _hasLoaded = true;
        _errorMessage = 'No rewards configured';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<Map<String, dynamic>> loadedRewards = [];

      for (final id in rewardIds) {
        try {
          DocumentSnapshot doc = await FirebaseFirestore.instance
              .collection('rewards')
              .doc(id)
              .get();

          if (!doc.exists && id.startsWith('sys_')) {
            debugPrint('Reward $id not found by ID, trying fallback query...');
            Query query = FirebaseFirestore.instance
                .collection('rewards')
                .where('systemDefaultId', isEqualTo: id);
            if (_familyId != null) {
              query = query.where('familyId', isEqualTo: _familyId);
            }
            final fallback = await query.limit(1).get();
            if (fallback.docs.isNotEmpty) {
              doc = fallback.docs.first;
              debugPrint('Found fallback doc for $id: ${doc.id}');
            }
          }

          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            loadedRewards.add({
              'id': doc.id,
              'name': data['name'] ?? data['title'] ?? 'Prize',
              'description': data['description'] ?? '',
              'fullData': data,
            });
          } else {
            debugPrint('Reward $id not found in Firestore');
          }
        } catch (e) {
          print('Error loading reward $id: $e');
        }
      }

      if (mounted) {
        setState(() {
          _rewards = loadedRewards;
          _isLoading = false;
          _hasLoaded = true;
          _lastRewardIdsHash = currentHash;

          if (loadedRewards.isEmpty) {
            _errorMessage = 'No valid rewards found';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
          _errorMessage = 'Failed to load: $e';
        });
      }
    }
  }

  Stream<DocumentSnapshot?> _getWheelConfigStream() {
    if (_familyId == null) {
      debugPrint('FamilyId is null, cannot stream config');
      return Stream.value(null);
    }

    debugPrint('Streaming wheel config for child: ${widget.childId}, family: $_familyId');

    return FirebaseFirestore.instance
        .collection('wheelConfigurations')
        .doc(widget.childId)
        .snapshots()
        .asyncMap((childConfig) async {
      debugPrint('Checking specific config for ${widget.childId}: exists=${childConfig.exists}');

      if (childConfig.exists) {
        final data = childConfig.data() as Map<String, dynamic>?;
        if (data != null && data['isEnabled'] == true) {
          debugPrint('Using specific child config');
          return childConfig;
        } else {
          debugPrint('Child config exists but is disabled');
        }
      }

      final allChildrenDocId = '${_familyId}_all_children';
      debugPrint('Checking all children config: $allChildrenDocId');

      final allChildrenConfig = await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(allChildrenDocId)
          .get();

      debugPrint('All children config exists: ${allChildrenConfig.exists}');

      if (allChildrenConfig.exists) {
        final allData = allChildrenConfig.data() as Map<String, dynamic>?;
        if (allData != null && allData['isEnabled'] == true) {
          debugPrint('Using all children config');
          return allChildrenConfig;
        } else {
          debugPrint('All children config exists but is disabled');
        }
      }

      debugPrint('No valid wheel config found');
      return childConfig;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFamily) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_familyId == null) {
      debugPrint('Warning: familyId is null');
    }

    return StreamBuilder<DocumentSnapshot?>(
      stream: _getWheelConfigStream(),
      builder: (context, snapshot) {
        debugPrint('StreamBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint('Wheel config error: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        final configDoc = snapshot.data;

        if (configDoc == null || !configDoc.exists) {
          debugPrint('No wheel config document found');
          return const SizedBox.shrink();
        }

        final data = configDoc.data() as Map<String, dynamic>?;

        if (data == null) {
          debugPrint('Config document data is null');
          return const SizedBox.shrink();
        }

        final isEnabled = data['isEnabled'] == true;
        final deadline = (data['deadline'] as Timestamp?)?.toDate();
        final hasSpun = data['hasBeenSpun'] == true;
        final rewardIds = List<String>.from(data['rewardIds'] ?? []);
        final now = DateTime.now();

        debugPrint('Config check: isEnabled=$isEnabled, deadline=$deadline, rewardCount=${rewardIds.length}');

        if (!isEnabled) {
          debugPrint('Wheel disabled');
          return const SizedBox.shrink();
        }

        if (deadline == null || deadline.isBefore(now)) {
          debugPrint('Wheel expired or no deadline');
          return const SizedBox.shrink();
        }

        if (rewardIds.length < 2) {
          debugPrint('Wheel has < 2 rewards');
          return const SizedBox.shrink();
        }

        if (!_hasLoaded || _lastRewardIdsHash != rewardIds.join(',')) {
          Future.microtask(() => _loadRewardsIfNeeded(rewardIds));
        }

        if (_isLoading) {
          return const Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (_errorMessage != null || _rewards.isEmpty) {
          debugPrint('Error or no rewards: $_errorMessage');
          return const SizedBox.shrink();
        }

        final canSpin = !hasSpun;

        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.card_giftcard, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      'Bonus Reward Wheel',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  'Spin until: ${DateFormat('MMM dd, HH:mm').format(deadline)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _currentRotation * _animation.value,
                            child: CustomPaint(
                              size: const Size(200, 200),
                              painter: WheelPainter(_rewards),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.touch_app, color: Colors.purple, size: 20),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (canSpin)
                  ElevatedButton.icon(
                    onPressed: _spinWheel,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('SPIN FOR BONUS!'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bonus already claimed! Check Rewards tab',
                            style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _spinWheel() async {
    if (_rewards.isEmpty) return;

    final random = Random();
    final spinCount = 3 + random.nextInt(3);
    final segmentAngle = 2 * 3.14159 / _rewards.length;
    final winningIndex = random.nextInt(_rewards.length);
    final targetAngle = spinCount * 2 * 3.14159 + (winningIndex * segmentAngle);

    setState(() => _currentRotation = targetAngle);

    await _controller.animateTo(1.0, curve: Curves.easeOutExpo);

    final reward = _rewards[winningIndex];

    try {
      String configDocId;

      final childConfig = await FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(widget.childId)
          .get();

      if (childConfig.exists && (childConfig.data()?['isEnabled'] == true)) {
        configDocId = widget.childId;
        debugPrint('Spinning: Using specific child config');
      } else {
        configDocId = '${_familyId}_all_children';
        debugPrint('Spinning: Using all children config: $configDocId');
      }

      final configRef = FirebaseFirestore.instance
          .collection('wheelConfigurations')
          .doc(configDocId);

      final wonRewardRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('wonRewards')
          .doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.update(configRef, {
          'hasBeenSpun': true,
          'spunAt': FieldValue.serverTimestamp(),
          'lastWin': reward['name'],
        });

        transaction.set(wonRewardRef, {
          'rewardName': reward['name'],
          'rewardId': reward['id'],
          'rewardData': reward['fullData'],
          'wonAt': FieldValue.serverTimestamp(),
          'claimed': false,
          'isBonus': true,
        });
      });

      debugPrint('Spin completed successfully');

      // NEW: Send notification to parent immediately on win
      try {
        final childDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.childId)
            .get();
        final childData = childDoc.data() as Map<String, dynamic>?;
        final parentId = childData?['parentId'] as String?;
        final childName = childData?['name'] ?? childData?['username'] ?? 'Your child';

        if (parentId != null && parentId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'type': 'wheel_win',
            'title': '🎉 $childName won a wheel bonus!',
            'message': '$childName won "${reward['name']}" from the bonus wheel. They can claim it in their Rewards tab.',
            'parentId': parentId,
            'childId': widget.childId,
            'childName': childName,
            'rewardName': reward['name'],
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          debugPrint('Parent notification sent for wheel win');
        }
      } catch (e) {
        debugPrint('Failed to send parent notification: $e');
      }

      if (mounted) {
        _showGiftBoxDialog(reward);
      }
    } catch (e) {
      debugPrint('Error during spin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showGiftBoxDialog(Map<String, dynamic> reward) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GiftBoxRevealDialog(
        rewardName: reward['name'] as String,
        description: reward['description'] as String? ?? '',
        onClose: () {
          Navigator.pop(ctx);
          _controller.reset();
        },
      ),
    );
  }
}

class GiftBoxRevealDialog extends StatefulWidget {
  final String rewardName;
  final String description;
  final VoidCallback onClose;

  const GiftBoxRevealDialog({
    super.key,
    required this.rewardName,
    required this.description,
    required this.onClose,
  });

  @override
  State<GiftBoxRevealDialog> createState() => _GiftBoxRevealDialogState();
}

class _GiftBoxRevealDialogState extends State<GiftBoxRevealDialog>
    with TickerProviderStateMixin {
  late AnimationController _boxController;
  late AnimationController _bounceController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _openAnimation;
  late Animation<double> _bounceAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();

    _boxController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: -0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: 0), weight: 1),
    ]).animate(_boxController);

    _openAnimation = CurvedAnimation(
      parent: _boxController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutBack),
    );

    _bounceAnimation = CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    );

    _startAnimation();
  }

  void _startAnimation() async {
    await _boxController.forward();
    setState(() => _isOpen = true);

    await Future.delayed(const Duration(milliseconds: 200));
    _bounceController.forward();
  }

  @override
  void dispose() {
    _boxController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🎉 You Won! 🎉',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'BONUS REWARD',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 20),

            AnimatedBuilder(
              animation: Listenable.merge([_boxController, _bounceController]),
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isOpen)
                      Transform.scale(
                        scale: _bounceAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber, width: 3),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.card_giftcard,
                                size: 48,
                                color: Colors.amber,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.rewardName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (widget.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  widget.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    if (!_isOpen || _openAnimation.value < 1)
                      Opacity(
                        opacity: 1 - _openAnimation.value,
                        child: Transform.rotate(
                          angle: _shakeAnimation.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.card_giftcard,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Go to "Rewards" tab to claim your bonus!\n(No points needed)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.check_circle),
              label: const Text('Got it!'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WheelPainter extends CustomPainter {
  final List<Map<String, dynamic>> rewards;
  WheelPainter(this.rewards);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = 2 * 3.14159 / rewards.length;
    final colors = [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple];

    for (int i = 0; i < rewards.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      final startAngle = i * segmentAngle - 3.14159 / 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );
    }

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}