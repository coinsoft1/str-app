import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/usage_entry.dart';
import '../services/usage_tracking_service.dart';

class UsageVerificationScreen extends StatefulWidget {
  const UsageVerificationScreen({super.key});

  @override
  State<UsageVerificationScreen> createState() => _UsageVerificationScreenState();
}

class _UsageVerificationScreenState extends State<UsageVerificationScreen> {
  final service = UsageTrackingService();
  String? _selectedChildId;
  String? _selectedChildName;
  List<Map<String, dynamic>> _children = [];

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final parentId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: parentId)
        .get();
    
    setState(() {
      _children = snapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'] ?? 'Child',
        'data': doc.data(),
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Usage Logs'),
        centerTitle: true,
        actions: [
          if (_children.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter by child',
              onSelected: (childId) {
                setState(() {
                  if (childId == 'all') {
                    _selectedChildId = null;
                    _selectedChildName = null;
                  } else {
                    _selectedChildId = childId;
                    _selectedChildName = _children.firstWhere(
                      (c) => c['id'] == childId,
                    )['name'] as String?;
                  }
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'all',
                  child: Text('All Children'),
                ),
                ..._children.map((child) {
                  final String childId = child['id'] as String;
                  final String childName = child['name'] as String;
                  return PopupMenuItem<String>(
                    value: childId,
                    child: Text(childName),
                  );
                }).toList(),
              ],
            ),
        ],
      ),
      body: StreamBuilder<List<UsageEntry>>(
        stream: service.getPendingVerifications(
          FirebaseAuth.instance.currentUser!.uid,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading data',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          var entries = snapshot.data ?? [];
          
          // Filter by selected child if specified
          if (_selectedChildId != null) {
            entries = entries.where((e) => e.childId == _selectedChildId).toList();
          }

          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedChildId != null 
                      ? 'No pending verifications for ${_selectedChildName ?? 'this child'}'
                      : 'No pending verifications',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (_children.isEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Make sure your children are linked to your account',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ],
              ),
            );
          }

          return Column(
            children: [
              if (_selectedChildId != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Showing: $_selectedChildName',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() {
                          _selectedChildId = null;
                          _selectedChildName = null;
                        }),
                        child: Icon(Icons.close, size: 16, color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _buildVerificationCard(context, entry, service);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVerificationCard(BuildContext context, UsageEntry entry, UsageTrackingService service) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: entry.category.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.category.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.appName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${entry.durationMinutes} minutes • ${entry.category.displayName}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'By: ${_children.firstWhere(
                          (c) => c['id'] == entry.childId,
                          orElse: () => {'name': 'Unknown'},
                        )['name']}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: Colors.grey.shade400, width: 4)),
                ),
                child: Text(
                  entry.notes!,
                  style: TextStyle(color: Colors.grey[800], fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await service.verifyEntry(entry.childId, entry.id, true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('✅ Entry approved'),
                              backgroundColor: Colors.green.shade600,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await service.verifyEntry(entry.childId, entry.id, false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('❌ Entry rejected'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Extension to add color to UsageCategory
extension UsageCategoryExtension on UsageCategory {
  Color get color {
    switch (this) {
      case UsageCategory.educational:
        return Colors.green;
      case UsageCategory.entertainment:
        return Colors.orange;
      case UsageCategory.utility:
        return Colors.blue;
    }
  }
}