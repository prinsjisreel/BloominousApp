import 'package:flutter/material.dart';
import 'gemini_service.dart';
import 'inventory_data.dart';

/// Flora AI Concierge -- moved out of the AI Assistant tabs and into its own
/// page, opened from a floating button on the Shop Category screen. Unlike
/// its old home inside the AI Assistant tabs (which only ever gave Flora a
/// static system prompt), this version pulls REAL live data from Firestore
/// (current branch's stock, prices, categories) before every reply, so
/// Flora can answer actual inquiries -- "do you have red roses?", "how much
/// is X?", "what's available at this branch?" -- grounded in what's
/// genuinely in the database right now, not guesses.
class FloraChatPage extends StatefulWidget {
  // When opened from a product's detail page, this carries that product
  // so Flora can be primed to answer as if the customer is asking about
  // it specifically -- e.g. tapping "Ask Flora" while viewing "Red Rose"
  // means the very first thing Flora says references that product, and
  // every reply after is grounded with "the customer is currently
  // looking at X" context, not just the general store catalog. Null when
  // opened from the general FAB on the Shop Category page (no product
  // focus, general inquiry mode).
  final Map<String, dynamic>? focusedProduct;

  const FloraChatPage({super.key, this.focusedProduct});

  @override
  State<FloraChatPage> createState() => _FloraChatPageState();
}

