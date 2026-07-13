// lib/screens/child/session_logging_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/trust_ladder_service.dart';

class SessionLoggingScreen extends StatefulWidget {
  const SessionLoggingScreen({super.key});

  @override
  State<SessionLoggingScreen> createState() => _SessionLoggingScreenState();
}

class _SessionLoggingScreenState extends State<SessionLoggingScreen> {
  String _selectedCategory = 'Educational';
  String _selectedApp = '';
  String _dropdownApp = '';
  final TextEditingController _customAppController = TextEditingController();
  int? _selectedDuration;
  bool _isSubmitting = false;

  final List<String> _topEducationalApps = [
    'Khan Academy', 'Duolingo', 'Coursera', 'Quizlet', 'Photomath',
    'BBC Bitesize', 'National Geographic Kids', 'PBS Kids', 'Scratch', 'YouTube',
  ];

  final List<String> _moreEducationalApps = [
    'Google Classroom', 'Epic!', 'ABCmouse', 'Starfall', 'CK-12',
    'Wolfram Alpha', 'NASA App', 'ReadingIQ', 'Moodle', 'Canvas', 'Other',
  ];

  final List<String> _topEntertainmentApps = [
    'TikTok', 'Roblox', 'Minecraft', 'Netflix', 'Disney+',
    'Instagram', 'Snapchat', 'Fortnite', 'Spotify', 'YouTube',
  ];

  final List<String> _moreEntertainmentApps = [
    'Twitch', 'Discord', 'Reddit', 'Pinterest', 'Hulu',
    'Amazon Prime', 'HBO Max', 'Apple TV+', 'Paramount+', 'Peacock', 'Other',
  ];

  final List<int> _durationOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  List<String> get _currentTopApps {
    return _selectedCategory == 'Educational' ? _topEducationalApps : _topEntertainmentApps;
  }

  List<String> get _currentMoreApps {
    return _selectedCategory == 'Educational' ? _moreEducationalApps : _moreEntertainmentApps;
  }

  @override
  void dispose() {
    _customAppController.dispose();
    super.dispose();
  }

  Future<void> _submitLog() async {
    String appName;
    if (_selectedApp.isNotEmpty) {
      appName = _selectedApp;
    } else if (_dropdownApp == 'Other') {
      appName = _customAppController.text.trim();
      if (appName.isEmpty) {
        _showError('Please enter the app name');
        return;
      }
    } else if (_dropdownApp.isNotEmpty) {
      appName = _dropdownApp;
    } else {
      _showError('Please select an app');
      return;
    }

    if (_selectedDuration == null) {
      _showError('Please select duration');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final childDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final parentId = childDoc.data()?['parentId'] as String?;
      if (parentId == null) throw Exception('No parent assigned');

      final endTime = DateTime.now();
      final startTime = endTime.subtract(Duration(minutes: _selectedDuration!));

      final result = await TrustLadderService.submitSessionLog(
        childId: user.uid,
        parentId: parentId,
        appName: appName,
        category: _selectedCategory,
        durationMinutes: _selectedDuration!,
        startTime: startTime,
        endTime: endTime,
        platform: 'android',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Log submitted! ${result['message']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        setState(() {
          _selectedApp = '';
          _dropdownApp = '';
          _customAppController.clear();
          _selectedDuration = null;
        });

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Log Screen Time'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quickly log what you just used. Takes 10 seconds!',
                      style: TextStyle(color: Colors.teal.shade800, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Category Selection
            const Text('What type of use?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: ['Educational', 'Entertainment'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat;
                        _selectedApp = '';
                        _dropdownApp = '';
                        _customAppController.clear();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? _getCategoryColor(cat) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? _getCategoryColor(cat) : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _getCategoryIcon(cat),
                            color: isSelected ? Colors.white : _getCategoryColor(cat),
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            cat,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Contextual Nudge for Entertainment
            if (_selectedCategory == 'Entertainment') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '💡 Remember: completing your goal tasks earns you points for rewards! Less entertainment = more time for fun activities.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Encouragement for Educational
            if (_selectedCategory == 'Educational') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.school, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '📚 Great choice! Educational time counts toward your goals. Keep learning!',
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // App Selection
            Text(
              _selectedCategory == 'Educational'
                  ? 'Popular Educational Apps'
                  : 'Popular Entertainment Apps',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _currentTopApps.map((app) {
                final isSelected = _selectedApp == app;
                return ChoiceChip(
                  label: Text(app),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedApp = app;
                        _dropdownApp = '';
                        _customAppController.clear();
                      } else {
                        _selectedApp = '';
                      }
                    });
                  },
                  selectedColor: _getCategoryColor(_selectedCategory).withOpacity(0.2),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? _getCategoryColor(_selectedCategory) : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? _getCategoryColor(_selectedCategory) : Colors.grey.shade300,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // More Apps Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('More apps...'),
                  value: _dropdownApp.isNotEmpty ? _dropdownApp : null,
                  items: _currentMoreApps.map((app) {
                    return DropdownMenuItem(value: app, child: Text(app));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _dropdownApp = value ?? '';
                      _selectedApp = '';
                      if (value != 'Other') _customAppController.clear();
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (_dropdownApp == 'Other') ...[
              TextField(
                controller: _customAppController,
                decoration: InputDecoration(
                  hintText: 'Enter app name',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.edit),
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 24),

            // Duration Selection
            const Text('How long did you use it?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  hint: const Text('Select duration...'),
                  value: _selectedDuration,
                  items: _durationOptions.map((mins) {
                    return DropdownMenuItem(value: mins, child: Text('$mins minutes'));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedDuration = value),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitLog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                child: _isSubmitting
                    ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Submitting...'),
                  ],
                )
                    : const Text('Submit Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Educational': return Colors.blue;
      case 'Entertainment': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Educational': return Icons.school;
      case 'Entertainment': return Icons.videogame_asset;
      default: return Icons.devices;
    }
  }
}