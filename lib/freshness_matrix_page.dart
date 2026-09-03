import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'inventory_data.dart';
import 'app_sidebar.dart';

class FreshnessMatrixPage extends StatefulWidget {
  final String role;
  const FreshnessMatrixPage({super.key, this.role = 'employee'});

  @override
  State<FreshnessMatrixPage> createState() => _FreshnessMatrixPageState();
}

class _FreshnessMatrixPageState extends State<FreshnessMatrixPage> {
  Color _scoreColor(int score) {
    if (score > 70) return Colors.green;
    if (score > 40) return Colors.orange;
    return const Color(0xFFE91E63);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'freshness')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'freshness'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  if (!isDesktop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                      child: Row(
                        children: [
                          Builder(builder: (ctx) => IconButton(
                            icon: Icon(Icons.menu, color: textColor),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          )),
                          Text('Freshness Matrix',
                              style: GoogleFonts.cormorantGaramond(color: textColor, fontWeight: FontWeight.bold, fontSize: 22)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.freshnessStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: textColor)));
                        }

                        final all = snapshot.data ?? [];
                        // CONFIRMED from freshness_analysis.php: both the
                        // table AND the stat cards only ever consider the
                        // most recent 10 scans.
                        final displayScans = all.take(10).toList();

                        int total = 0, healthy = 0, discount = 0, critical = 0;
                        for (final s in displayScans) {
                          total++;
                          final score = (s['freshnessScore'] ?? 0) as int;
                          final status = (s['status'] ?? '').toString();
                          if (status == 'Healthy') healthy++;
                          if (score >= 30 && score <= 60) discount++;
                          if (score < 30) critical++;
                        }

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Freshness Matrix',
                                style: GoogleFonts.cormorantGaramond(fontSize: isDesktop ? 32 : 24, fontWeight: FontWeight.bold, color: textColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Computer vision metrics for botanical integrity and shelf-life prediction.',
                                style: TextStyle(fontSize: 12, color: subTextColor),
                              ),
                              const SizedBox(height: 20),

                              _statRow([
                                _statBox('PROCESSED', '$total', textColor, subTextColor, cardColor, borderColor, null),
                                _statBox('PEAK FRESHNESS', '$healthy', textColor, subTextColor, cardColor, borderColor, Colors.green),
                                _statBox('DISCOUNT THRESHOLD', '$discount', textColor, subTextColor, cardColor, borderColor, Colors.orange),
                                _statBox('CRITICAL DECAY', '$critical', textColor, subTextColor, cardColor, borderColor, const Color(0xFFE91E63)),
                              ], isDesktop),
                              const SizedBox(height: 24),

                              if (displayScans.isEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 60),
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                                  child: Text('Awaiting neural telemetry from mobile nodes...',
                                      style: TextStyle(color: subTextColor, fontStyle: FontStyle.italic)),
                                )
                              else
                                ...displayScans.map((scan) => _buildScanCard(scan, isDark, cardColor, borderColor, textColor, subTextColor)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(List<Widget> boxes, bool isDesktop) {
    if (isDesktop) {
      return Row(children: boxes.map((b) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: b))).toList());
    }
    return Column(
      children: [
        Row(children: [Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: boxes[0])), Expanded(child: Padding(padding: const EdgeInsets.only(left: 6), child: boxes[1]))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: boxes[2])), Expanded(child: Padding(padding: const EdgeInsets.only(left: 6), child: boxes[3]))]),
      ],
    );
  }

  // FIXED: minHeight guarantees the box never gets squeezed shorter than
  // both children genuinely need; FittedBox on the value number means IT
  // shrinks under pressure instead of silently starving the label of
  // space; label now wraps to 2 lines instead of forcing 1 line — this
  // is exactly what was making "Peak Freshness" and "Discount Threshold"
  // (both accent-bordered, both longer labels) render blank on narrow
  // 2-column layouts.
  Widget _statBox(String label, String value, Color textColor, Color subTextColor, Color cardColor, Color borderColor, Color? accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: BorderSide(color: accent ?? borderColor, width: accent != null ? 3 : 1),
          left: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(Map<String, dynamic> scan, bool isDark, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    final int score = scan['freshnessScore'] ?? 0;
    final String status = scan['status'] ?? 'Unknown';
    final bool isRecycled = scan['is_recycled'] == true;
    final color = _scoreColor(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scan['productName'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    Text('Analysis from AI Vision', style: TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: Text('$score%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Text(
              scan['aiRecommendation'] ?? 'No recommendation available.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: isDark ? Colors.grey[300] : Colors.grey[700]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDate(scan['scanned_at'] ?? scan['createdAt']), style: TextStyle(fontSize: 10, color: subTextColor)),
              if (score < 40 && !isRecycled)
                ElevatedButton.icon(
                  onPressed: () => _showRecycleConfirm(scan),
                  icon: const Icon(Icons.recycling_rounded, size: 14),
                  label: const Text('RECYCLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )
              else if (isRecycled)
                const Text('SALVAGED ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return timestamp.toString();
  }

  void _showRecycleConfirm(Map<String, dynamic> scan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Recycle?'),
        content: Text('Convert all remaining stock of ${scan['productName']} into Recycled Bouquets (₱150)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                Navigator.pop(context);
                await InventoryData.recycleFromAnalysis(
                  productName: scan['productName'],
                  quantity: 0,
                  analysisId: scan['id'],
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Successfully salvaged and recycled!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('PROCEED'),
          ),
        ],
      ),
    );
  }
}