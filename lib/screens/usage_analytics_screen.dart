// lib/screens/usage_analytics_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class UsageAnalyticsScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const UsageAnalyticsScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<UsageAnalyticsScreen> createState() => _UsageAnalyticsScreenState();
}

class _UsageAnalyticsScreenState extends State<UsageAnalyticsScreen> {
  String _timeRange = 'today';
  String _chartView = 'ed_vs_ent';
  bool _isLoading = false;
  bool _isExporting = false;

  List<Map<String, dynamic>> _verifiedEntries = [];
  Map<String, dynamic> _summaryData = {
    'educational': 0,
    'entertainment': 0,
    'utility': 0,
    'total': 0,
  };
  List<Map<String, dynamic>> _chartData = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'educational': return Colors.green;
      case 'entertainment': return Colors.orange;
      case 'social': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getCategoryEmoji(String? category) {
    switch (category?.toLowerCase()) {
      case 'educational': return '🎓';
      case 'entertainment': return '🎮';
      case 'social': return '👥';
      default: return '📱';
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      switch (_timeRange) {
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'today':
        default:
          startDate = DateTime(now.year, now.month, now.day);
          endDate = startDate.add(const Duration(days: 1));
          break;
      }

      // FIXED: Read from sessionLogs where trust_ladder_service writes data
      final entriesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.childId)
          .collection('sessionLogs')
          .get();

      _verifiedEntries = entriesSnapshot.docs
          .map((doc) => doc.data())
          .where((entry) {
        // Filter: must be verified or corrected
        final status = entry['status'] as String?;
        if (status != 'verified' && status != 'corrected') return false;

        // Filter: within selected date range
        final startTimeRaw = entry['startTime'];
        DateTime? entryDate;
        if (startTimeRaw is Timestamp) {
          entryDate = startTimeRaw.toDate();
        }
        if (entryDate == null) return false;

        return entryDate.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            entryDate.isBefore(endDate.add(const Duration(seconds: 1)));
      })
          .toList();

      // Sort by startTime descending
      _verifiedEntries.sort((a, b) {
        final aTime = (a['startTime'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bTime = (b['startTime'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      // Calculate totals for the SELECTED PERIOD
      int eduTotal = 0;
      int entTotal = 0;
      int utilTotal = 0;

      Map<String, Map<String, int>> dailyMap = {};

      for (var entry in _verifiedEntries) {
        final entryDate = (entry['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateKey = '${entryDate.year}-${entryDate.month.toString().padLeft(2, '0')}-${entryDate.day.toString().padLeft(2, '0')}';

        if (!dailyMap.containsKey(dateKey)) {
          dailyMap[dateKey] = {'educational': 0, 'entertainment': 0, 'utility': 0};
        }

        final category = entry['category'] as String? ?? 'Other';
        final duration = (entry['durationMinutes'] as num?)?.toInt() ?? 0;

        if (category.toLowerCase() == 'educational') {
          dailyMap[dateKey]!['educational'] = dailyMap[dateKey]!['educational']! + duration;
          eduTotal += duration;
        } else if (category.toLowerCase() == 'entertainment') {
          dailyMap[dateKey]!['entertainment'] = dailyMap[dateKey]!['entertainment']! + duration;
          entTotal += duration;
        } else {
          dailyMap[dateKey]!['utility'] = dailyMap[dateKey]!['utility']! + duration;
          utilTotal += duration;
        }
      }

      final sortedDates = dailyMap.keys.toList()..sort();

      _chartData = sortedDates.map((date) => {
        'date': date,
        'educational': dailyMap[date]!['educational'],
        'entertainment': dailyMap[date]!['entertainment'],
        'utility': dailyMap[date]!['utility'],
      }).toList();

      setState(() {
        _summaryData = {
          'educational': eduTotal,
          'entertainment': entTotal,
          'utility': utilTotal,
          'total': eduTotal + entTotal + utilTotal,
        };
      });

    } catch (e, stack) {
      print('Error loading analytics: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showExportDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share, color: Colors.blue),
            SizedBox(width: 8),
            Text('Export Report'),
          ],
        ),
        content: Text(
          'Choose format to export screen time report for ${widget.childName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportCSV();
            },
            icon: const Icon(Icons.table_chart),
            label: const Text('CSV Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPDF() async {
    setState(() => _isExporting = true);

    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final periodLabel = _getPeriodLabel();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Screen Time Report',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Child: ${widget.childName}',
                  style: pw.TextStyle(fontSize: 16),
                ),
                pw.Text(
                  'Period: $periodLabel',
                  style: pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Generated: ${_formatDateFull(now)}',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey),
                ),
                pw.Divider(),
                pw.SizedBox(height: 16),

                pw.Text(
                  'Summary',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.green),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Educational',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.Text(
                              '${_summaryData['educational']} minutes',
                              style: pw.TextStyle(
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Entertainment',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.Text(
                              '${_summaryData['entertainment']} minutes',
                              style: pw.TextStyle(
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Total',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.Text(
                              '${_summaryData['total']} minutes',
                              style: pw.TextStyle(
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                pw.Text(
                  'Daily Breakdown',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Educational', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Entertainment', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                    ..._chartData.map((day) {
                      final edu = (day['educational'] as num?)?.toInt() ?? 0;
                      final ent = (day['entertainment'] as num?)?.toInt() ?? 0;
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(day['date'] as String),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$edu min'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$ent min'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('${edu + ent} min', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
                pw.SizedBox(height: 24),

                pw.Text(
                  'Activity Log (${_verifiedEntries.length} entries)',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                ..._verifiedEntries.take(20).map((entry) {
                  final startTime = (entry['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final appName = entry['appName'] as String? ?? 'Unknown';
                  final category = entry['category'] as String? ?? 'Other';
                  final duration = (entry['durationMinutes'] as num?)?.toInt() ?? 0;
                  final note = entry['parentNote'] as String? ?? '';

                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(_formatDateFull(startTime)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(appName),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            category,
                            style: pw.TextStyle(
                              color: category.toLowerCase() == 'educational'
                                  ? PdfColors.green
                                  : category.toLowerCase() == 'entertainment'
                                  ? PdfColors.orange
                                  : PdfColors.blue,
                            ),
                          ),
                        ),
                        pw.Text('$duration min'),
                      ],
                    ),
                  );
                }).toList(),
                if (_verifiedEntries.length > 20)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Text(
                      '... and ${_verifiedEntries.length - 20} more entries',
                      style: pw.TextStyle(color: PdfColors.grey, fontStyle: pw.FontStyle.italic),
                    ),
                  ),
              ],
            );
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/screen_time_report_${widget.childName.replaceAll(' ', '_')}_${_timeRange}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Screen Time Report for ${widget.childName} - $periodLabel',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportCSV() async {
    setState(() => _isExporting = true);

    try {
      final buffer = StringBuffer();
      final periodLabel = _getPeriodLabel();

      buffer.writeln('Screen Time Report');
      buffer.writeln('Child: ${widget.childName}');
      buffer.writeln('Period: $periodLabel');
      buffer.writeln('Generated: ${DateTime.now()}');
      buffer.writeln('');

      buffer.writeln('SUMMARY');
      buffer.writeln('Educational,${_summaryData['educational']}');
      buffer.writeln('Entertainment,${_summaryData['entertainment']}');
      buffer.writeln('Utility,${_summaryData['utility']}');
      buffer.writeln('Total,${_summaryData['total']}');
      buffer.writeln('');

      buffer.writeln('DAILY_BREAKDOWN');
      buffer.writeln('Date,Educational,Entertainment,Utility,Total');
      for (var day in _chartData) {
        final edu = (day['educational'] as num?)?.toInt() ?? 0;
        final ent = (day['entertainment'] as num?)?.toInt() ?? 0;
        final util = (day['utility'] as num?)?.toInt() ?? 0;
        buffer.writeln('${day['date']},$edu,$ent,$util,${edu + ent + util}');
      }
      buffer.writeln('');

      buffer.writeln('ACTIVITY_LOG');
      buffer.writeln('Date,Time,App Name,Category,Duration (min),Notes');
      for (var entry in _verifiedEntries) {
        final startTime = (entry['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
        final appName = entry['appName'] as String? ?? 'Unknown';
        final category = entry['category'] as String? ?? 'Other';
        final duration = (entry['durationMinutes'] as num?)?.toInt() ?? 0;
        final note = entry['parentNote'] as String? ?? '';
        buffer.writeln('${_formatDateCSV(startTime)},${_formatTimeCSV(startTime)},$appName,$category,$duration,$note');
      }

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/screen_time_data_${widget.childName.replaceAll(' ', '_')}_${_timeRange}.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Screen Time Data for ${widget.childName} - $periodLabel (CSV)',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _getPeriodLabel() {
    switch (_timeRange) {
      case 'week':
        return 'Last 7 Days';
      case 'month':
        return 'Last 30 Days';
      case 'today':
      default:
        return 'Today (${DateTime.now().toString().split(' ')[0]})';
    }
  }

  String _formatDateFull(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateCSV(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTimeCSV(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final educational = (_summaryData['educational'] as num?)?.toInt() ?? 0;
    final entertainment = (_summaryData['entertainment'] as num?)?.toInt() ?? 0;
    final total = educational + entertainment;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Activity'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') {
                _showExportDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Export Report'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeRangeSelector(),
                  const SizedBox(height: 16),
                  _buildChartViewSelector(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Educational',
                          educational,
                          Colors.green,
                          Icons.school,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Entertainment',
                          entertainment,
                          Colors.orange,
                          Icons.sports_esports,
                        ),
                      ),
                    ],
                  ),
                  if (total == 0 && _verifiedEntries.isEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No verified entries found for this period',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    _getChartTitle(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildChart(),
                  const SizedBox(height: 24),
                  if (_verifiedEntries.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Verified Entries (${_verifiedEntries.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'All Verified',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._verifiedEntries.take(10).map((entry) {
                      final category = entry['category'] as String? ?? 'Other';
                      final appName = entry['appName'] as String? ?? 'Unknown';
                      final duration = (entry['durationMinutes'] as num?)?.toInt() ?? 0;
                      final startTime = (entry['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getCategoryColor(category).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getCategoryEmoji(category),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                          title: Text(
                            appName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '$duration min • ${_formatDate(startTime)}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '✓ Verified',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
          if (_isExporting)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Generating report...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getChartTitle() {
    switch (_chartView) {
      case 'ed_trend':
        return 'Educational Trend';
      case 'ent_trend':
        return 'Entertainment Trend';
      case 'ed_vs_ent':
      default:
        return 'Educational vs Entertainment';
    }
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTimeButton('Today', 'today'),
          _buildTimeButton('7 Days', 'week'),
          _buildTimeButton('30 Days', 'month'),
        ],
      ),
    );
  }

  Widget _buildTimeButton(String label, String value) {
    final isSelected = _timeRange == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _timeRange = value);
          _loadData();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black87 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartViewSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildViewButton(
            'Ed vs Ent',
            'ed_vs_ent',
            Icons.compare_arrows,
            Colors.purple,
            Colors.purple.shade400,
            Colors.purple.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildViewButton(
            'Ed Trend',
            'ed_trend',
            Icons.trending_up,
            Colors.green,
            Colors.green.shade400,
            Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildViewButton(
            'Ent Trend',
            'ent_trend',
            Icons.trending_up,
            Colors.orange,
            Colors.orange.shade400,
            Colors.orange.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildViewButton(String label, String value, IconData icon, Color baseColor, Color lightColor, Color darkColor) {
    final isSelected = _chartView == value;
    return GestureDetector(
      onTap: () => setState(() => _chartView = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
            colors: [lightColor, darkColor],
          )
              : null,
          color: isSelected ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : baseColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatCard(String label, int minutes, Color color, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$minutes min',
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return Card(
        child: Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          child: const Center(
            child: Text(
              'No data for selected period',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _calculateMaxY(),
                  minY: 0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBorder: BorderSide(color: Colors.blueGrey),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final data = _chartData[groupIndex];
                        final date = data['date'] as String;
                        String label;
                        String value;

                        if (_chartView == 'ed_vs_ent') {
                          label = rodIndex == 0 ? 'Educational' : 'Entertainment';
                          value = '${rod.toY.toInt()} min';
                        } else if (_chartView == 'ed_trend') {
                          label = 'Educational';
                          value = '${rod.toY.toInt()} min';
                        } else {
                          label = 'Entertainment';
                          value = '${rod.toY.toInt()} min';
                        }

                        return BarTooltipItem(
                          '$date\n$label: $value',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _chartData.length) {
                            final date = _chartData[index]['date'] as String;
                            final parts = date.split('-');
                            if (parts.length >= 3) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${parts[1]}/${parts[2]}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            }
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: _calculateInterval(),
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '${value.toInt()}m',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: _calculateInterval(),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _buildBarGroups(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_chartView == 'ed_vs_ent')
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem('Educational', Colors.green),
                  const SizedBox(width: 24),
                  _buildLegendItem('Entertainment', Colors.orange),
                ],
              )
            else if (_chartView == 'ed_trend')
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem('Educational Trend', Colors.green),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem('Entertainment Trend', Colors.orange),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    return _chartData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;

      final educational = (data['educational'] as num?)?.toDouble() ?? 0;
      final entertainment = (data['entertainment'] as num?)?.toDouble() ?? 0;

      List<BarChartRodData> rods = [];

      if (_chartView == 'ed_vs_ent') {
        rods = [
          BarChartRodData(
            toY: educational,
            color: Colors.green,
            width: 12,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          BarChartRodData(
            toY: entertainment,
            color: Colors.orange,
            width: 12,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ];
      } else if (_chartView == 'ed_trend') {
        rods = [
          BarChartRodData(
            toY: educational,
            color: Colors.green,
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ];
      } else {
        rods = [
          BarChartRodData(
            toY: entertainment,
            color: Colors.orange,
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ];
      }

      return BarChartGroupData(
        x: index,
        barRods: rods,
        barsSpace: _chartView == 'ed_vs_ent' ? 4 : 0,
      );
    }).toList();
  }

  double _calculateMaxY() {
    if (_chartData.isEmpty) return 100;

    double max = 0;
    for (var data in _chartData) {
      final edu = (data['educational'] as num?)?.toDouble() ?? 0;
      final ent = (data['entertainment'] as num?)?.toDouble() ?? 0;

      if (_chartView == 'ed_vs_ent') {
        if (edu > max) max = edu;
        if (ent > max) max = ent;
      } else if (_chartView == 'ed_trend') {
        if (edu > max) max = edu;
      } else {
        if (ent > max) max = ent;
      }
    }

    return max > 0 ? max * 1.2 : 100;
  }

  double _calculateInterval() {
    final maxY = _calculateMaxY();
    if (maxY <= 50) return 10;
    if (maxY <= 100) return 20;
    if (maxY <= 200) return 40;
    if (maxY <= 500) return 100;
    return 200;
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}