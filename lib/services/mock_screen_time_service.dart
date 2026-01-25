// ✅ FREE ALTERNATIVE - No paid packages needed

class MockScreenTimeService {
  // Simulate screen time detection
  // In production, replace with actual Android UsageStats API
  
  static Future<int> getScreenTimeMinutes(String packageName, DateTime startTime) async {
    // Simulate 5 minutes of screen time per interval for demo purposes
    // This returns a FIXED value for testing - replace with real implementation
    return 5;
  }

  static Future<bool> isScreenOn() async {
    // Assume screen is always on for demo
    return true;
  }
}