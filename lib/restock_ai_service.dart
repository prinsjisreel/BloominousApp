import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_keys.dart';

/// One low-stock product, reduced to the few fields the AI needs.
class RestockItem {
  final String name;
  final int stock;
  final double price;
  final String category;

  const RestockItem({
    required this.name,
    required this.stock,
    required this.price,
    required this.category,
  });
}

/// The finished suggestion plus WHERE it came from, so the screen can tell
/// the user honestly whether Gemini or the built-in estimate wrote it.
class RestockSuggestion {
  final String text;
  final bool fromGemini;
  const RestockSuggestion(this.text, this.fromGemini);
}

/// Restock advice for the AI Stock Alerts page.
///
/// Same pattern as Flora (GeminiService.chatWithConcierge):
///   1. Ask live Gemini (gemini-2.5-flash) using the key from ApiKeys.
///   2. If Gemini is unreachable, return a rule-based plan instead of an
///      error, so the button always gives the staff something usable.
///
/// Note on embeddings: Flora's embedding model only turns text into numbers
/// so she can MATCH a question to a stored answer. It cannot write a new
/// plan, so for writing the suggestion we use the generative model, and the
/// fallback is rule-based.
class RestockAiService {
  RestockAiService._();

  static Future<RestockSuggestion> suggest(List<RestockItem> items) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: ApiKeys.geminiApiKey,
      );

      final itemsList = items
          .map((i) =>
      '- ${i.name} (${i.category}): ${i.stock} left, sells at P${i.price.toStringAsFixed(0)}')
          .join('\n');

      final now = DateTime.now();
      final prompt = '''
You are the inventory assistant of 'Bloominous', a flower shop in the Philippines.
These products are low on stock:
$itemsList

Today is ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.
Consider upcoming Philippine flower seasons and events (Valentine's Day, Mother's Day, All Saints' Day, graduation season, Christmas).

Give a short restocking plan:
1. Which products to restock first (most urgent first).
2. A suggested order quantity for each.
3. One short reason for each.

Rules: plain text only, no markdown, no asterisks. Start each point with "- ". Under 150 words.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      if (text.isNotEmpty) {
        return RestockSuggestion(_cleanup(text), true);
      }
    } catch (e) {
      // ignore: avoid_print
      print('RestockAiService: Gemini failed, using built-in estimate: $e');
    }

    return RestockSuggestion(_ruleBasedPlan(items), false);
  }

  /// Removes markdown the model sometimes adds anyway, so the Text widget
  /// doesn't show raw "**" or "* " characters.
  static String _cleanup(String raw) {
    return raw
        .replaceAll('**', '')
        .replaceAllMapped(RegExp(r'^\s*\*\s+', multiLine: true), (_) => '- ');
  }

  /// Offline plan: out of stock first, then lowest stock first. Order enough
  /// to bring each product back to about 30 pieces.
  static String _ruleBasedPlan(List<RestockItem> items) {
    final sorted = [...items]..sort((a, b) => a.stock.compareTo(b.stock));
    final lines = sorted.map((i) {
      final order = (30 - i.stock).clamp(10, 60);
      final urgency = i.stock <= 0
          ? 'out of stock'
          : (i.stock <= 5 ? 'critically low' : 'running low');
      return '- ${i.name}: order about $order pcs ($urgency, ${i.stock} left).';
    });
    return lines.join('\n');
  }
}