class _FloraChatPageState extends State<FloraChatPage> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isChatLoading = false;

  // Snapshot of live store data, fetched once when this page opens and
  // reused for every message in the conversation. Refreshed with the
  // refresh button in the app bar if stock changes mid-conversation.
  String? _inventoryContext;
  bool _isLoadingInventory = true;

  // Raw (unformatted) inventory items -- kept separately from
  // _inventoryContext above. That string is for the primary Gemini
  // prompt; this raw list is what gets passed to chatWithConcierge's
  // embedding-based semantic fallback, which needs actual structured
  // fields (name/price/stock/description) to embed and search, not
  // pre-formatted display text.
  List<Map<String, dynamic>> _inventoryItems = [];

  late final List<Map<String, String>> _messages;

  // Real Pexels photos attached to each message, kept in lock-step with
  // _messages by index (empty list = no photos for that message). This
  // replaces the old _getChatFlowerImage(), which mapped a few keywords
  // straight to a handful of hardcoded Unsplash URLs -- the SAME photo
  // every single time "rose" appeared in a reply, regardless of what
  // Flora actually said. Real search means the photo genuinely reflects
  // what's being discussed.
  final List<List<String>> _messagePhotos = [];

  @override
  void initState() {
    super.initState();

    final product = widget.focusedProduct;
    _messages = [
      {
        'role': 'Flora',
        'content': product != null
            ? 'Hello! I see you\'re looking at ${product['name'] ?? 'this product'} '
            '(₱${(product['price'] ?? 0).toStringAsFixed(2)}). Ask me anything about '
            'it -- availability, care tips, whether it suits an occasion -- or '
            'anything else about our flowers!'
            : 'Hello! I am Flora, your AI Floral Assistant. Ask me about flower meanings, care tips, or check what we currently have in stock and its price! How can I help you today?'
      }
    ];
    _messagePhotos.add([]); // filled in below if a product photo exists

    if (product != null) {
      _loadFocusedProductPhoto(product);
    }
    _loadInventoryContext();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Pulls a compact, real snapshot of what the store actually has right
  /// now -- branches, categories, and a capped list of in-stock items with
  /// their real prices -- and formats it into plain text that gets fed
  /// into Gemini's prompt on every message. Capped at 60 items so the
  /// prompt stays a reasonable size; if you carry more SKUs than that
  /// regularly, consider filtering to the customer's selected branch only
  /// instead of "all branches" here.
  Future<void> _loadInventoryContext() async {
    setState(() => _isLoadingInventory = true);
    try {
      final branches = await InventoryData.getBranches();
      final branchNames = <String, String>{
        for (final b in branches)
          (b['id'] ?? '').toString(): (b['name'] ?? 'Branch').toString()
      };

      final inventory =
      await InventoryData.inventoryStream(branchId: 'all').first;
      final categories = await InventoryData.globalCategoriesStream().first;

      final buffer = StringBuffer();

      // Product focus note goes FIRST, before the general catalog dump,
      // so it's the most prominent thing Gemini sees -- this is what
      // keeps Flora anchored to "Red Rose" even three messages into the
      // conversation, rather than drifting back to generic answers.
      final product = widget.focusedProduct;
      if (product != null) {
        buffer.writeln(
            'IMPORTANT CONTEXT: The customer opened this chat directly from '
                'the product page for "${product['name'] ?? 'a product'}" '
                '(price: ₱${(product['price'] ?? 0).toStringAsFixed(2)}'
                '${product['category'] != null ? ", category: ${product['category']}" : ""}'
                '${product['description'] != null && (product['description'] as String).isNotEmpty ? ", description: ${product['description']}" : ""}). '
                'Assume their questions are about THIS product unless they '
                'clearly ask about something else.');
      }

      if (inventory.isEmpty) {
        buffer.writeln(
            'No live inventory data is currently available -- answer generally and suggest the customer check the Shop page.');
        _inventoryItems = [];
      } else {
        final inStock =
        inventory.where((item) => (item['stock'] ?? 0) > 0).toList();

        buffer.writeln('Branches: ${branchNames.values.join(", ")}');
        buffer.writeln('Categories offered: ${categories.join(", ")}');
        buffer.writeln(
            'Current in-stock items (name | price | stock | branch):');

        for (final item in inStock.take(60)) {
          final name = item['name'] ?? 'Unnamed';
          final price = item['price'] ?? 0;
          final stock = item['stock'] ?? 0;
          final branch = branchNames[item['branchId']] ?? 'Branch';
          buffer.writeln('- $name | ₱$price | $stock in stock | $branch');
        }

        if (inStock.length > 60) {
          buffer.writeln(
              '...and ${inStock.length - 60} more items not listed here for brevity.');
        }

        // Raw items kept for the semantic fallback -- see field comment
        // above for why this is separate from the formatted text block.
        _inventoryItems = inventory;
      }

      _inventoryContext = buffer.toString();
    } catch (e) {
      debugPrint('Error building Flora inventory context: $e');
      _inventoryContext =
      'Live stock data is temporarily unavailable -- answer generally and suggest the customer check the Shop page directly.';
      _inventoryItems = [];
    } finally {
      if (mounted) setState(() => _isLoadingInventory = false);
    }
  }

  /// Fetches a real photo of the product the chat opened focused on, so
  /// the greeting message isn't just text -- shown alongside the "Hello!
  /// I see you're looking at X" message.
  Future<void> _loadFocusedProductPhoto(Map<String, dynamic> product) async {
    final name = product['name']?.toString();
    if (name == null || name.isEmpty) return;
    try {
      final photos = await GeminiService.searchFlowerPhotos(name, perPage: 3);
      if (mounted && _messagePhotos.isNotEmpty) {
        setState(() => _messagePhotos[0] = photos);
      }
    } catch (e) {
      debugPrint('Error loading focused product photo: $e');
    }
  }

  /// Pulls a plain flower/topic keyword out of Flora's own reply text so
  /// we know what to search Pexels for -- e.g. if she mentions "roses" in
  /// her answer, the photo strip shows real roses, not a generic default.
  /// Returns null (no photo search) if nothing recognizable is mentioned.
  String? _extractPhotoQuery(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('sunflower')) return 'sunflowers';
    if (lower.contains('rose')) return 'red roses';
    if (lower.contains('tulip')) return 'tulips';
    if (lower.contains('lily') || lower.contains('lilies')) {
      return 'white lilies';
    }
    if (lower.contains('carnation')) return 'pink carnations';
    if (lower.contains('hydrangea')) return 'blue hydrangeas';
    if (lower.contains('orchid')) return 'orchids';
    if (lower.contains('gerbera')) return 'gerbera daisies';
    return null;
  }

  Future<void> _sendChatMessage([String? predefined]) async {
    final text = predefined ?? _chatController.text.trim();
    if (text.isEmpty || _isChatLoading) return;

    if (predefined == null) {
      _chatController.clear();
    }

    setState(() {
      _messages.add({'role': 'User', 'content': text});
      _messagePhotos.add([]); // user messages never carry a photo strip
      _isChatLoading = true;
    });

    _scrollToBottom();

    final response = await GeminiService.chatWithConcierge(
      userQuery: text,
      conversationHistory: _messages.take(10).toList(),
      inventoryContext: _inventoryContext,
      inventoryItems: _inventoryItems,
    );

    // Real Pexels search based on what Flora's answer actually mentions --
    // fetched before the setState below so the photo strip appears at the
    // same time as the text, not popping in a beat later.
    final query = _extractPhotoQuery(response);
    List<String> photos = [];
    if (query != null) {
      try {
        photos = await GeminiService.searchFlowerPhotos(query, perPage: 3);
      } catch (e) {
        debugPrint('Error fetching Flora reply photos: $e');
      }
    }

    if (mounted) {
      setState(() {
        _messages.add({'role': 'Flora', 'content': response});
        _messagePhotos.add(photos);
        _isChatLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final product = widget.focusedProduct;
    final suggestedQuestions = product != null
        ? [
      'Tell me more about ${product['name']}',
      'Is ${product['name']} available right now?',
      'What occasions suit ${product['name']}?',
      'How do I keep it fresh?',
    ]
        : [
      'What flowers do you have in stock right now?',
      'How much is a bouquet of red roses?',
      'What flowers represent gratitude?',
      'How do I make roses stay fresh for 2 weeks?',
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFF59E0B),
              radius: 16,
              child: Icon(Icons.support_agent, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Flora AI Concierge',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (product != null)
                    Text(
                      'Asking about: ${product['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.normal,
                          color: isDark
                              ? Colors.grey[400]
                              : Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoadingInventory
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFF59E0B)),
            )
                : const Icon(Icons.refresh, color: Color(0xFFF59E0B)),
            tooltip: 'Refresh live stock data',
            onPressed: _isLoadingInventory ? null : _loadInventoryContext,
          ),
        ],
      ),
      body: Column(
        children: [
          // Small status strip so it's clear whether Flora currently has
          // real stock data to work with -- avoids the confusing situation
          // of Flora answering stock questions before the fetch finishes.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: isDark ? const Color(0xFF262626) : const Color(0xFFFFF7ED),
            child: Row(
              children: [
                Icon(
                  _isLoadingInventory
                      ? Icons.sync
                      : Icons.check_circle_outline,
                  size: 12,
                  color: _isLoadingInventory
                      ? Colors.grey
                      : const Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                Text(
                  _isLoadingInventory
                      ? 'Checking live stock...'
                      : 'Connected to live stock & pricing',
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Quick Suggestion Chips
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: suggestedQuestions.length,
              itemBuilder: (context, index) {
                final q = suggestedQuestions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 11)),
                    backgroundColor:
                    isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    side: BorderSide(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    onPressed: () => _sendChatMessage(q),
                  ),
                );
              },
            ),
          ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'User';

                return Align(
                  alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFFF59E0B)
                          : (isDark
                          ? const Color(0xFF262626)
                          : const Color(0xFFF3F4F6)),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser
                            ? const Radius.circular(16)
                            : const Radius.circular(4),
                        bottomRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUser ? 'You' : 'Flora AI',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isUser
                                ? Colors.white70
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['content'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: isUser
                                ? Colors.white
                                : (isDark
                                ? Colors.white
                                : const Color(0xFF121212)),
                            height: 1.4,
                          ),
                        ),
                        if (!isUser &&
                            index < _messagePhotos.length &&
                            _messagePhotos[index].isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _messagePhotos[index].length,
                                itemBuilder: (context, photoIndex) {
                                  return Padding(
                                    padding:
                                    const EdgeInsets.only(right: 6.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        _messagePhotos[index][photoIndex],
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isChatLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFF59E0B))),
                  SizedBox(width: 10),
                  Text('Flora is thinking...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

          // Input Field
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: InputDecoration(
                        hintText:
                        'Ask Flora about stock, prices, or flower care...',
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF59E0B),
                    child: IconButton(
                      icon: const Icon(Icons.send,
                          color: Colors.white, size: 20),
                      onPressed: () => _sendChatMessage(),
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
}