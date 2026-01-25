import 'package:cloud_firestore/cloud_firestore.dart';

enum DeductionRuleType {
  screenTime,      // Deduct per minute/hour of usage
  missedTask,      // Deduct for incomplete tasks
  ruleViolation,   // Deduct for breaking rules
  dailyFee,        // Daily maintenance deduction
}

class DeductionRule {
  final String id;
  final String childId;
  final String childName;
  final DeductionRuleType type;
  final int pointsPerInterval;
  final int intervalMinutes;  // How often to check (1 = every minute, 60 = hourly)
  final bool isActive;
  final String description;

  const DeductionRule({
    required this.id,
    required this.childId,
    required this.childName,
    required this.type,
    required this.pointsPerInterval,
    required this.intervalMinutes,
    required this.isActive,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'childName': childName,
      'type': type.toString(),
      'pointsPerInterval': pointsPerInterval,
      'intervalMinutes': intervalMinutes,
      'isActive': isActive,
      'description': description,
      'lastApplied': null, // Timestamp of last deduction
    };
  }

  factory DeductionRule.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeductionRule(
      id: doc.id,
      childId: data['childId'],
      childName: data['childName'],
      type: DeductionRuleType.values.firstWhere((e) => e.toString() == data['type']),
      pointsPerInterval: data['pointsPerInterval'],
      intervalMinutes: data['intervalMinutes'],
      isActive: data['isActive'],
      description: data['description'],
    );
  }
}