// lib/screens/parent/goal_history_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class GoalHistoryScreen extends StatefulWidget {
  const GoalHistoryScreen({super.key});

  @override
  State<GoalHistoryScreen> createState() => _GoalHistoryScreenState();
}

class _GoalHistoryScreenState extends State<GoalHistoryScreen> {
  String _familyId = '';

  @override
  void initState() {
    super.initState();
    _loadFamilyId();
  }

  Future<void> _loadFamilyId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      setState(() => _familyId = (doc.data()?['familyId'] ?? '') as String);
    }
  }

  Future<void> _exportReport(List<QueryDocumentSnapshot> docs) async {
    final pdf = pw.Document();
    final goals = docs.map((d) => d.data() as Map<String, dynamic>).toList();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Goal History Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Text('Generated on ${DateTime.now().toString().split(' ').first}', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 24),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _header('Title'),
                    _header('Status'),
                    _header('Start Date'),
                    _header('End Date'),
                    _header('Progress'),
                  ],
                ),
                ...goals.map((g) {
                  final start = (g['startDate'] as Timestamp?)?.toDate();
                  final end = (g['endDate'] as Timestamp?)?.toDate();
                  return pw.TableRow(
                    children: [
                      _cell(g['title'] ?? 'Untitled'),
                      _cell(g['status'] ?? 'unknown'),
                      _cell(start != null ? '${start.month}/${start.day}/${start.year}' : '-'),
                      _cell(end != null ? '${end.month}/${end.day}/${end.year}' : '-'),
                      _cell('${g['progressPercent'] ?? 0}%'),
                    ],
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/goal_history_report.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'STR App - Goal History Report');
  }

  pw.Widget _header(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _cell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'expired':
        return Colors.orange;
      case 'deleted':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(title: const Text('Goal History'), elevation: 0),
      body: _familyId.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('goals').where('familyId', isEqualTo: _familyId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs.where((doc) {
            final status = (doc.data() as Map<String, dynamic>)['status'] as String?;
            return status == 'expired' || status == 'deleted' || status == 'completed';
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No goal history yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _exportReport(docs),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF Report'),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status'] as String? ?? 'unknown';
                    final start = (data['startDate'] as Timestamp?)?.toDate();
                    final end = (data['endDate'] as Timestamp?)?.toDate();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          status == 'completed' ? Icons.check_circle : status == 'expired' ? Icons.timer_off : Icons.delete,
                          color: _statusColor(status),
                        ),
                        title: Text(data['title'] ?? 'Untitled'),
                        subtitle: Text(
                          '${start != null ? '${start.month}/${start.day}/${start.year}' : '-'} — ${end != null ? '${end.month}/${end.day}/${end.year}' : '-'}',
                        ),
                        trailing: Chip(
                          label: Text(status.toUpperCase()),
                          backgroundColor: _statusColor(status).withOpacity(0.1),
                          side: BorderSide(color: _statusColor(status)),
                          labelStyle: TextStyle(color: _statusColor(status), fontSize: 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}