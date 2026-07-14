// lib/services/usage_stats_stub.dart
// Stub for usage_stats — prevents iOS build crashes

class UsageStats {
  static Future<bool?> checkUsagePermission() async => false;
  static Future<void> grantUsagePermission() async {}
  static Future<List<EventUsageInfo>> queryEvents(DateTime startDate, DateTime endDate) async => [];
}

class EventUsageInfo {
  final String? packageName;
  final String? className;
  final String? eventType;
  final String? timeStamp;

  EventUsageInfo({this.packageName, this.className, this.eventType, this.timeStamp});
}