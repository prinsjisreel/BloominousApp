import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'inventory_data.dart';
import 'app_sidebar.dart';
import 'restock_ai_service.dart';

/// AI Stock Alerts — lists products at or below the low-stock threshold,
/// lets staff restock them, and asks Gemini for a restocking plan.
class LowStockAlertsPage extends StatefulWidget {
  final String role;
  const LowStockAlertsPage({super.key, this.role = 'employee'});

  @override
  State<LowStockAlertsPage> createState() => _LowStockAlertsPageState();
}

class _LowStockAlertsPageState extends State<LowStockAlertsPage> {
  // Bloominous theme tokens (same gold / ink used across the app).
  static const Color _gold = Color(0xFFF59E0B);
  static const Color _ink = Color(0xFF121212);
  static const int _threshold = 10; // must match lowStockStream's default

  // Created ONCE so a rebuild (keyboard, rotation) never restarts the stream.
  late final Stream<List<Map<String, dynamic>>> _lowStockStream;

  bool _isAnalyzing = false;
  RestockSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _lowStockStream = InventoryData.lowStockStream(threshold: _threshold);
  }

  // ── Gemini suggestion ────────────────────────────────────────────────
  Future<void> _getAISuggestions(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      _snack('No low stock items to analyze!');
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _suggestion = null;
    });

    try {
      final result = await RestockAiService.suggest(items
          .map((i) => RestockItem(
        name: (i['name'] ?? 'Unknown').toString(),
        stock: ((i['stock'] ?? 0) as num).toInt(),
        price: ((i['price'] ?? 0) as num).toDouble(),
        category: (i['category'] ?? 'Flowers').toString(),
      ))
          .toList());
      if (mounted) setState(() => _suggestion = result);
    } catch (e) {
      _snack('Could not get a suggestion: $e', error: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ── Restock ──────────────────────────────────────────────────────────
  Future<void> _showRestockDialog(Map<String, dynamic> item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: '20');
    final name = (item['name'] ?? 'Product').toString();
    final current = ((item['stock'] ?? 0) as num).toInt();

    final qty = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Restock $name',
                style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 22)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current stock: $current',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Quantity to add',
                    errorText: errorText,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [10, 20, 50]
                      .map((n) => ActionChip(
                    label: Text('+$n'),
                    onPressed: () => setDialogState(() => controller.text = '$n'),
                  ))
                      .toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: _ink,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final value = int.tryParse(controller.text.trim());
                  if (value == null || value <= 0) {
                    setDialogState(() => errorText = 'Enter a number above 0');
                    return;
                  }
                  if (value > 10000) {
                    setDialogState(() => errorText = 'That looks too large');
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('ADD STOCK', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          );
        });
      },
    );
    // (Not disposed on purpose: the dialog's closing animation can still
    // touch the controller, and disposing it early throws an error.)
    if (qty == null) return;

    try {
      await InventoryData.updateStock(item['id'] as String, qty);
      _snack('Added $qty to $name. New stock: ${current + qty}.');
      // No manual refresh: the live stream updates the list, and the item
      // disappears from here once it is above the low-stock threshold.
    } catch (e) {
      _snack('Could not restock: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : Colors.green,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final card = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final border = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final text = isDark ? Colors.white : const Color(0xFF1E293B);
    final sub = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('AI STOCK ALERTS',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: isDark ? Colors.black : _ink,
        foregroundColor: const Color(0xFFF4B400),
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'alerts')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'alerts'),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _lowStockStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _gold));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: text)));
                }

                // Lowest stock first, so the most urgent are on top.
                // The type is written out on purpose: with `?? []` Dart guesses
                // List<dynamic>, which _aiSection() rejects.
                final List<Map<String, dynamic>> items = [...(snapshot.data ?? <Map<String, dynamic>>[])]
                  ..sort((a, b) => ((a['stock'] ?? 0) as num).compareTo((b['stock'] ?? 0) as num));
                final outCount = items.where((i) => ((i['stock'] ?? 0) as num) <= 0).length;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    Text('Stock Alerts',
                        style: GoogleFonts.cormorantGaramond(
                            fontSize: isDesktop ? 32 : 26, fontWeight: FontWeight.bold, color: text)),
                    const SizedBox(height: 4),
                    Text('Products at or below $_threshold pieces, with AI restocking advice.',
                        style: TextStyle(fontSize: 12, color: sub)),
                    const SizedBox(height: 18),

                    Row(children: [
                      Expanded(child: _statBox('LOW STOCK', '${items.length}', _gold, card, border, text, sub)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statBox('OUT OF STOCK', '$outCount', const Color(0xFFE91E63), card, border, text, sub)),
                    ]),
                    const SizedBox(height: 22),

                    if (items.isEmpty)
                      _emptyState(card, border, text, sub)
                    else ...[
                      ...items.map((i) => _lowStockCard(i, card, border, text, sub)),
                      const SizedBox(height: 8),
                      _aiSection(items, isDark, card, border, text, sub),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Accent strip INSIDE a uniformly-bordered box (a differently coloured
  // single border side plus rounded corners does not paint in Flutter).
  Widget _statBox(String label, String value, Color accent, Color card, Color border, Color text, Color sub) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: accent),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sub, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(value, style: GoogleFonts.cormorantGaramond(fontSize: 30, fontWeight: FontWeight.bold, color: text)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(Color card, Color border, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('All stock levels are healthy!',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: text)),
          const SizedBox(height: 4),
          Text('Nothing needs restocking right now.', style: TextStyle(fontSize: 12, color: sub)),
        ],
      ),
    );
  }

  Widget _lowStockCard(Map<String, dynamic> item, Color card, Color border, Color text, Color sub) {
    final stock = ((item['stock'] ?? 0) as num).toInt();
    final isOut = stock <= 0;
    final isCritical = stock <= 5;
    final level = isOut ? const Color(0xFFE91E63) : (isCritical ? Colors.deepOrange : _gold);
    final label = isOut ? 'OUT OF STOCK' : (isCritical ? 'CRITICAL' : 'LOW');
    // .clamp() returns a generic 'num'; the progress bar needs a double.
    final double progress = (stock / _threshold).clamp(0.0, 1.0).toDouble();
    final image = (item['image'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: image.isEmpty
                  ? Container(color: Colors.grey.withValues(alpha: 0.15), child: const Icon(Icons.local_florist))
                  : Image.network(image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.withValues(alpha: 0.15), child: const Icon(Icons.image_not_supported))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((item['name'] ?? 'Unknown').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: text)),
                const SizedBox(height: 6),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: level.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                    child: Text(label,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: level, letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text('$stock left', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: border,
                    valueColor: AlwaysStoppedAnimation(level),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _showRestockDialog(item),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _ink,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('RESTOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // Gold gradient card, same look as the web "AI Cognition" panel.
  Widget _aiSection(
      List<Map<String, dynamic>> items, bool isDark, Color card, Color border, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCD34D), Color(0xFFF59E0B), Color(0xFFB45309)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Smart Restocking',
                  style: GoogleFonts.cormorantGaramond(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Gemini reviews your low-stock items and suggests what to order.',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          if (_suggestion != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_suggestion!.text,
                      style: TextStyle(fontSize: 13, height: 1.5, color: text)),
                  const SizedBox(height: 10),
                  Text(
                    _suggestion!.fromGemini
                        ? 'Generated by Gemini'
                        : 'Built-in estimate (Gemini was unreachable)',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: sub),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isAnalyzing ? null : () => _getAISuggestions(items),
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isAnalyzing
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_suggestion == null ? 'GET AI RESTOCK SUGGESTION' : 'REFRESH SUGGESTION',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}