// FREE ALTERNATIVE - No paid packages needed
// In production, replace with Android UsageStats API via platform channels

class ScreenTimeService {
  // Mock implementation - returns simulated screen time
  // Replace with actual implementation for production
  
  Future<int> getScreenTimeMinutes(DateTime startTime) async {
    // Simulate 5 minutes of screen time per check for demo
    // In production, query UsageStatsManager or similar
    return 5;
  }

  Future<bool> isScreenOn() async {
    // Assume screen is on for demo purposes
    return true;
  }
}

// Mock class for backward compatibility
class MockScreenTimeService {
  static Future<int> getScreenTimeMinutes(String packageName, DateTime startTime) async {
    return 5;
  }

  static Future<bool> isScreenOn() async {
    return true;
  }
}