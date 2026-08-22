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
  const FloraChatPage({super.key});

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

  final List<Map<String, String>> _messages = [
    {
      'role': 'Flora',
      'content':
      'Hello! I am Flora, your AI Floral Assistant. Ask me about flower meanings, care tips, or check what we currently have in stock and its price! How can I help you today?'
    }
  ];

  @override
  void initState() {
    super.initState();
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

      if (inventory.isEmpty) {
        _inventoryContext =
        'No live inventory data is currently available -- answer generally and suggest the customer check the Shop page.';
      } else {
        final inStock =
        inventory.where((item) => (item['stock'] ?? 0) > 0).toList();

        final buffer = StringBuffer();
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

        _inventoryContext = buffer.toString();
      }
    } catch (e) {
      debugPrint('Error building Flora inventory context: $e');
      _inventoryContext =
      'Live stock data is temporarily unavailable -- answer generally and suggest the customer check the Shop page directly.';
    } finally {
      if (mounted) setState(() => _isLoadingInventory = false);
    }
  }

  Future<void> _sendChatMessage([String? predefined]) async {
    final text = predefined ?? _chatController.text.trim();
    if (text.isEmpty || _isChatLoading) return;

    if (predefined == null) {
      _chatController.clear();
    }

    setState(() {
      _messages.add({'role': 'User', 'content': text});
      _isChatLoading = true;
    });

    _scrollToBottom();

    final response = await GeminiService.chatWithConcierge(
      userQuery: text,
      conversationHistory: _messages.take(10).toList(),
      inventoryContext: _inventoryContext,
    );

    if (mounted) {
      setState(() {
        _messages.add({'role': 'Flora', 'content': response});
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

  String? _getChatFlowerImage(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('sunflower') || lower.contains('yellow')) {
      return 'https://images.unsplash.com/photo-1597848212624-a19eb35e2651?q=80&w=400&auto=format&fit=crop';
    } else if (lower.contains('rose') ||
        lower.contains('red') ||
        lower.contains('romance')) {
      return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=400&auto=format&fit=crop';
    } else if (lower.contains('tulip')) {
      return 'https://images.unsplash.com/photo-1520763185298-1b434c919102?q=80&w=400&auto=format&fit=crop';
    } else if (lower.contains('lily') || lower.contains('white')) {
      return 'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=400&auto=format&fit=crop';
    } else if (lower.contains('carnation') ||
        lower.contains('pink') ||
        lower.contains('mom') ||
        lower.contains('mother')) {
      return 'https://images.unsplash.com/photo-1561181286-d3fee7d55364?q=80&w=400&auto=format&fit=crop';
    } else if (lower.contains('hydrangea') || lower.contains('blue')) {
      return 'https://images.unsplash.com/photo-1508610048659-a06b669e3321?q=80&w=400&auto=format&fit=crop';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final suggestedQuestions = [
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
            const Text('Flora AI Concierge',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        if (!isUser) ...[
                          Builder(
                            builder: (context) {
                              final chatImg =
                              _getChatFlowerImage(msg['content'] ?? '');
                              if (chatImg == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    chatImg,
                                    height: 130,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                                  ),
                                ),
                              );
                            },
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