// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/settings_service.dart';
import '../widgets/color_picker.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() => _userRole = doc.data()?['role'] as String?);
      }
    } catch (e) {
      debugPrint('Error loading role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              _buildSectionTitle('Appearance'),
              _buildThemeTile(),
              _buildAccentColorTile(),
              _buildFontSizeTile(),
              const Divider(),
              _buildSectionTitle('Accessibility'),
              _buildSwitchTile(
                'Reduce Motion',
                'Disable animations for wheel spin and transitions',
                Icons.animation,
                _settings.reducedMotion,
                    (v) => _settings.reducedMotion = v,
              ),
              _buildSwitchTile(
                'High Contrast',
                'Increase contrast for better visibility',
                Icons.contrast,
                _settings.highContrast,
                    (v) => _settings.highContrast = v,
              ),
              _buildSwitchTile(
                'Color Blind Friendly',
                'Use patterns and icons instead of color alone',
                Icons.palette,
                _settings.colorBlindMode,
                    (v) => _settings.colorBlindMode = v,
              ),
              _buildSwitchTile(
                'Distraction-Free Mode',
                'Hide wheel and non-essential cards',
                Icons.do_not_disturb,
                _settings.distractionFreeMode,
                    (v) => _settings.distractionFreeMode = v,
              ),
              const Divider(),
              _buildSectionTitle('Notifications'),
              _buildSwitchTile(
                'Sound Effects',
                'Play sounds for wheel spins and rewards',
                Icons.volume_up,
                _settings.soundEnabled,
                    (v) => _settings.soundEnabled = v,
              ),
              _buildSwitchTile(
                'Haptic Feedback',
                'Vibrate on button presses and wheel spins',
                Icons.vibration,
                _settings.hapticEnabled,
                    (v) => _settings.hapticEnabled = v,
              ),
              if (_userRole == 'parent') ...[
                const Divider(),
                _buildSectionTitle('Parent Preferences'),
                _buildPointsPerVerifyTile(),
                _buildPointsPerCorrectTile(),
              ],
              if (_userRole == 'child') ...[
                const Divider(),
                _buildSectionTitle('Child Profile'),
                _buildAvatarTile(),
                _buildSwitchTile(
                  'Show Goal Update Banner',
                  'Display banner when parent updates your goal',
                  Icons.notifications_active,
                  _settings.goalBannerEnabled,
                      (v) => _settings.goalBannerEnabled = v,
                ),
                _buildWheelSpeedTile(),
              ],
              const Divider(),
              _buildSectionTitle('About'),
              _buildAboutTile(),
              _buildReplayOnboardingTile(),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildThemeTile() {
    final labels = {
      'system': 'System Default',
      'light': 'Light',
      'dark': 'Dark',
      'auto': 'Auto (Time-based)',
    };
    return ListTile(
      leading: const Icon(Icons.brightness_6),
      title: const Text('Theme'),
      subtitle: Text(labels[_settings.themeModeString] ?? 'System Default'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemePicker(),
    );
  }

  void _showThemePicker() {
    final labels = {
      'system': 'System Default',
      'light': 'Light',
      'dark': 'Dark',
      'auto': 'Auto (Time-based)',
    };
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: labels.entries.map((e) {
            return RadioListTile<String>(
              title: Text(e.value),
              value: e.key,
              groupValue: _settings.themeModeString,
              onChanged: (v) {
                if (v != null) {
                  _settings.themeModeString = v;
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAccentColorTile() {
    final current = _settings.accentColor;
    final preset = SettingsService.presetColors.firstWhere(
          (p) => (p['color'] as Color).value == current.value,
      orElse: () => {'name': 'Custom', 'color': current},
    );
    return ListTile(
      leading: const Icon(Icons.color_lens),
      title: const Text('Accent Color'),
      subtitle: Text(preset['name'] as String),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: current,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300),
        ),
      ),
      onTap: () => _showColorPicker(),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Accent Color'),
        content: SingleChildScrollView(
          child: ColorPickerGrid(
            selectedColor: _settings.accentColor,
            onColorSelected: (color) {
              _settings.accentColor = color;
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFontSizeTile() {
    final labels = {'normal': 'Normal', 'large': 'Large', 'extra_large': 'Extra Large'};
    return ListTile(
      leading: const Icon(Icons.text_fields),
      title: const Text('Font Size'),
      subtitle: Text(labels[_settings.fontSize] ?? 'Normal'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showFontSizePicker(),
    );
  }

  void _showFontSizePicker() {
    final labels = {'normal': 'Normal', 'large': 'Large', 'extra_large': 'Extra Large'};
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Font Size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: labels.entries.map((e) {
            return RadioListTile<String>(
              title: Text(e.value),
              value: e.key,
              groupValue: _settings.fontSize,
              onChanged: (v) {
                if (v != null) {
                  _settings.fontSize = v;
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title,
      String subtitle,
      IconData icon,
      bool value,
      ValueChanged<bool> onChanged,
      ) {
    return Semantics(
      label: '$title, $subtitle, currently ${value ? 'on' : 'off'}',
      toggled: value,
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildPointsPerVerifyTile() {
    final pts = _settings.pointsPerVerify;
    final label = pts == pts.toInt() ? '${pts.toInt()}' : '$pts';
    return ListTile(
      leading: const Icon(Icons.check_circle),
      title: const Text('Points per Verified Log'),
      subtitle: Text('$label points'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPointsPicker('verify'),
    );
  }

  Widget _buildPointsPerCorrectTile() {
    final pts = _settings.pointsPerCorrect;
    final label = pts == pts.toInt() ? '${pts.toInt()}' : '$pts';
    return ListTile(
      leading: const Icon(Icons.edit),
      title: const Text('Points per Corrected Log'),
      subtitle: Text('$label points'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPointsPicker('correct'),
    );
  }

  void _showPointsPicker(String type) {
    final options = [0.0, 0.5, 1.0, 2.0, 3.0, 5.0];
    final title = type == 'verify' ? 'Points per Verified Log' : 'Points per Corrected Log';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((pts) {
            final label = pts == pts.toInt() ? '${pts.toInt()}' : '$pts';
            return RadioListTile<double>(
              title: Text('$label points'),
              value: pts,
              groupValue: type == 'verify' ? _settings.pointsPerVerify : _settings.pointsPerCorrect,
              onChanged: (v) {
                if (v != null) {
                  if (type == 'verify') {
                    _settings.pointsPerVerify = v;
                  } else {
                    _settings.pointsPerCorrect = v;
                  }
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAvatarTile() {
    return ListTile(
      leading: const Icon(Icons.emoji_emotions),
      title: const Text('Avatar'),
      subtitle: Text(_settings.childAvatar),
      trailing: Text(_settings.childAvatar, style: const TextStyle(fontSize: 24)),
      onTap: () => _showAvatarPicker(),
    );
  }

  void _showAvatarPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Avatar'),
        content: SingleChildScrollView(
          child: AvatarPickerGrid(
            selectedAvatar: _settings.childAvatar,
            onAvatarSelected: (avatar) {
              _settings.childAvatar = avatar;
              _updateFirestoreAvatar(avatar);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _updateFirestoreAvatar(String avatar) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'avatar': avatar});
    } catch (e) {
      debugPrint('Error updating avatar: $e');
    }
  }

  Widget _buildWheelSpeedTile() {
    final labels = {'normal': 'Normal', 'fast': 'Fast'};
    return ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('Wheel Spin Speed'),
      subtitle: Text(labels[_settings.wheelSpeed] ?? 'Normal'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showWheelSpeedPicker(),
    );
  }

  void _showWheelSpeedPicker() {
    final labels = {'normal': 'Normal', 'fast': 'Fast'};
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wheel Spin Speed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: labels.entries.map((e) {
            return RadioListTile<String>(
              title: Text(e.value),
              value: e.key,
              groupValue: _settings.wheelSpeed,
              onChanged: (v) {
                if (v != null) {
                  _settings.wheelSpeed = v;
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAboutTile() {
    return const ListTile(
      leading: Icon(Icons.info),
      title: Text('Version'),
      subtitle: Text('1.0.0+1'),
    );
  }

  Widget _buildReplayOnboardingTile() {
    return ListTile(
      leading: const Icon(Icons.replay),
      title: const Text('Replay Tutorial'),
      subtitle: const Text('Watch the onboarding guide again'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showReplayConfirmation(),
    );
  }

  void _showReplayConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replay Tutorial?'),
        content: const Text('This will replay the onboarding guide now.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'hasSeenOnboarding': false});
              }
              Navigator.pop(context);
              _launchOnboarding();
            },
            child: const Text('Replay'),
          ),
        ],
      ),
    );
  }

  void _launchOnboarding() {
    final isParent = _userRole == 'parent';

    final pages = isParent ? [
      OnboardingPage(
        title: 'Set Goals & Limits',
        description: 'Create screen time goals for your children. Set daily limits and choose rewards they can earn by staying within bounds.',
        icon: Icons.flag,
        color: Colors.teal,
      ),
      OnboardingPage(
        title: 'Assign Tasks',
        description: 'Create tasks like homework, chores, or reading. Each completed task earns points toward rewards.',
        icon: Icons.checklist,
        color: Colors.blue,
      ),
      OnboardingPage(
        title: 'Review & Verify',
        description: 'Your child logs their own screen time. You review and verify entries to build trust and accountability.',
        icon: Icons.verified_user,
        color: Colors.orange,
      ),
      OnboardingPage(
        title: 'Analytics & Reports',
        description: 'Track educational vs entertainment usage over time. Export weekly or monthly reports to see progress.',
        icon: Icons.analytics,
        color: Colors.indigo,
      ),
      OnboardingPage(
        title: 'Stay Notified',
        description: 'Get instant alerts when your child completes tasks, redeems rewards, or wins bonus spins on the reward wheel.',
        icon: Icons.notifications,
        color: Colors.green,
      ),
    ] : [
      OnboardingPage(
        title: 'Log Time',
        description: 'Track your daily screen time usage honestly to earn points.',
        icon: Icons.timer,
        color: Colors.blue,
      ),
      OnboardingPage(
        title: 'Tasks',
        description: 'Complete tasks assigned by your parent to earn rewards.',
        icon: Icons.checklist,
        color: Colors.green,
      ),
      OnboardingPage(
        title: 'Wheel',
        description: 'Spin the reward wheel for a chance to win bonus points!',
        icon: Icons.casino,
        color: Colors.purple,
      ),
      OnboardingPage(
        title: 'Rewards',
        description: 'Redeem your points for exciting rewards from your parent.',
        icon: Icons.card_giftcard,
        color: Colors.amber,
      ),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          pages: pages,
          onComplete: () => Navigator.pop(context),
          onSkip: () => Navigator.pop(context),
          completeButtonText: 'Done',
        ),
      ),
    );
  }
}