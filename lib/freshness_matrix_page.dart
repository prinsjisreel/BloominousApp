import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_data.dart';

class FreshnessMatrixPage extends StatefulWidget {
  const FreshnessMatrixPage({super.key});

  @override
  State<FreshnessMatrixPage> createState() => _FreshnessMatrixPageState();
}

class _FreshnessMatrixPageState extends State<FreshnessMatrixPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'FRESHNESS MATRIX',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.freshnessStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final scans = snapshot.data ?? [];
          if (scans.isEmpty) {
            return const Center(
                child: Text('No scans found. Use the AI Scanner first! 🌸'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: scans.length,
            itemBuilder: (context, index) {
              final scan = scans[index];
              final int score = scan['freshnessScore'] ?? 0;
              final String status = scan['status'] ?? 'Unknown';
              final bool isRecycled = scan['is_recycled'] == true;

              Color statusColor = Colors.green;
              if (score < 40)
                statusColor = Colors.red;
              else if (score < 70) statusColor = Colors.orange;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  scan['productName'] ?? 'Unknown',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                                Text(
                                  'Analysis from AI Vision',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          _buildScoreIndicator(score, statusColor),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: statusColor.withOpacity(0.1)),
                        ),
                        child: Text(
                          scan['aiRecommendation'] ??
                              'No recommendation available.',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(
                                scan['scanned_at'] ?? scan['createdAt']),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[400]),
                          ),
                          if (score < 40 && !isRecycled)
                            ElevatedButton.icon(
                              onPressed: () => _showRecycleConfirm(scan),
                              icon:
                                  const Icon(Icons.recycling_rounded, size: 14),
                              label: const Text('RECYCLE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            )
                          else if (isRecycled)
                            const Text(
                              'SALVAGED ✓',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildScoreIndicator(int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$score%',
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
        content: Text(
            'Convert all remaining stock of ${scan['productName']} into Recycled Bouquets (₱150)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                Navigator.pop(context);
                await InventoryData.recycleFromAnalysis(
                  productName: scan['productName'],
                  quantity: 0, // Auto-detect full stock
                  analysisId: scan['id'],
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Successfully salvaged and recycled!'),
                        backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red),
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
