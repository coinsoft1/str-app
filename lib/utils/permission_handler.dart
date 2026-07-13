import 'dart:io';
import 'package:flutter/material.dart';
import '../services/screen_time_service.dart';

class PermissionHandler {
  static Future<bool> checkAndRequestUsageStats(BuildContext context) async {
    final service = ScreenTimeService();
    final hasPermission = await service.checkPermission();
    
    if (hasPermission) return true;
    
    // Show explanation dialog
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.orange),
            SizedBox(width: 8),
            Text('Permission Required'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To automatically track screen time and deduct points when limits are exceeded, STR App needs "Usage Access" permission.',
            ),
            SizedBox(height: 12),
            Text(
              'This permission allows the app to:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('• Monitor how long apps are used\n• Enforce screen time limits\n• Protect your child\'s points automatically'),
            SizedBox(height: 12),
            Text(
              'No personal data leaves your device.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
    
    if (shouldOpenSettings == true) {
      await service.requestPermission();
      // Wait a moment then check again
      await Future.delayed(const Duration(seconds: 2));
      return await service.checkPermission();
    }
    
    return false;
  }
}