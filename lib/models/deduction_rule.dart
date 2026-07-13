import 'package:cloud_firestore/cloud_firestore.dart';

class DeductionRule {
  final String id;
  final String parentId;
  final String childId;
  final String childName;
  final DeductionRuleType type;
  final int pointsPerInterval;
  final int intervalMinutes;
  final bool isActive;
  final String description;

  DeductionRule({
    required this.id,
    required this.parentId,
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
      'parentId': parentId,
      'childId': childId,
      'childName': childName,
      'type': type.name,
      'pointsPerInterval': pointsPerInterval,
      'intervalMinutes': intervalMinutes,
      'isActive': isActive,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory DeductionRule.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeductionRule(
      id: doc.id,
      parentId: data['parentId'] ?? '',
      childId: data['childId'] ?? '',
      childName: data['childName'] ?? '',
      type: DeductionRuleType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => DeductionRuleType.screenTime,
      ),
      pointsPerInterval: data['pointsPerInterval'] ?? 1,
      intervalMinutes: data['intervalMinutes'] ?? 60,
      isActive: data['isActive'] ?? true,
      description: data['description'] ?? '',
    );
  }
}

enum DeductionRuleType { screenTime, usage, bedtime }