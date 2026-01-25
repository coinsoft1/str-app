import 'package:flutter/material.dart';
import 'dart:async'; // ✅ FIX: Import Timer
import '../services/deduction_service.dart';

class DeductionMonitor extends StatefulWidget {
  final Widget child;
  
  const DeductionMonitor({super.key, required this.child});

  @override
  State<DeductionMonitor> createState() => _DeductionMonitorState();
}

class _DeductionMonitorState extends State<DeductionMonitor> {
  @override
  void initState() {
    super.initState();
    // Start monitoring when widget is created
    DeductionService.startMonitoring();
  }

  @override
  void dispose() {
    // Don't stop monitoring when widget disposes - let main.dart handle it
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}