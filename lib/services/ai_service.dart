import 'package:flutter/foundation.dart';

/// AI-powered screen time recommendations based on WHO/AAP guidelines
class AIService {
  
  /// Get AI-suggested screen time limit based on child's age
  Future<String> suggestScreenTimeLimit({
    required String childName,
    required int age,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    
    String recommendation;
    String reasoning;
    
    if (age < 2) {
      recommendation = "0 minutes (screen time not recommended)";
      reasoning = "WHO recommends no screen time for children under 2, except video calls.";
    } else if (age >= 2 && age <= 5) {
      recommendation = "45-60 minutes";
      reasoning = "At age $age, focus on high-quality educational content with co-viewing.";
    } else if (age >= 6 && age <= 7) {
      recommendation = "60-90 minutes";
      reasoning = "For $childName (age $age), balance entertainment with educational content.";
    } else if (age >= 8 && age <= 12) {
      recommendation = "90-120 minutes";
      reasoning = "Pre-teens need guidance on social media and mindful tech use.";
    } else {
      recommendation = "120-180 minutes";
      reasoning = "Teens should focus on intentional, productive screen use.";
    }
    
    return "💡 **AI Recommendation for $childName (Age $age)**\n\n"
        "**Limit:** $recommendation per day\n\n"
        "**Reasoning:** $reasoning\n\n"
        "📱 **Tips:**\n"
        "• Schedule device-free meals\n"
        "• No screens 1 hour before bedtime\n"
        "• Encourage co-viewing for younger children\n"
        "• Replace passive watching with creative activities";
  }

  /// AI negotiation for screen time requests
  Future<String> negotiateScreenTime({
    required String childName,
    required int currentPoints,
    required int requestedMinutes,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (requestedMinutes > 120) {
      return "🤔 I understand you'd like more time, $childName, but $requestedMinutes minutes is quite long. "
          "How about we compromise with 60 minutes? You currently have $currentPoints points. "
          "Consider earning more points by completing tasks first!";
    } else if (currentPoints >= requestedMinutes * 2) {
      return "✅ Reasonable request, $childName! Your $currentPoints points are sufficient for $requestedMinutes minutes. "
          "This is a good balance. Consider saving some points for later!";
    } else {
      int neededPoints = requestedMinutes * 2;
      return "⚠️ $childName, you need $neededPoints points for $requestedMinutes minutes, but only have $currentPoints. "
          "Complete some tasks to earn more points, or request fewer minutes.";
    }
  }

  /// General AI negotiation/chat
  Future<String> negotiate({
    required String prompt,
    required String childName,
    required int childAge,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (prompt.toLowerCase().contains('time') || prompt.toLowerCase().contains('minutes')) {
      return "I'm here to help negotiate screen time! How many minutes are you asking for, and what would you like to do with the extra time?";
    } else if (prompt.toLowerCase().contains('task') || prompt.toLowerCase().contains('points')) {
      return "Great question! You can earn points by completing tasks assigned by your parents. Check the Tasks section to see what's available.";
    } else {
      return "Hi $childName! I'm here to help you negotiate with your parents. "
          "You can ask me about screen time, tasks, or rewards. What would you like to discuss?";
    }
  }

  /// Analyze screen time usage
  Future<String> analyzeUsage({
    required String childName,
    required int actualMinutes,
    required int dailyLimit,
    required String ageGroup,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (actualMinutes <= dailyLimit) {
      return "✅ **Great job, $childName!** You've used $actualMinutes minutes out of $dailyLimit allowed. "
          "Keep up the good balance!";
    } else {
      int overage = actualMinutes - dailyLimit;
      return "⚠️ **Over limit by $overage minutes**, $childName. \n\n"
          "This week, you've averaged ${actualMinutes}min/day (${overage}min over). "
          "Consider:\n"
          "• Earning extra time with tasks\n"
          "• Taking screen breaks every 30min\n"
          "• Device-free activities (reading, outdoor play)";
    }
  }

  /// Suggest educational content
  Future<List<String>> suggestEducationalApps(int age) async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (age < 5) {
      return [
        "📚 PBS Kids (co-viewing recommended)",
        "🎵 Sesame Street",
        "🎨 Drawing/Coloring Apps",
      ];
    } else if (age < 10) {
      return [
        "🔬 Khan Academy Kids",
        "🧩 Logic Puzzles",
        "🌍 National Geographic Kids",
        "💻 Scratch Jr (coding)",
      ];
    } else {
      return [
        "💻 Khan Academy",
        "🎬 YouTube EDU",
        "🎨 Canva (creative design)",
        "📝 Notion (organization)",
        "🎵 Music Production Apps",
      ];
    }
  }
}