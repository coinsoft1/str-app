import 'package:cloud_firestore/cloud_firestore.dart';

enum UsageCategory {
  educational,
  entertainment,
  utility;

  String get displayName {
    switch (this) {
      case UsageCategory.educational:
        return 'Educational';
      case UsageCategory.entertainment:
        return 'Entertainment';
      case UsageCategory.utility:
        return 'Utility';
    }
  }

  String get emoji {
    switch (this) {
      case UsageCategory.educational:
        return '🎓';
      case UsageCategory.entertainment:
        return '🎮';
      case UsageCategory.utility:
        return '🔧';
    }
  }
}

class UsageEntry {
  final String id;
  final String childId;
  final DateTime timestamp;
  final String appName;
  final String? packageName;
  final int durationMinutes;
  final UsageCategory category;
  final String source; // 'manual' or 'automatic'
  final bool verified;
  final String? notes;
  final DateTime createdAt;

  UsageEntry({
    required this.id,
    required this.childId,
    required this.timestamp,
    required this.appName,
    this.packageName,
    required this.durationMinutes,
    required this.category,
    required this.source,
    this.verified = false,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'childId': childId,
      'timestamp': Timestamp.fromDate(timestamp),
      'appName': appName,
      'packageName': packageName,
      'durationMinutes': durationMinutes,
      'category': category.name,
      'source': source,
      'verified': verified,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory UsageEntry.fromMap(Map<String, dynamic> map) {
    return UsageEntry(
      id: map['id'] ?? '',
      childId: map['childId'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      appName: map['appName'] ?? '',
      packageName: map['packageName'],
      durationMinutes: map['durationMinutes'] ?? 0,
      category: UsageCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => UsageCategory.utility,
      ),
      source: map['source'] ?? 'manual',
      verified: map['verified'] ?? false,
      notes: map['notes'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}