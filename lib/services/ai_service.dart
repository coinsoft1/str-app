import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Enhanced AI Service with clean output and proper formatting
class AIService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _random = Random();
  
  String? _currentChildId;
  String? _currentParentId;
  String? _currentChildName;
  int? _currentChildAge;
  
  // Real-time streams
  StreamSubscription? _childDataSubscription;
  StreamSubscription? _tasksSubscription;
  StreamSubscription? _redemptionsSubscription;
  
  // Live data cache
  Map<String, dynamic> _liveData = {};
  List<String> _conversationMemory = [];
  
  // Cleaner templates with less markdown clutter
  final Map<String, List<String>> _responseTemplates = {
    'greeting': [
      "Hey there! I'm monitoring {childName}'s activity — {recentTasks} tasks completed recently with **{currentPoints} points** available. What situation are you navigating today?",
      "Hi! I've been watching {childName}'s progress. They've completed {recentTasks} tasks and have **{currentPoints} points**. How can I help with today's challenges?",
      "Hello! {childName} has **{currentPoints} points** from {recentTasks} recent tasks. What's the negotiation scenario you're facing?",
    ],
    
    'approve_suggestion': [
      "✅ **I'd recommend APPROVING this request.**\n\n{childName} has earned it — {recentTasks} tasks completed with **{currentPoints} points** available.\n\n**What to say:**\n> \"I see how hard you've been working! You've definitely earned {requestedMinutes} minutes. Set a timer and enjoy!\"\n\nThis reinforces positive behavior.",
      
      "🟢 **Green light from me!**\n\n{childName} has been consistent ({recentTasks} tasks, **{currentPoints} points**).\n\n**Script:** \"Great job earning those points! You can have the time — you've worked for it.\"",
    ],
    
    'deny_suggestion': [
      "❌ **Not enough points yet.**\n\n{childName} has **{currentPoints} points** but needs **{neededPoints} points** for {requestedMinutes} minutes.\n\n**What to say:**\n> \"I appreciate you asking respectfully. You need {neededPoints} more points. Want to knock out a quick task to get there?\"\n\n**Why this works:** It teaches that rewards require effort, but gives a clear path forward.",
      
      "⛔ **Points needed: {neededPoints}** (Currently: {currentPoints})\n\n**Your response:**\n> \"I hear you want the time, and that's fair to ask. Right now you need {neededPoints} more points. The dishwasher needs unloading (20 points) — want to swap 5 minutes of work for 30 minutes of screen time?\"\n\nThis turns a 'no' into a negotiation.",
    ],
    
    'counter_suggestion': [
      "⚖️ **Try a COUNTER-OFFER.**\n\n{childName} has had {avgScreenTime}min already today.\n\n**Say:**\n> \"I know you want {requestedMinutes} minutes, but you've had quite a bit of screen time today. How about 15 minutes now, and if you read for 20 minutes, you can earn 30 more?\"\n\n**Psychology:** You're not saying no — you're teaching delayed gratification.",
      
      "🤝 **Compromise time.** ({avgScreenTime} minutes already used)\n\n**Try this:**\n> \"You can have 15 minutes now as a break, then after some outside time, you can have another 20. Deal?\"\n\nThis prevents 'screen zombie' effect while avoiding a power struggle.",
    ],
    
    'task_motivation': [
      "💡 **Motivation strategies for {childName}:**\n\n1. **Choice architecture:** \"Do you want to do dishes first or fold laundry?\" (Gives control)\n2. **Micro-tasks:** \"Just put away 5 things\" (Builds momentum)  \n3. **Body doubling:** \"I'll do my work while you do yours\" (Companionship)\n4. **Gamification:** \"Bet you can't finish in 10 minutes!\"\n\n**Current stats:** {recentTasks} tasks done, **{currentPoints} points** earned.",
    ],
    
    'pattern_analysis': [
      "📊 **Pattern Analysis for {childName}:**\n\n**Recent Activity:** {recentTasks} tasks completed, {redemptions} rewards redeemed\n**Points:** {currentPoints} available\n**Engagement Level:** {patternType}\n\n**Insight:** {insight}\n\n**Recommendation:** {recommendation}",
    ],
  };
  
  /// Initialize conversation with streaming data
  Future<Stream<String>> startSmartConversation({
    required String childId,
    required String parentId,
    required String childName,
    required int childAge,
  }) async {
    _currentChildId = childId;
    _currentParentId = parentId;
    _currentChildName = childName;
    _currentChildAge = childAge;
    _conversationMemory.clear();
    
    // Start real-time data streaming
    _startRealTimeStreams(childId, parentId);
    
    // Wait for initial data
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Generate varied greeting
    return _generateStreamingResponse(_getRandomTemplate('greeting', {
      'childName': childName,
      'recentTasks': _liveData['recentCompletions']?.toString() ?? '0',
      'currentPoints': _liveData['currentPoints']?.toString() ?? '0',
    }));
  }
  
  /// Send message with context awareness
  Future<Stream<String>> sendMessage(String userMessage) async {
    _conversationMemory.add("Parent: $userMessage");
    
    // Analyze intent
    final intent = _analyzeIntent(userMessage);
    
    // Build response based on intent + real data
    String response;
    switch (intent) {
      case 'screen_time_request':
        response = _handleScreenTimeRequest(userMessage);
        break;
      case 'task_motivation':
        response = _getRandomTemplate('task_motivation', _getTemplateData());
        break;
      case 'pattern_analysis':
        response = await _generatePatternAnalysis();
        break;
      case 'general_help':
      default:
        response = _handleGeneralHelp(userMessage);
    }
    
    _conversationMemory.add("AI: $response");
    return _generateStreamingResponse(response);
  }
  
  /// Get specific negotiation advice with fresh data check
  Future<Stream<String>> getSmartNegotiationAdvice({
    required String scenario,
    required int requestedMinutes,
  }) async {
    // Ensure we have fresh data
    await _refreshLiveData();
    
    final currentPoints = (_liveData['currentPoints'] ?? 0) as int;
    final recentTasks = (_liveData['recentCompletions'] ?? 0) as int;
    final avgScreenTime = (_liveData['avgScreenTime'] ?? 0) as int;
    final neededPoints = requestedMinutes * 2;
    
    String templateKey;
    Map<String, String> data = {
      'childName': _currentChildName ?? 'Child',
      'currentPoints': currentPoints.toString(),
      'recentTasks': recentTasks.toString(),
      'requestedMinutes': requestedMinutes.toString(),
      'neededPoints': neededPoints.toString(),
      'avgScreenTime': avgScreenTime.toString(),
    };
    
    // Better logic with clear thresholds
    if (currentPoints < neededPoints) {
      templateKey = 'deny_suggestion';
    } else if (avgScreenTime > 90) {
      templateKey = 'counter_suggestion';
    } else if (recentTasks >= 2 || currentPoints >= neededPoints + 20) {
      templateKey = 'approve_suggestion';
    } else {
      templateKey = 'approve_suggestion'; // Default to approve if they have points
    }
    
    return _generateStreamingResponse(_getRandomTemplate(templateKey, data));
  }
  
  /// NEW: Non-streaming version for dialogs (fixes repetition issue)
  Future<String> getNegotiationAdviceText({
    required String childName,
    required int currentPoints,
    required int requestedMinutes,
  }) async {
    await _refreshLiveData();
    
    final neededPoints = requestedMinutes * 2;
    final recentTasks = (_liveData['recentCompletions'] ?? 0) as int;
    final avgScreenTime = (_liveData['avgScreenTime'] ?? 0) as int;
    final actualPoints = (_liveData['currentPoints'] ?? currentPoints) as int;
    
    // Determine recommendation
    if (actualPoints < neededPoints) {
      final deficit = neededPoints - actualPoints;
      return '''❌ **Not Enough Points Yet**

**Current:** $actualPoints points  
**Needed:** $neededPoints points (for $requestedMinutes min)  
**Shortage:** $deficit points

**Why:** You need $deficit more points to afford this screen time.

**How to earn points quickly:**
• Complete a task from your task list
• Ask your parent for a quick chore (10-30 points)
• Read for 20 minutes (10 points)

**What to say to your parent:**
> "I don't have enough points yet. Can I do a quick task to earn the remaining $deficit points?"''';
    } else if (avgScreenTime > 90) {
      return '''⚖️ **Counter Offer Recommended**

You've already had $avgScreenTime minutes today.

**Suggestion:** Instead of $requestedMinutes minutes, how about:
• **15 minutes now** (30 points)
• **Then 20 minutes later** after a break (40 points)

**Why this helps:**
• Prevents "screen zombie" mode
• Gives your eyes a rest
• Makes the fun last longer!

**What to say:**
> "Can I have 15 minutes now and 20 more later after I play outside?"''';
    } else {
      return '''✅ **Request Approved!**

**Current:** $actualPoints points  
**Cost:** $neededPoints points (for $requestedMinutes min)  
**Remaining after:** ${actualPoints - neededPoints} points

**AI Note:** You've been doing great with $recentTasks recent tasks completed. You've earned this screen time!

**What to say:**
> "I've earned $actualPoints points and would like to exchange $neededPoints for $requestedMinutes minutes of screen time. Can I use my points?"''';
    }
  }
  
  /// Analyze patterns with fake AI
  Future<Stream<String>> analyzeChildPatterns() async {
    await _refreshLiveData();
    return _generateStreamingResponse(await _generatePatternAnalysis());
  }
  
  // ============ PRIVATE METHODS ============
  
  void _startRealTimeStreams(String childId, String parentId) {
    _childDataSubscription?.cancel();
    _tasksSubscription?.cancel();
    _redemptionsSubscription?.cancel();
    
    // Live child data
    _childDataSubscription = _firestore
        .collection('users')
        .doc(childId)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        _liveData['currentPoints'] = (snap.data()?['currentPoints'] ?? 0) as int;
        _liveData['totalPoints'] = snap.data()?['totalPoints'] ?? 0;
        _liveData['childName'] = snap.data()?['name'] ?? 'Child';
      }
    });
    
    // Live task completions (last 7 days)
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    _tasksSubscription = _firestore
        .collection('tasks')
        .where('assignedTo', isEqualTo: childId)
        .where('status', whereIn: ['completed', 'approved'])
        .snapshots()
        .listen((snap) {
      final recent = snap.docs.where((d) {
        final completedAt = d.data()['completedAt'] as Timestamp?;
        return completedAt != null && completedAt.toDate().isAfter(weekAgo);
      }).length;
      _liveData['recentCompletions'] = recent;
    });
    
    // Live redemptions
    _redemptionsSubscription = _firestore
        .collection('redemptions')
        .where('childId', isEqualTo: childId)
        .where('status', isEqualTo: 'completed')
        .orderBy('redeemedAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
      _liveData['recentRedemptions'] = snap.docs.length;
    });
  }
  
  Future<void> _refreshLiveData() async {
    if (_currentChildId == null) return;
    
    // Force fresh fetch
    final doc = await _firestore.collection('users').doc(_currentChildId).get();
    if (doc.exists) {
      _liveData['currentPoints'] = (doc.data()?['currentPoints'] ?? 0) as int;
    }
    
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final tasks = await _firestore
        .collection('tasks')
        .where('assignedTo', isEqualTo: _currentChildId)
        .where('status', whereIn: ['completed', 'approved'])
        .get();
        
    final recent = tasks.docs.where((d) {
      final completedAt = d.data()['completedAt'] as Timestamp?;
      return completedAt != null && completedAt.toDate().isAfter(weekAgo);
    }).length;
    
    _liveData['recentCompletions'] = recent;
  }
  
  Stream<String> _generateStreamingResponse(String fullText) async* {
    // FIXED: Yield word by word (delta), not accumulated buffer
    final words = fullText.split(' ');
    String currentText = '';
    
    for (var i = 0; i < words.length; i++) {
      currentText += (i == 0 ? '' : ' ') + words[i];
      yield currentText;
      await Future.delayed(Duration(milliseconds: 15 + _random.nextInt(20)));
    }
  }
  
  String _getRandomTemplate(String key, Map<String, String> data) {
    final templates = _responseTemplates[key] ?? ['Let me help with that.'];
    final template = templates[_random.nextInt(templates.length)];
    
    // Replace placeholders
    String result = template;
    data.forEach((placeholder, value) {
      result = result.replaceAll('{$placeholder}', value);
    });
    
    return result;
  }
  
  Map<String, String> _getTemplateData() {
    return {
      'childName': _liveData['childName']?.toString() ?? _currentChildName ?? 'Child',
      'currentPoints': (_liveData['currentPoints'] ?? 0).toString(),
      'recentTasks': (_liveData['recentCompletions'] ?? 0).toString(),
      'redemptions': (_liveData['recentRedemptions'] ?? 0).toString(),
    };
  }
  
  String _analyzeIntent(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('minute') || lower.contains('time') || lower.contains('screen')) {
      return 'screen_time_request';
    } else if (lower.contains('task') || lower.contains('chore') || lower.contains('won\'t') || lower.contains('refuse')) {
      return 'task_motivation';
    } else if (lower.contains('pattern') || lower.contains('analyze') || lower.contains('behavior')) {
      return 'pattern_analysis';
    }
    return 'general_help';
  }
  
  String _handleScreenTimeRequest(String message) {
    // Extract minutes
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(message);
    final requestedMinutes = match != null ? int.parse(match.group(0)!) : 30;
    
    final currentPoints = (_liveData['currentPoints'] ?? 0) as int;
    final recentTasks = (_liveData['recentCompletions'] ?? 0) as int;
    final avgScreenTime = (_liveData['avgScreenTime'] ?? 0) as int;
    final neededPoints = requestedMinutes * 2;
    
    if (currentPoints < neededPoints) {
      return _getRandomTemplate('deny_suggestion', {
        ..._getTemplateData(),
        'requestedMinutes': requestedMinutes.toString(),
        'neededPoints': neededPoints.toString(),
      });
    } else if (avgScreenTime > 90) {
      return _getRandomTemplate('counter_suggestion', {
        ..._getTemplateData(),
        'requestedMinutes': requestedMinutes.toString(),
        'avgScreenTime': avgScreenTime.toString(),
      });
    } else {
      return _getRandomTemplate('approve_suggestion', {
        ..._getTemplateData(),
        'requestedMinutes': requestedMinutes.toString(),
        'neededPoints': neededPoints.toString(),
      });
    }
  }
  
  String _handleGeneralHelp(String message) {
    return "I'm here to help with ${_liveData['childName'] ?? 'your child'}! Based on their recent activity (**${_liveData['recentCompletions'] ?? 0} tasks**, **${_liveData['currentPoints'] ?? 0} points**), what specific situation are you dealing with?\n\nI can help with:\n• Screen time negotiations\n• Task motivation strategies  \n• Behavioral pattern analysis\n• Exact scripts to say\n\nWhat would be most helpful right now?";
  }
  
  Future<String> _generatePatternAnalysis() async {
    final tasks = (_liveData['recentCompletions'] ?? 0) as int;
    final points = (_liveData['currentPoints'] ?? 0) as int;
    final redemptions = (_liveData['recentRedemptions'] ?? 0) as int;
    
    String patternType;
    String insight;
    String recommendation;
    
    if (tasks >= 5) {
      patternType = "HIGH ENGAGEMENT ✅";
      insight = "${_currentChildName} is consistently completing tasks. This suggests they respond well to the reward system.";
      recommendation = "Maintain current structure. Consider increasing task difficulty slightly to keep them challenged.";
    } else if (tasks >= 2) {
      patternType = "MODERATE ENGAGEMENT ⚠️";
      insight = "Some participation, but inconsistent. May need more immediate rewards or simpler tasks.";
      recommendation = "Try breaking tasks into smaller chunks (2-3 minute micro-tasks) to build momentum.";
    } else {
      patternType = "LOW ENGAGEMENT ❌";
      insight = "Tasks aren't being completed. Could be motivation issue or tasks are too difficult.";
      recommendation = "Have a conversation about what rewards actually motivate them. Reset with very easy wins.";
    }
    
    return _getRandomTemplate('pattern_analysis', {
      ..._getTemplateData(),
      'patternType': patternType,
      'insight': insight,
      'recommendation': recommendation,
    });
  }
  
  void dispose() {
    _childDataSubscription?.cancel();
    _tasksSubscription?.cancel();
    _redemptionsSubscription?.cancel();
  }
  
  // UPDATED: Backward compatibility - now uses fixed text method
  Future<String> negotiateScreenTime({
    required String childName,
    required int currentPoints,
    required int requestedMinutes,
  }) async {
    return getNegotiationAdviceText(
      childName: childName,
      currentPoints: currentPoints,
      requestedMinutes: requestedMinutes,
    );
  }
  
  Future<String> suggestScreenTimeLimit({
    required String childName,
    required int age,
  }) async {
    final recommendations = {
      5: "20-30 minutes",
      6: "30-45 minutes", 
      7: "45-60 minutes",
      8: "60-90 minutes",
      9: "90-120 minutes",
      10: "90-120 minutes",
    };
    
    final rec = recommendations[age] ?? "60-90 minutes";
    return "For **$childName** (age $age), I recommend **$rec per day**.\n\n**Why:** At this age, quality matters more than quantity. Encourage educational content and co-viewing when possible. Use the points system to teach that screen time is earned, not automatic.";
  }
}