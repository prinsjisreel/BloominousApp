import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

class LowStockAlertsPage extends StatefulWidget {
  final String role;
  const LowStockAlertsPage({super.key, this.role = 'employee'});

  @override
  State<LowStockAlertsPage> createState() => _LowStockAlertsPageState();
}

class _LowStockAlertsPageState extends State<LowStockAlertsPage> {
  bool _isAnalyzing = false;
  String? _aiSuggestion;

  static const String _geminiApiKey = 'AIzaSyDF4jJULCnYTCcBrhGrHH8eoia3x6xpVbE';

  Future<void> _getAISuggestions(
      List<Map<String, dynamic>> lowStockItems) async {
    if (lowStockItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No low stock items to analyze!')));
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _aiSuggestion = null;
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
      );

      final itemsList = lowStockItems
          .map((item) => "${item['name']} (Stock: ${item['stock']})")
          .join(", ");
      final prompt = """
        You are a smart inventory assistant for 'BloomyPro', an AR Flower Shop.
        The following items are low on stock: $itemsList.
        
        Today's date is ${DateTime.now().toString()}. 
        Consider upcoming events (like Valentine's Day, Mother's Day, or local flower trends).
        
        Provide a concise restocking strategy:
        1. Which flowers to prioritize for restocking.
        2. Suggested quantities to order.
        3. A brief reason based on seasonal trends or the current items.
        
        Format the response clearly with bullet points.
      """;

      final response = await model.generateContent([Content.text(prompt)]);

      setState(() {
        _aiSuggestion = response.text;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('AI Error: $e')));
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LOW STOCK ALERTS',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
      ),
      // NEW: sidebar drawer on mobile — same pattern as every other
      // portal page. Setting `drawer` makes Scaffold auto-draw the
      // hamburger icon in the existing AppBar above.
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'alerts')),
      body: Row(
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'alerts'),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.lowStockStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data ?? [];

                return Column(
                  children: [
                    Expanded(
                      child: items.isEmpty
                          ? _buildEmptyState(isDark)
                          : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _buildLowStockCard(item, isDark);
                        },
                      ),
                    ),
                    if (items.isNotEmpty) _buildAISuggestionSection(items, isDark),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 80, color: Colors.green.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'All stock levels are healthy!',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockCard(Map<String, dynamic> item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              item['image'] ?? '',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported)),
            ),
          ),
          const SizedBox(width: 16),
          // FIXED: name and stock line now guard against overflow with
          // ellipsis/maxLines, so a long product name can't push the
          // Restock button off the card's edge on a narrow phone.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Current Stock: ${item['stock']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink.shade50,
              foregroundColor: Colors.pink,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Restock'),
          ),
        ],
      ),
    );
  }

  Widget _buildAISuggestionSection(
      List<Map<String, dynamic>> items, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.purple),
              const SizedBox(width: 12),
              // FIXED: wrapped in Expanded — "SMART RESTOCKING" is short
              // enough to rarely be an issue, but any future label change
              // (or a device with enlarged system font size) now wraps
              // safely instead of risking overflow next to the icon.
              Expanded(
                child: Text(
                  'SMART RESTOCKING',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.purple,
                      fontSize: 12,
                      letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_aiSuggestion != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.withOpacity(0.1)),
              ),
              child: Text(
                _aiSuggestion!,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark ? Colors.white : Colors.black87),
              ),
            ),
          ElevatedButton(
            onPressed: _isAnalyzing ? null : () => _getAISuggestions(items),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _isAnalyzing
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            // FittedBox guard on the label, same pattern as the Save
            // Thresholds button fix from earlier — never overflows
            // its own button on a squeezed layout.
                : const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Get AI Restock Suggestions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}