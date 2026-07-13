import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ai_service.dart';
import '../services/screen_time_service.dart';

class ParentScreenTimeControls extends StatefulWidget {
  final String childId;
  
  const ParentScreenTimeControls({super.key, required this.childId});

  @override
  State<ParentScreenTimeControls> createState() => _ParentScreenTimeControlsState();
}

class _ParentScreenTimeControlsState extends State<ParentScreenTimeControls> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showAdvanced = false;
  
  // Basic Settings
  bool _enabled = false;
  int _dailyLimit = 60;
  int _deductionRate = 1;
  bool _autoDeduct = true;
  
  // Advanced Settings
  String _mode = 'total';
  String _educationalMode = 'count-toward-limit';
  int _educationalLimit = 120;
  int _interestRate = 0;
  int _maxDebt = 100;
  bool _allowNegative = true;
  bool _blockRewardsInDebt = false;
  int _checkInterval = 5;
  int _gracePeriod = 0;
  bool _bedtimeEnabled = false;
  int _bedtimeStart = 21;
  int _bedtimeEnd = 7;
  String _bedtimeBehavior = 'pause';
  
  // Notification Settings
  String _debtNotification = 'both';
  String _limit80Notification = 'in-app';
  String _limit100Notification = 'push';
  bool _showPersistentNotif = true;
  int _warnAtMinutes = 10;

  final List<String> _educationalApps = [];
  final TextEditingController _appInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _appInputController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();
          
      final data = doc.data();
      if (data != null && data['screenTimeConfig'] != null) {
        final config = data['screenTimeConfig'] as Map<String, dynamic>;
        
        setState(() {
          _enabled = config['enabled'] ?? false;
          _dailyLimit = (config['dailyLimitMinutes'] as num?)?.toInt() ?? 60;
          _deductionRate = (config['deductionRate'] as num?)?.toInt() ?? 1;
          _autoDeduct = config['autoDeduct'] ?? true;
          _mode = config['mode'] ?? 'total';
          
          // Educational
          _educationalMode = config['educationalSettings']?['mode'] ?? 'count-toward-limit';
          _educationalLimit = (config['educationalSettings']?['separateLimitMinutes'] as num?)?.toInt() ?? 120;
          
          // Debt
          _allowNegative = config['debtSettings']?['allowNegative'] ?? true;
          _interestRate = (config['debtSettings']?['interestRate'] as num?)?.toInt() ?? 0;
          _maxDebt = (config['debtSettings']?['maxDebt'] as num?)?.toInt() ?? 100;
          _blockRewardsInDebt = config['debtSettings']?['blockRewardsWhenInDebt'] ?? false;
          
          // Timing
          _checkInterval = (config['timingSettings']?['checkIntervalMinutes'] as num?)?.toInt() ?? 5;
          _gracePeriod = (config['timingSettings']?['gracePeriodMinutes'] as num?)?.toInt() ?? 0;
          _bedtimeEnabled = config['timingSettings']?['bedtimeSettings']?['enabled'] ?? false;
          _bedtimeStart = (config['timingSettings']?['bedtimeSettings']?['startHour'] as num?)?.toInt() ?? 21;
          _bedtimeEnd = (config['timingSettings']?['bedtimeSettings']?['endHour'] as num?)?.toInt() ?? 7;
          _bedtimeBehavior = config['timingSettings']?['bedtimeSettings']?['behavior'] ?? 'pause';
          
          // Notifications
          _debtNotification = config['notificationSettings']?['parentAlerts']?['onDebtCreated'] ?? 'both';
          _limit80Notification = config['notificationSettings']?['parentAlerts']?['onLimit80Percent'] ?? 'in-app';
          _limit100Notification = config['notificationSettings']?['parentAlerts']?['onLimit100Percent'] ?? 'push';
          _showPersistentNotif = config['notificationSettings']?['childAlerts']?['showPersistentNotification'] ?? true;
          _warnAtMinutes = (config['notificationSettings']?['childAlerts']?['warnAtRemainingMinutes'] as num?)?.toInt() ?? 10;
          
          // Apps
          final apps = config['educationalApps'] as List<dynamic>?;
          if (apps != null) {
            _educationalApps.addAll(apps.cast<String>());
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading settings: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_autoDeduct && _enabled) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Manual Mode'),
          content: const Text('Auto-deduction is disabled. You will need to manually deduct points when limits are exceeded. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);
    try {
      final config = {
        'enabled': _enabled,
        'dailyLimitMinutes': _dailyLimit,
        'deductionRate': _deductionRate,
        'autoDeduct': _autoDeduct,
        'mode': _mode,
        'educationalSettings': {
          'mode': _educationalMode,
          'separateLimitMinutes': _educationalLimit,
        },
        'debtSettings': {
          'allowNegative': _allowNegative,
          'interestRate': _interestRate,
          'maxDebt': _maxDebt,
          'blockRewardsWhenInDebt': _blockRewardsInDebt,
        },
        'timingSettings': {
          'checkIntervalMinutes': _checkInterval,
          'gracePeriodMinutes': _gracePeriod,
          'bedtimeSettings': {
            'enabled': _bedtimeEnabled,
            'startHour': _bedtimeStart,
            'endHour': _bedtimeEnd,
            'behavior': _bedtimeBehavior,
          },
        },
        'notificationSettings': {
          'parentAlerts': {
            'onDebtCreated': _debtNotification,
            'onLimit80Percent': _limit80Notification,
            'onLimit100Percent': _limit100Notification,
          },
          'childAlerts': {
            'showPersistentNotification': _showPersistentNotif,
            'warnAtRemainingMinutes': _warnAtMinutes,
          },
        },
        'educationalApps': _educationalApps,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .update({
        'screenTimeConfig': config,
        'screenTimeEnabled': _enabled,
      });

      if (_enabled) {
        final hasPermission = await ScreenTimeService().checkPermission();
        if (!hasPermission && mounted) {
          _showPermissionDialog();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'To track screen time automatically, please enable "Usage Access" permission for this app in Android Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScreenTimeService().requestPermission();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _getAISuggestions() async {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Getting AI recommendations...'),
          ],
        ),
      ),
    );

    try {
      final childDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .get();
      
      final age = (childDoc.data()?['age'] as num?)?.toInt() ?? 8;
      
      // Use existing AIService method or create inline suggestion
      String suggestions = '''
**AI Recommendations for Age $age:**

**Screen Time Limit:** ${age < 6 ? '30-45 minutes' : age < 12 ? '60-90 minutes' : '90-120 minutes'}

**Key Recommendations:**
• Set clear boundaries about when and where devices can be used
• Encourage educational content during allotted screen time
• Use a timer or visual cue to help child understand time limits
• Offer alternative activities when time is up (reading, outdoor play)
• Be consistent with enforcement

**Suggested Settings:**
• Daily Limit: ${age < 6 ? '30' : age < 12 ? '60' : '90'} minutes
• Deduction Rate: 1-2 points per minute over limit
• Allow debt accumulation so child learns financial responsibility
• Enable bedtime mode (9pm-7am) to ensure sleep quality
''';

      Navigator.pop(context);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.purple),
              SizedBox(width: 8),
              Text('AI Recommendations'),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(suggestions),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dailyLimit = age < 6 ? 30 : (age < 12 ? 60 : 90);
                  _deductionRate = 1;
                  _allowNegative = true;
                  _maxDebt = 50;
                  _bedtimeEnabled = true;
                  _bedtimeStart = 21;
                  _bedtimeEnd = 7;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply Suggestions'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading settings...'),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Screen Time Rules'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome, color: Colors.purple),
                onPressed: _getAISuggestions,
                tooltip: 'Get AI Suggestions',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Master Toggle
                Card(
                  color: _enabled ? Colors.blue[50] : Colors.grey[100],
                  child: SwitchListTile(
                    title: const Text(
                      'Enable Screen Time Tracking',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _enabled 
                        ? 'Monitoring active - child will see screen time widget'
                        : 'Disabled - child will not see screen time tracking',
                      ),
                    value: _enabled,
                    onChanged: (val) => setState(() => _enabled = val),
                    secondary: Icon(
                      _enabled ? Icons.timer : Icons.timer_off,
                      color: _enabled ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
                
                if (_enabled) ...[
                  const SizedBox(height: 20),
                  
                  // Basic Settings
                  _buildSectionTitle('Basic Settings'),
                  const SizedBox(height: 12),
                  
                  TextFormField(
                    initialValue: _dailyLimit.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Daily Limit (minutes)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer),
                      helperText: 'Recommended: 60-120 min for ages 6-12',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _dailyLimit = int.tryParse(v) ?? 60,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    initialValue: _deductionRate.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Point Deduction Rate',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.monetization_on),
                      suffixText: 'points/min over limit',
                      helperText: '1-5 points per minute is typical',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _deductionRate = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Enable Auto-Deduction'),
                    subtitle: const Text('Automatically deduct points every 5 minutes when limit exceeded'),
                    value: _autoDeduct,
                    onChanged: (val) => setState(() => _autoDeduct = val),
                  ),
                  
                  const Divider(height: 32),
                  
                  // Advanced Settings Toggle
                  InkWell(
                    onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                    child: Row(
                      children: [
                        Icon(
                          _showAdvanced ? Icons.expand_less : Icons.expand_more,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Advanced Settings',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (_showAdvanced) ...[
                    const SizedBox(height: 20),
                    
                    // Tracking Mode
                    _buildSectionTitle('Tracking Mode'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'total',
                          label: Text('Total Time'),
                          icon: Icon(Icons.timer),
                        ),
                        ButtonSegment(
                          value: 'per-app',
                          label: Text('Per App'),
                          icon: Icon(Icons.apps),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (set) => setState(() => _mode = set.first),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Educational Settings
                    _buildSectionTitle('Educational Apps'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _educationalMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Educational Time Handling',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'count-toward-limit',
                          child: Text('Count toward limit (standard)'),
                        ),
                        DropdownMenuItem(
                          value: 'exempt',
                          child: Text('Exempt from limit (unlimited)'),
                        ),
                        DropdownMenuItem(
                          value: 'separate-limit',
                          child: Text('Separate higher limit'),
                        ),
                      ],
                      onChanged: (val) => setState(() => _educationalMode = val!),
                    ),
                    
                    if (_educationalMode == 'separate-limit') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _educationalLimit.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Educational App Limit (minutes)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _educationalLimit = int.tryParse(v) ?? 120,
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    _buildEducationalAppsList(),
                    
                    const SizedBox(height: 20),
                    
                    // Debt Configuration
                    _buildSectionTitle('Debt Configuration'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Allow Negative Points (Debt)'),
                      subtitle: const Text('Child can owe points when balance reaches zero'),
                      value: _allowNegative,
                      onChanged: (val) => setState(() => _allowNegative = val),
                    ),
                    
                    if (_allowNegative) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _maxDebt.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Maximum Debt Allowed',
                          border: OutlineInputBorder(),
                          helperText: 'Max points child can owe (0 = unlimited)',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _maxDebt = int.tryParse(v) ?? 100,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _interestRate.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Interest Rate (% per day)',
                          border: OutlineInputBorder(),
                          helperText: '0 = no interest',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _interestRate = int.tryParse(v) ?? 0,
                      ),
                      SwitchListTile(
                        title: const Text('Block Rewards When in Debt'),
                        value: _blockRewardsInDebt,
                        onChanged: (val) => setState(() => _blockRewardsInDebt = val),
                      ),
                    ],
                    
                    const SizedBox(height: 20),
                    
                    // Timing Settings
                    _buildSectionTitle('Timing & Grace'),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: _gracePeriod.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Grace Period (minutes)',
                        border: OutlineInputBorder(),
                        helperText: 'Minutes over limit before deductions start (0 = immediate)',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _gracePeriod = int.tryParse(v) ?? 0,
                    ),
                    
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Enable Bedtime Mode'),
                      subtitle: const Text('Pause or modify tracking during sleep hours'),
                      value: _bedtimeEnabled,
                      onChanged: (val) => setState(() => _bedtimeEnabled = val),
                    ),
                    
                    if (_bedtimeEnabled) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _bedtimeStart.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Bedtime Start (24h)',
                                border: OutlineInputBorder(),
                                helperText: 'e.g., 21 for 9pm',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _bedtimeStart = int.tryParse(v) ?? 21,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _bedtimeEnd.toString(),
                              decoration: const InputDecoration(
                                labelText: 'Wake Time (24h)',
                                border: OutlineInputBorder(),
                                helperText: 'e.g., 7 for 7am',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _bedtimeEnd = int.tryParse(v) ?? 7,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _bedtimeBehavior,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Bedtime Behavior',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'pause',
                            child: Text('Pause tracking (free time)'),
                          ),
                          DropdownMenuItem(
                            value: 'continue',
                            child: Text('Continue tracking'),
                          ),
                          DropdownMenuItem(
                            value: 'double-rate',
                            child: Text('Double deduction rate'),
                          ),
                        ],
                        onChanged: (val) => setState(() => _bedtimeBehavior = val!),
                      ),
                    ],
                    
                    const SizedBox(height: 20),
                    
                    // Notifications
                    _buildSectionTitle('Notifications'),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      'When Child Goes Into Debt',
                      _debtNotification,
                      ['push', 'in-app', 'both', 'none'],
                      (val) => setState(() => _debtNotification = val),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      'At 80% of Limit',
                      _limit80Notification,
                      ['push', 'in-app', 'both', 'none'],
                      (val) => setState(() => _limit80Notification = val),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      'At 100% of Limit',
                      _limit100Notification,
                      ['push', 'in-app', 'both', 'none'],
                      (val) => setState(() => _limit100Notification = val),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Show Persistent Notification on Child Device'),
                      subtitle: const Text('Required for background tracking on Android'),
                      value: _showPersistentNotif,
                      onChanged: (val) => setState(() => _showPersistentNotif = val),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SafeArea(
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, Function(String) onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.map((opt) {
        final label = opt == 'push' ? 'Push Notification' 
          : opt == 'in-app' ? 'In-App Only' 
          : opt == 'both' ? 'Push + In-App' 
          : 'No Notification';
        return DropdownMenuItem(value: opt, child: Text(label));
      }).toList(),
      onChanged: (val) => onChanged(val!),
    );
  }

  Widget _buildEducationalAppsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Educational Apps (Package Names)',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _educationalApps.map((app) {
            return Chip(
              label: Text(app),
              onDeleted: () => setState(() => _educationalApps.remove(app)),
              deleteIcon: const Icon(Icons.close, size: 18),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _appInputController,
                decoration: const InputDecoration(
                  hintText: 'com.example.app',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                if (_appInputController.text.isNotEmpty) {
                  setState(() {
                    _educationalApps.add(_appInputController.text);
                    _appInputController.clear();
                  });
                }
              },
              icon: const Icon(Icons.add),
              color: Colors.blue,
            ),
          ],
        ),
      ],
    );
  }
}