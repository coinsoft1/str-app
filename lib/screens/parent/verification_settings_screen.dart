// lib/screens/parent/verification_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/trust_ladder_service.dart';

class VerificationSettingsScreen extends StatefulWidget {
  const VerificationSettingsScreen({super.key});

  @override
  State<VerificationSettingsScreen> createState() => _VerificationSettingsScreenState();
}

class _VerificationSettingsScreenState extends State<VerificationSettingsScreen> {
  String _currentMode = 'daily_glance';
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, Map<String, dynamic>> _modes = {
    'auto_pilot': {
      'title': '🤖 Auto-Pilot',
      'subtitle': 'Minimal effort',
      'description': 'System auto-approves logs after 5 consecutive accurate entries. You get a weekly summary only.',
      'effort': '~0 seconds/day',
      'color': Colors.green,
      'icon': Icons.auto_mode,
    },
    'daily_glance': {
      'title': '👁️ Daily Glance',
      'subtitle': 'Recommended',
      'description': 'One notification at 8 PM to review all logs for the day. One tap to approve.',
      'effort': '~10 seconds/day',
      'color': Colors.blue,
      'icon': Icons.remove_red_eye,
    },
    'active_monitor': {
      'title': '🔍 Active Monitor',
      'subtitle': 'High engagement',
      'description': 'Real-time notification for every log. Review each one individually.',
      'effort': '~2-5 minutes/day',
      'color': Colors.orange,
      'icon': Icons.visibility,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
  }

  Future<void> _loadCurrentMode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final mode = await TrustLadderService.getParentVerificationMode(user.uid);
    setState(() {
      _currentMode = mode;
      _isLoading = false;
    });
  }

  Future<void> _saveMode(String mode) async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await TrustLadderService.setParentVerificationMode(user.uid, mode);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('modeChangeHistory')
          .add({
        'fromMode': _currentMode,
        'toMode': mode,
        'timestamp': Timestamp.now(),
      });

      setState(() => _currentMode = mode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_modes[mode]!['title']} mode activated'),
            backgroundColor: _modes[mode]!['color'],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Verification Settings'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.amber.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These settings control how you review your child\'s screen time logs. You can change this anytime.',
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Choose Your Involvement Level',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._modes.entries.map((entry) {
              final mode = entry.key;
              final info = entry.value;
              final isSelected = _currentMode == mode;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: isSelected ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isSelected
                      ? BorderSide(color: info['color'] as Color, width: 2)
                      : BorderSide.none,
                ),
                child: InkWell(
                  onTap: _isSaving ? null : () => _saveMode(mode),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (info['color'] as Color).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                info['icon'] as IconData,
                                color: info['color'] as Color,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    info['subtitle'] as String,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (info['color'] as Color).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_circle,
                                  color: info['color'] as Color,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          info['description'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Parent effort: ${info['effort']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            _buildTrustStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustStatsSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('parentId', isEqualTo: user.uid)
          .where('role', isEqualTo: 'child')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final children = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Children Trust Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children.map((child) {
              final childId = child.id;

              // ROBUST FIX: Explicit cast from Object? to Map
              final rawData = child.data();
              final Map<String, dynamic> childData = (rawData is Map<String, dynamic>) ? rawData : {};
              final childName = childData['displayName'] ?? childData['name'] ?? 'Child';

              return FutureBuilder<Map<String, dynamic>>(
                future: TrustLadderService.getTrustStats(childId),
                builder: (context, trustSnapshot) {
                  if (!trustSnapshot.hasData) {
                    return Card(
                      child: ListTile(
                        title: Text(childName),
                        trailing: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  final stats = trustSnapshot.data!;
                  final tier = stats['currentTier'] ?? 'daily_glance';
                  final streak = stats['accuracyStreak'] ?? 0;
                  final totalLogs = stats['totalLogs'] ?? 0;

                  Color tierColor;
                  IconData tierIcon;
                  switch (tier) {
                    case 'auto_pilot':
                      tierColor = Colors.green;
                      tierIcon = Icons.auto_mode;
                      break;
                    case 'active_monitor':
                      tierColor = Colors.orange;
                      tierIcon = Icons.visibility;
                      break;
                    default:
                      tierColor = Colors.blue;
                      tierIcon = Icons.remove_red_eye;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tierColor.withOpacity(0.1),
                        child: Icon(tierIcon, color: tierColor),
                      ),
                      title: Text(childName),
                      subtitle: Text('$totalLogs logs • $streak streak'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: tierColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tier.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }
}