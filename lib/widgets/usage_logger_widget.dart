import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/usage_entry.dart';
import '../services/usage_tracking_service.dart';

class UsageLoggerWidget extends StatefulWidget {
  final String childId;
  final VoidCallback? onSubmitted;

  const UsageLoggerWidget({
    super.key,
    required this.childId,
    this.onSubmitted,
  });

  @override
  State<UsageLoggerWidget> createState() => _UsageLoggerWidgetState();
}

class _UsageLoggerWidgetState extends State<UsageLoggerWidget>
    with SingleTickerProviderStateMixin {
  final _service = UsageTrackingService();
  final _appController = TextEditingController();
  final _notesController = TextEditingController();
  final _customAppController = TextEditingController();
  
  int _duration = 30;
  // CHANGED: Default to educational instead of entertainment
  UsageCategory _selectedCategory = UsageCategory.educational;
  bool _isSubmitting = false;
  bool _showCustomInput = false;
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  // Predefined app lists with icons
  final Map<UsageCategory, List<Map<String, dynamic>>> _categoryApps = {
    UsageCategory.educational: [
      {'name': 'Khan Academy', 'icon': Icons.school},
      {'name': 'Duolingo', 'icon': Icons.language},
      {'name': 'Google Classroom', 'icon': Icons.class_},
      {'name': 'BrainPOP', 'icon': Icons.lightbulb},
      {'name': 'PBS Kids', 'icon': Icons.tv},
      {'name': 'Scratch Jr', 'icon': Icons.code},
      {'name': 'Google Docs', 'icon': Icons.description},
      {'name': 'Zoom', 'icon': Icons.video_call},
      {'name': 'Epic Books', 'icon': Icons.menu_book},
      {'name': 'Kindle', 'icon': Icons.book},
    ],
    UsageCategory.entertainment: [
      {'name': 'YouTube', 'icon': Icons.play_circle_filled},
      {'name': 'Netflix', 'icon': Icons.movie},
      {'name': 'TikTok', 'icon': Icons.music_note},
      {'name': 'Instagram', 'icon': Icons.camera_alt},
      {'name': 'Roblox', 'icon': Icons.videogame_asset},
      {'name': 'Minecraft', 'icon': Icons.landscape},
      {'name': 'Spotify', 'icon': Icons.audiotrack},
      {'name': 'Disney+', 'icon': Icons.star},
      {'name': 'Twitch', 'icon': Icons.live_tv},
      {'name': 'Discord', 'icon': Icons.chat},
    ],
    UsageCategory.utility: [
      {'name': 'Phone Call', 'icon': Icons.phone},
      {'name': 'Messages', 'icon': Icons.message},
      {'name': 'Camera', 'icon': Icons.camera},
      {'name': 'Calculator', 'icon': Icons.calculate},
      {'name': 'Maps', 'icon': Icons.map},
      {'name': 'Email', 'icon': Icons.email},
      {'name': 'Clock', 'icon': Icons.alarm},
      {'name': 'Settings', 'icon': Icons.settings},
    ],
  };

  final Map<UsageCategory, Map<String, dynamic>> _categoryThemes = {
    UsageCategory.educational: {
      'color': Colors.green,
      'gradient': [Colors.green.shade400, Colors.teal.shade400],
      'icon': Icons.school,
      'title': 'Learning Time',
      'subtitle': 'Great job learning! 📚',
    },
    UsageCategory.entertainment: {
      'color': Colors.orange,
      'gradient': [Colors.orange.shade400, Colors.pink.shade400],
      'icon': Icons.sports_esports,
      'title': 'Fun Time',
      'subtitle': 'Everyone needs fun! 🎮',
    },
    UsageCategory.utility: {
      'color': Colors.blue,
      'gradient': [Colors.blue.shade400, Colors.indigo.shade400],
      'icon': Icons.build,
      'title': 'Tool Time',
      'subtitle': 'Getting things done! 🔧',
    },
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _appController.dispose();
    _notesController.dispose();
    _customAppController.dispose();
    super.dispose();
  }

  void _onCategoryChanged(UsageCategory category) {
    setState(() {
      _selectedCategory = category;
      _appController.clear();
      _showCustomInput = false;
    });
    _animationController.reset();
    _animationController.forward();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _categoryThemes[_selectedCategory]!;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme['gradient'][0].withOpacity(0.1),
                  theme['gradient'][1].withOpacity(0.05),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: theme['color'].withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: const ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with animated icon
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: theme['gradient'],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: theme['color'].withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              theme['icon'],
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  theme['title'],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  theme['subtitle'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme['color'],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Category Selection Chips
                      Text(
                        'What did you do?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: UsageCategory.values.map((category) {
                          final isSelected = _selectedCategory == category;
                          final catTheme = _categoryThemes[category]!;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                child: Material(
                                  color: isSelected ? catTheme['color'] : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => _onCategoryChanged(category),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                      decoration: BoxDecoration(
                                        border: isSelected
                                            ? null
                                            : Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            catTheme['icon'],
                                            color: isSelected ? Colors.white : catTheme['color'],
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            category.displayName,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.grey.shade700,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      
                      // App Selection Grid
                      Text(
                        'Pick an app',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._categoryApps[_selectedCategory]!.map((app) {
                            final isSelected = _appController.text == app['name'];
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              child: Material(
                                color: isSelected ? theme['color'] : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _appController.text = app['name'];
                                      _showCustomInput = false;
                                    });
                                    HapticFeedback.selectionClick();
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          app['icon'],
                                          size: 18,
                                          color: isSelected ? Colors.white : theme['color'],
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          app['name'],
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.grey.shade800,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          // Custom option
                          Material(
                            color: _showCustomInput ? theme['color'] : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _showCustomInput = !_showCustomInput;
                                  if (!_showCustomInput) {
                                    _appController.clear();
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showCustomInput ? Icons.check : Icons.add,
                                      size: 18,
                                      color: _showCustomInput ? Colors.white : Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Other',
                                      style: TextStyle(
                                        color: _showCustomInput ? Colors.white : Colors.grey.shade600,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Custom app input
                      if (_showCustomInput) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _customAppController,
                          onChanged: (value) {
                            _appController.text = value.isNotEmpty ? 'Other: $value' : '';
                          },
                          decoration: InputDecoration(
                            hintText: 'Type app name...',
                            prefixIcon: Icon(Icons.edit, color: theme['color']),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme['color']),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme['color'].withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme['color'], width: 2),
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      // Duration Selector
                      Text(
                        'How long?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: _duration > 5
                                      ? () {
                                          setState(() => _duration -= 5);
                                          HapticFeedback.lightImpact();
                                        }
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: theme['color'],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    children: [
                                      Text(
                                        '$_duration',
                                        style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                          color: theme['color'],
                                        ),
                                      ),
                                      Text(
                                        'minutes',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _duration < 180
                                      ? () {
                                          setState(() => _duration += 5);
                                          HapticFeedback.lightImpact();
                                        }
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: theme['color'],
                                ),
                              ],
                            ),
                            Slider(
                              value: _duration.toDouble(),
                              min: 5,
                              max: 180,
                              divisions: 35,
                              activeColor: theme['color'],
                              inactiveColor: theme['color'].withOpacity(0.2),
                              onChanged: (value) {
                                setState(() => _duration = value.round());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Notes (Optional)
                      TextField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Add a note (optional)...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.note_alt, color: theme['color']),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme['color'], width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _canSubmit()
                                  ? theme['gradient']
                                  : [Colors.grey.shade300, Colors.grey.shade400],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _canSubmit()
                                ? [
                                    BoxShadow(
                                      color: theme['color'].withOpacity(0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isSubmitting || !_canSubmit() ? null : _submit,
                              borderRadius: BorderRadius.circular(16),
                              child: Center(
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Log My Time!',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Parent will verify this entry ✓',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _canSubmit() {
    return _appController.text.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_canSubmit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select an app first!'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.submitManualEntry(
        appName: _appController.text,
        durationMinutes: _duration,
        category: _selectedCategory,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (mounted) {
        // Success animation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Great job! 🎉',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_duration minutes of ${_selectedCategory.displayName} time logged!',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Reset form with animation
        setState(() {
          _appController.clear();
          _notesController.clear();
          _customAppController.clear();
          _duration = 30;
          _showCustomInput = false;
          // Reset to educational default
          _selectedCategory = UsageCategory.educational;
        });
        
        widget.onSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Oops! $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}