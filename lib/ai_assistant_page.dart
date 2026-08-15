import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'gemini_service.dart';
import 'builder_page.dart';
import 'product_catalog_page.dart';

class AIAssistantPage extends StatefulWidget {
  const AIAssistantPage({super.key});

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Visual Assistant State
  File? _selectedImage;
  Uint8List? _imageBytes;
  bool _isAnalyzingImage = false;
  Map<String, dynamic>? _visualResult;
  final TextEditingController _visualNoteController = TextEditingController();

  // Gemini API Direct Photo Edit & Synthesis State
  Uint8List? _aiSynthesizedImageBytes;
  bool _isSynthesizingAiImage = false;
  final TextEditingController _customApiPromptController =
  TextEditingController();

  Future<void> _generateAiPhotoSynthesis({String? customPrompt}) async {
    setState(() {
      _isSynthesizingAiImage = true;
    });

    final flowerName = _selectedFlowerType == 'sunflower'
        ? 'sunflowers (mirasol)'
        : _selectedFlowerType == 'rose'
        ? 'fresh red roses'
        : _selectedFlowerType == 'tulip'
        ? 'vibrant pink tulips'
        : _selectedFlowerType == 'lily'
        ? 'fragrant white stargazer lilies'
        : 'colorful carnations';

    final potName = _selectedPotType == 'terracotta'
        ? 'terracotta clay paso pot'
        : _selectedPotType == 'ceramic'
        ? 'white ceramic vase'
        : _selectedPotType == 'gold'
        ? 'luxurious golden metallic vase'
        : 'clear crystal glass vase';

    final userTyped = _customApiPromptController.text.trim();
    final promptText = (customPrompt != null && customPrompt.isNotEmpty)
        ? customPrompt
        : userTyped.isNotEmpty
        ? "Edit the uploaded photo: $userTyped, featuring $flowerName placed inside a $potName on a table, ultra realistic 8k florist interior photography."
        : "Edit the uploaded photo: place an elegant floral arrangement of $flowerName gracefully inside a $potName sitting on the table in the room photo, ultra realistic 8k daylight interior photo.";

    Uint8List? instantEdited;
    String providerUsed = 'Gemini';
    try {
      Uint8List? bytes;
      if (_imageBytes != null && _imageBytes!.isNotEmpty) {
        // Instant placeholder shown immediately while the real AI call is in flight
        instantEdited = await GeminiService.compositeEditedRoomPhoto(
          userRoomBytes: _imageBytes!,
          flowerType: flowerName,
          potType: potName,
        );
        if (mounted) {
          setState(() {
            _aiSynthesizedImageBytes = instantEdited;
          });
        }

        // The real AI image edit -- this is what should end up on screen.
        // Tries Gemini first; if that fails for any reason, automatically
        // retries with Stability AI before giving up to the placeholder.
        try {
          bytes = await GeminiService.editUserPhotoWithGemini(
            userRoomBytes: _imageBytes!,
            userInstruction: promptText,
            flowerType: flowerName,
            potType: potName,
          );
        } on GeminiImageException catch (geminiError) {
          // Logged for debugging, but NOT shown to the user -- with Gemini's
          // free-tier quota at 0 for this model, this fallback fires on
          // every single attempt until billing is enabled. Showing a banner
          // every time is just noise; only the final outcome (success or
          // total failure below) is worth surfacing to the user.
          print("Gemini failed, trying Stability AI fallback: ${geminiError.message}");
          bytes = await GeminiService.editUserPhotoWithStabilityAI(
            userRoomBytes: _imageBytes!,
            userInstruction: promptText,
            flowerType: flowerName,
            potType: potName,
          );
          providerUsed = 'Stability AI';
        }
      } else {
        bytes = await GeminiService.generateImagen3Image(prompt: promptText);
      }

      if (mounted) {
        setState(() {
          if (bytes != null && bytes.isNotEmpty) {
            _aiSynthesizedImageBytes = bytes;
          }
          _isSynthesizingAiImage = false;
        });
        if (bytes != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✨ $providerUsed analyzed your photo and generated your edited room design!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } on GeminiImageException catch (e) {
      // Surface the REAL reason instead of failing silently. This is what
      // was previously getting swallowed -- "nothing generates" with no
      // way to tell why. Falls back to the instant placeholder so the
      // screen isn't left blank, but the error is now visible.
      print("Gemini image generation failed: ${e.message}");
      if (mounted) {
        setState(() {
          _isSynthesizingAiImage = false;
          if (instantEdited != null) {
            _aiSynthesizedImageBytes = instantEdited;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI image generation failed: ${e.message}'),
            backgroundColor: const Color(0xFFDC3545),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      print("Unexpected error in _generateAiPhotoSynthesis: $e");
      if (mounted) {
        setState(() {
          _isSynthesizingAiImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong: $e'),
            backgroundColor: const Color(0xFFDC3545),
          ),
        );
      }
    }
  }

  // Room Virtual Staging State
  Offset _flowerPosition = const Offset(90, 60);
  double _flowerScale = 1.0;
  bool _showStagedRoom = true;
  bool _usePhotorealisticMode =
  true; // Default to photorealistic HD photography!
  bool _showFullGeminiAiBlend =
  true; // Default to Gemini Web style Full Photorealistic Synthesis!

  Widget _buildPhotorealisticFallbackWidget() {
    return Container(
      width: 210,
      height: 250,
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_florist, size: 48, color: Color(0xFFF59E0B)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '✨ Floral Arrangement Design',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _selectedOverlayIndex = 0;
  String _selectedFlowerType =
      'rose'; // 'rose', 'sunflower', 'tulip', 'lily', 'carnation'
  String _selectedPotType = 'glass'; // 'glass', 'ceramic', 'terracotta', 'gold'

  String _getPhotorealisticOverlayUrl() {
    if (_selectedFlowerType == 'rose') {
      if (_selectedPotType == 'terracotta') {
        return 'https://images.unsplash.com/photo-1563241527-3004b7be0ffd?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'ceramic') {
        return 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'gold') {
        return 'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=800&auto=format&fit=crop';
      }
      return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=800&auto=format&fit=crop';
    } else if (_selectedFlowerType == 'sunflower') {
      if (_selectedPotType == 'terracotta') {
        return 'https://images.unsplash.com/photo-1545241047-6083a3684587?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'ceramic') {
        return 'https://images.unsplash.com/photo-1508610048659-a06b669e3321?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'gold') {
        return 'https://images.unsplash.com/photo-1565201217036-7c264e10ceb2?q=80&w=800&auto=format&fit=crop';
      }
      return 'https://images.unsplash.com/photo-1508610048659-a06b669e3321?q=80&w=800&auto=format&fit=crop';
    } else if (_selectedFlowerType == 'tulip') {
      if (_selectedPotType == 'terracotta') {
        return 'https://images.unsplash.com/photo-1589241062272-c0a000072dfa?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'ceramic') {
        return 'https://images.unsplash.com/photo-1519378058457-4c29a0a2efac?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'gold') {
        return 'https://images.unsplash.com/photo-1527061011665-3652c757a4d4?q=80&w=800&auto=format&fit=crop';
      }
      return 'https://images.unsplash.com/photo-1520763185298-1b434c919102?q=80&w=800&auto=format&fit=crop';
    } else if (_selectedFlowerType == 'lily') {
      if (_selectedPotType == 'terracotta') {
        return 'https://images.unsplash.com/photo-1567696911980-2eed69a46042?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'ceramic') {
        return 'https://images.unsplash.com/photo-1572454591674-2739f30d8c40?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'gold') {
        return 'https://images.unsplash.com/photo-1513151233558-d860c5398176?q=80&w=800&auto=format&fit=crop';
      }
      return 'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=800&auto=format&fit=crop';
    } else {
      if (_selectedPotType == 'terracotta') {
        return 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'ceramic') {
        return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=800&auto=format&fit=crop';
      } else if (_selectedPotType == 'gold') {
        return 'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=800&auto=format&fit=crop';
      }
      return 'https://images.unsplash.com/photo-1561181286-d3fee7d55364?q=80&w=800&auto=format&fit=crop';
    }
  }

  final List<Map<String, String>> _overlayPresets = [
    {
      'name': '🌹 Florist Event Red Roses in Glass Vase',
      'flowerType': 'rose',
      'potType': 'glass',
    },
    {
      'name': '🌻 Sunflowers in Crystal Vase',
      'flowerType': 'sunflower',
      'potType': 'glass',
    },
    {
      'name': '🌷 Pink Tulips in Glass Vase',
      'flowerType': 'tulip',
      'potType': 'glass',
    },
    {
      'name': '🤍 White Lilies Luxury Glass Vase',
      'flowerType': 'lily',
      'potType': 'glass',
    },
    {
      'name': '🌸 Pastel Carnations in Glass Vase',
      'flowerType': 'carnation',
      'potType': 'glass',
    },
  ];

  // Personal Matchmaker State
  String _selectedRecipient = 'Partner / Spouse';
  String _selectedOccasion = 'Anniversary';
  String _selectedVibe = 'Romantic Red';
  String _selectedBudget = '₱1,000 - ₱2,500';
  String _selectedTone = 'Heartfelt & Deep';
  bool _isGeneratingMatch = false;
  Map<String, dynamic>? _matchResult;

  // Chat Concierge State
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isChatLoading = false;
  final List<Map<String, String>> _messages = [
    {
      'role': 'Flora',
      'content':
      'Hello! I am Flora, your AI Floral Assistant. I can help you pick the perfect flowers, explain flower meanings (floriography), or give care tips for lasting fresh blooms! How can I assist you today?'
    }
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _visualNoteController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Visual Assistant Action
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedImage = File(picked.path);
          _imageBytes = bytes;
          _visualResult = null;
          _aiSynthesizedImageBytes = null;
        });
        // No auto-analysis here -- the user finishes typing their occasion
        // note first, then explicitly taps "Analyze & Match Floral Theme".
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select image: $e')),
        );
      }
    }
  }

  Future<void> _analyzeVisualImage() async {
    if (_imageBytes == null && _visualNoteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please upload a photo or add a description first.')),
      );
      return;
    }

    setState(() {
      _isAnalyzingImage = true;
    });

    // Step 1: detect theme + recommended flowers/colors from the photo + note
    final result = await GeminiService.analyzeVisualTheme(
      imageBytes: _imageBytes,
      description: _visualNoteController.text.trim().isEmpty
          ? null
          : _visualNoteController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _visualResult = result;

        final rec = ((result['recommendedFlowers'] as List?) ?? [])
            .join(' ')
            .toLowerCase();
        final theme = (result['detectedTheme'] ?? '').toString().toLowerCase();

        if (rec.contains('sunflower') ||
            rec.contains('yellow') ||
            theme.contains('rustic')) {
          _selectedFlowerType = 'sunflower';
          _selectedPotType = 'terracotta';
        } else if (rec.contains('rose') ||
            rec.contains('red') ||
            theme.contains('romantic')) {
          _selectedFlowerType = 'rose';
          _selectedPotType = 'ceramic';
        } else if (rec.contains('tulip') || rec.contains('pink')) {
          _selectedFlowerType = 'tulip';
          _selectedPotType = 'glass';
        } else if (rec.contains('lily') || rec.contains('white')) {
          _selectedFlowerType = 'lily';
          _selectedPotType = 'gold';
        } else {
          _selectedFlowerType = 'carnation';
          _selectedPotType = 'terracotta';
        }
      });
    }

    // Step 2: now that _selectedFlowerType/_selectedPotType reflect what the
    // AI actually recommended, generate the real photo edit using them.
    final userNote = _visualNoteController.text.trim();
    if (_imageBytes != null) {
      await _generateAiPhotoSynthesis(
          customPrompt: userNote.isNotEmpty ? userNote : null);
    }

    if (mounted) {
      setState(() {
        _isAnalyzingImage = false;
      });
    }
  }

  // Matchmaker Action
  Future<void> _generateMatch() async {
    setState(() {
      _isGeneratingMatch = true;
      _matchResult = null;
    });

    final result = await GeminiService.getPersonalizedMatch(
      recipient: _selectedRecipient,
      occasion: _selectedOccasion,
      vibe: _selectedVibe,
      budget: _selectedBudget,
      tone: _selectedTone,
    );

    if (mounted) {
      setState(() {
        _isGeneratingMatch = false;
        _matchResult = result;
      });
    }
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

  // Chat Action
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bloominous AI Assistant',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF121212),
                    ),
                  ),
                  Text(
                    'Visual Styling & Personal Matchmaker',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF59E0B),
          labelColor: const Color(0xFFF59E0B),
          unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
          tabs: const [
            Tab(icon: Icon(Icons.palette_outlined), text: 'Visual Stylist'),
            Tab(icon: Icon(Icons.favorite_outline), text: 'Matchmaker'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Flora AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualStylistTab(isDark),
          _buildMatchmakerTab(isDark),
          _buildChatConciergeTab(isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: VISUAL STYLIST & PHOTO ANALYZER
  // ---------------------------------------------------------------------------
  Widget _buildVisualStylistTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF2A2A2A), const Color(0xFF1E1E1E)]
                    : [const Color(0xFFFFF7ED), const Color(0xFFFEF3C7)],
              ),
              borderRadius: BorderRadius.circular(16),
              border:
              Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.camera_enhance_rounded,
                    size: 36, color: Color(0xFFF59E0B)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Room & Outfit Visual Stylist',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color:
                          isDark ? Colors.white : const Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Upload a photo of your room, outfit, or vase. Gemini AI recommends complementary flowers & palettes!',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                            isDark ? Colors.grey[300] : Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Image Picker Area
          GestureDetector(
            onTap: () => _showImageSourceBottomSheet(),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color:
                isDark ? const Color(0xFF262626) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedImage != null
                      ? const Color(0xFFF59E0B)
                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  width: 2,
                ),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(_selectedImage!, fit: BoxFit.cover),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Colors.white),
                          onPressed: _showImageSourceBottomSheet,
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined,
                      size: 48, color: Color(0xFFF59E0B)),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to Upload or Take Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color:
                      isDark ? Colors.white : const Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Room decor, dress, event venue, or vase',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                        isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Optional Note input
          TextField(
            controller: _visualNoteController,
            decoration: InputDecoration(
              labelText: 'Optional Event / Style Note',
              hintText:
              'e.g., Rustic garden wedding in Tagaytay with warm lighting',
              prefixIcon: const Icon(Icons.edit_note, color: Color(0xFFF59E0B)),
              filled: true,
              fillColor: isDark ? const Color(0xFF262626) : Colors.white,
              border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Analyze Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isAnalyzingImage ? null : _analyzeVisualImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isAnalyzingImage
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isAnalyzingImage
                    ? 'Analyzing with Gemini AI...'
                    : 'Analyze & Match Floral Theme',
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Results
          if (_visualResult != null) ...[
            Text(
              'AI Visual Styling Analysis',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF121212),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
                border:
                Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Room Virtual Staging Canvas & Image Preview
                  _buildRoomVirtualStagingWidget(isDark),

                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Aesthetic Theme
                        Row(
                          children: [
                            const Icon(Icons.style_outlined,
                                color: Color(0xFFF59E0B), size: 20),
                            const SizedBox(width: 8),
                            Text('Detected Theme: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700])),
                            Expanded(
                              child: Text(
                                _visualResult!['detectedTheme'] ??
                                    'Custom Theme',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF59E0B)),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Color Palette
                        Text('Matching Color Palette:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                          ((_visualResult!['colorPalette'] as List?) ?? [])
                              .map((color) {
                            return Chip(
                              avatar: CircleAvatar(
                                  backgroundColor:
                                  const Color(0xFFF59E0B).withOpacity(0.4)),
                              label: Text(color.toString(),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : const Color(0xFFFFFBEB),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Recommended Flowers
                        Text('Recommended Flowers:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 6),
                        ...((_visualResult!['recommendedFlowers'] as List?) ??
                            [])
                            .map(
                              (flower) => Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.local_florist_rounded,
                                    color: Color(0xFFF59E0B), size: 16),
                                const SizedBox(width: 8),
                                Text(flower.toString(),
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.grey[200]
                                            : Colors.grey[800])),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Arrangement Style
                        Text('Arrangement Style:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 4),
                        Text(_visualResult!['arrangementStyle'] ?? '',
                            style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700])),

                        const SizedBox(height: 16),

                        // Matching Reason
                        Text('Stylist Note:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 4),
                        Text(_visualResult!['matchingReason'] ?? '',
                            style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                                height: 1.4)),

                        if (_visualResult!['cardMessageSuggestion'] !=
                            null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.card_giftcard,
                                    color: Color(0xFFF59E0B), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '"${_visualResult!['cardMessageSuggestion']}"',
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                          const ProductCatalogPage()));
                                },
                                icon: const Icon(Icons.storefront, size: 18),
                                label: const Text('View Catalog'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const BuilderPage()));
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.white),
                                icon: const Icon(Icons.view_in_ar, size: 18),
                                label: const Text('Open 3D Builder'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomVirtualStagingWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Switcher Bar
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showStagedRoom = true),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: _showStagedRoom
                          ? const Color(0xFFF59E0B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chair_outlined,
                          size: 15,
                          color: _showStagedRoom
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[700]),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Room Staging',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _showStagedRoom
                                  ? Colors.white
                                  : (isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showStagedRoom = false),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: !_showStagedRoom
                          ? const Color(0xFFF59E0B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_florist_outlined,
                          size: 15,
                          color: !_showStagedRoom
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[700]),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Flower Catalog',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: !_showStagedRoom
                                  ? Colors.white
                                  : (isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_showStagedRoom) ...[
          // Interactive Room Photo Canvas with Floral Overlay / Gemini API Direct Edited Picture
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              height: 350,
              width: double.infinity,
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // A. Gemini API Synthesized/Edited Direct Picture Result
                  if (_aiSynthesizedImageBytes != null)
                    Image.memory(
                      _aiSynthesizedImageBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  // B. User's Uploaded Room Photo Background
                  else if (_imageBytes != null)
                    Image.memory(
                      _imageBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  else if (_selectedImage != null)
                      Image.file(
                        _selectedImage!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    else
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?q=80&w=1200&auto=format&fit=crop',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: isDark
                                    ? const Color(0xFF1F2937)
                                    : const Color(0xFFF3F4F6)),
                          ),
                          Container(
                            color: Colors.black.withOpacity(0.35),
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                    const Color(0xFFF59E0B).withOpacity(0.6)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_a_photo_outlined,
                                      color: Color(0xFFF59E0B), size: 13),
                                  SizedBox(width: 5),
                                  Text(
                                    'Tap upload to stage on your room',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                  // C. Photorealistic Floral Overlay (ONLY rendered when NO user photo is uploaded and NOT in AI synthesis mode)
                  if (_aiSynthesizedImageBytes == null &&
                      _imageBytes == null &&
                      _selectedImage == null &&
                      !_showFullGeminiAiBlend &&
                      !_usePhotorealisticMode)
                    Positioned(
                      left: _showFullGeminiAiBlend ? 75.0 : _flowerPosition.dx,
                      top: _showFullGeminiAiBlend ? 50.0 : _flowerPosition.dy,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            if (_showFullGeminiAiBlend) {
                              _showFullGeminiAiBlend =
                              false; // switch to manual drag on user interaction
                            }
                            _flowerPosition += details.delta;
                          });
                        },
                        child: Transform.scale(
                          scale: _flowerScale,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 90,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(50)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.55),
                                        blurRadius: 18,
                                        spreadRadius: 6,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Seamless Transparent Cutout (No rectangular card box frame)
                              SizedBox(
                                width: 210,
                                height: 250,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.network(
                                      GeminiService.selectTransparentOverlayUrl(
                                        flowers: _selectedFlowerType,
                                        theme: _selectedPotType,
                                      ),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          _buildPhotorealisticFallbackWidget(),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          border: Border.all(
                                              color: const Color(0xFFF59E0B)
                                                  .withOpacity(0.6)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.auto_awesome,
                                                color: Color(0xFFF59E0B),
                                                size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${_selectedFlowerType.toUpperCase()} in ${_selectedPotType.toUpperCase()}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.open_with,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // D. Non-blocking Status Banner when calling Gemini API
                  if (_isSynthesizingAiImage)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.80),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFF59E0B).withOpacity(0.8)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFF59E0B)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '✨ Gemini AI is refining your room photo edit...',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Top Indicator Badge & Mode Toggle
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withOpacity(0.8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: Color(0xFFF59E0B), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _aiSynthesizedImageBytes != null
                                ? '✨ Gemini API Edited Picture'
                                : '📸 Photorealistic HD Florist Design',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Save & Reset Buttons
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_aiSynthesizedImageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _aiSynthesizedImageBytes = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        color: Colors.white, size: 12),
                                    SizedBox(width: 3),
                                    Text(
                                      'Reset',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        InkWell(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '✨ Staged Room Photo Saved! Design attached to your arrangement preview.'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_rounded,
                                    color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Save Design',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tools Toolbar: Scale slider, Paso Style & Flower Selectors
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: isDark ? const Color(0xFF262626) : const Color(0xFFFFFBEB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Direct Gemini API Prompt Input Section
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_fix_high,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Sabihin sa Gemini API: "Edit the pic design it"',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.amber[300]
                                    : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                          if (_aiSynthesizedImageBytes != null)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _aiSynthesizedImageBytes = null;
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text('Reset',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customApiPromptController,
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                  isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                hintText:
                                'e.g., Integrate floral arrangement on stool next to plant with realistic shadows',
                                hintStyle: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[600]),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFF9FAFB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: _isSynthesizingAiImage
                                ? null
                                : () => _generateAiPhotoSynthesis(),
                            icon: _isSynthesizingAiImage
                                ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                                : const Icon(Icons.send_rounded, size: 14),
                            label: Text(
                              _isSynthesizingAiImage
                                  ? 'Editing...'
                                  : 'Send API',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.auto_awesome,
                                  size: 12, color: Color(0xFFD97706)),
                              label: const Text(
                                  '✨ In-Paint Bouquet on Stool (Accurate Shadow)',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              backgroundColor: isDark
                                  ? const Color(0xFF332B15)
                                  : const Color(0xFFFEF3C7),
                              side: BorderSide(
                                  color:
                                  const Color(0xFFF59E0B).withOpacity(0.5)),
                              padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () {
                                _customApiPromptController.text =
                                "Integrate a lush, architecturally composed floral bouquet in a modern ceramic vase on the wooden stool next to the plant, with natural soft daylight from left and realistic contact shadow";
                                _generateAiPhotoSynthesis();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.local_florist,
                                  size: 12, color: Color(0xFF10B981)),
                              label: const Text('🌹 Roses & Lilies on Stool',
                                  style: TextStyle(fontSize: 10)),
                              backgroundColor: isDark
                                  ? const Color(0xFF1E2923)
                                  : const Color(0xFFD1FAE5),
                              side: BorderSide(
                                  color:
                                  const Color(0xFF10B981).withOpacity(0.5)),
                              padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () {
                                _customApiPromptController.text =
                                "Place a high-end bouquet of red roses and white lilies in a ceramic vase on the stool under daylight";
                                _generateAiPhotoSynthesis();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Style & View Mode Toggles
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.style_outlined,
                        size: 16, color: Color(0xFFF59E0B)),
                    Text(
                      'Mode:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _usePhotorealisticMode = true;
                          _showFullGeminiAiBlend = true;
                        });
                        _generateAiPhotoSynthesis();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _showFullGeminiAiBlend
                              ? const Color(0xFFF59E0B)
                              : (isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _showFullGeminiAiBlend
                                  ? const Color(0xFFF59E0B)
                                  : Colors.grey.withOpacity(0.3)),
                        ),
                        child: Text(
                          '✨ Gemini AI Photo Synthesis',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: _showFullGeminiAiBlend
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _showFullGeminiAiBlend
                                ? Colors.white
                                : (isDark
                                ? Colors.grey[300]
                                : Colors.grey[800]),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        setState(() {
                          _usePhotorealisticMode = true;
                          _showFullGeminiAiBlend = false;
                        });
                        if (_imageBytes != null) {
                          final updatedEdited =
                          await GeminiService.compositeEditedRoomPhoto(
                            userRoomBytes: _imageBytes!,
                            flowerType: _selectedFlowerType,
                            potType: _selectedPotType,
                          );
                          if (mounted) {
                            setState(() {
                              _aiSynthesizedImageBytes = updatedEdited;
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: !_showFullGeminiAiBlend
                              ? const Color(0xFFF59E0B)
                              : (isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: !_showFullGeminiAiBlend
                                  ? const Color(0xFFF59E0B)
                                  : Colors.grey.withOpacity(0.3)),
                        ),
                        child: Text(
                          '📸 Photorealistic HD Drag',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: !_showFullGeminiAiBlend
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: !_showFullGeminiAiBlend
                                ? Colors.white
                                : (isDark
                                ? Colors.grey[300]
                                : Colors.grey[800]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Size Slider
                Row(
                  children: [
                    const Icon(Icons.aspect_ratio,
                        size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Text(
                      'Laki / Size:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                    Expanded(
                      child: Slider(
                        value: _flowerScale,
                        min: 0.5,
                        max: 1.8,
                        activeColor: const Color(0xFFF59E0B),
                        onChanged: (val) {
                          setState(() => _flowerScale = val);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.restart_alt, size: 18),
                      tooltip: 'Reset Position',
                      onPressed: () {
                        setState(() {
                          _flowerPosition = const Offset(90, 60);
                          _flowerScale = 1.0;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Paso / Pot Style Selector
                Row(
                  children: [
                    const Icon(Icons.yard_outlined,
                        size: 15, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      'Paso / Vase:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildPotChip('🪴 Clay Paso', 'terracotta', isDark),
                            _buildPotChip('🏺 Ceramic Vase', 'ceramic', isDark),
                            _buildPotChip('🥛 Glass Vase', 'glass', isDark),
                            _buildPotChip('🪙 Gold Paso', 'gold', isDark),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Bulaklak / Flower Type Selector
                Row(
                  children: [
                    const Icon(Icons.local_florist_outlined,
                        size: 15, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      'Bulaklak:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFlowerChip(
                                '🌻 Mirasol (Sunflower)', 'sunflower', isDark),
                            _buildFlowerChip('🌹 Red Rose', 'rose', isDark),
                            _buildFlowerChip('🌷 Pink Tulip', 'tulip', isDark),
                            _buildFlowerChip('🤍 White Lily', 'lily', isDark),
                            _buildFlowerChip(
                                '🌸 Carnation', 'carnation', isDark),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Preset Combinations
                SizedBox(
                  height: 32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _overlayPresets.length,
                    itemBuilder: (context, index) {
                      final item = _overlayPresets[index];
                      final isSelected = _selectedOverlayIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          selected: isSelected,
                          showCheckmark: false,
                          label: Text(
                            item['name']!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800]),
                            ),
                          ),
                          backgroundColor:
                          isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          selectedColor: const Color(0xFFF59E0B),
                          onSelected: (_) {
                            setState(() {
                              _selectedOverlayIndex = index;
                              _selectedFlowerType = item['flowerType']!;
                              _selectedPotType = item['potType']!;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Reference Catalog Photo View
          if (_visualResult!['imageUrl'] != null)
            ClipRRect(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  Image.network(
                    _visualResult!['imageUrl'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'AI Recommended Arrangement Look',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPotChip(String label, String value, bool isDark) {
    final isSelected = _selectedPotType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _selectedPotType = value;
            _usePhotorealisticMode = true;
          });
          if (_imageBytes != null) {
            final instantEdited = await GeminiService.compositeEditedRoomPhoto(
              userRoomBytes: _imageBytes!,
              flowerType: _selectedFlowerType,
              potType: value,
            );
            if (mounted) {
              setState(() {
                _aiSynthesizedImageBytes = instantEdited;
              });
            }
            _generateAiPhotoSynthesis();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF59E0B)
                  : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey[300] : Colors.grey[800]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlowerChip(String label, String value, bool isDark) {
    final isSelected = _selectedFlowerType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _selectedFlowerType = value;
            _usePhotorealisticMode = true;
          });
          if (_imageBytes != null) {
            final instantEdited = await GeminiService.compositeEditedRoomPhoto(
              userRoomBytes: _imageBytes!,
              flowerType: value,
              potType: _selectedPotType,
            );
            if (mounted) {
              setState(() {
                _aiSynthesizedImageBytes = instantEdited;
              });
            }
            _generateAiPhotoSynthesis();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF59E0B)
                  : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey[300] : Colors.grey[800]),
            ),
          ),
        ),
      ),
    );
  }

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading:
                const Icon(Icons.photo_camera, color: Color(0xFFF59E0B)),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.photo_library, color: Color(0xFFF59E0B)),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: PERSONAL MATCHMAKER (QUIZ & CUSTOM CREATIONS)
  // ---------------------------------------------------------------------------
  Widget _buildMatchmakerTab(bool isDark) {
    final recipients = [
      'Partner / Spouse',
      'Mother / Parent',
      'Best Friend',
      'Colleague / Boss',
      'Self-Care Treat'
    ];
    final occasions = [
      'Anniversary',
      'Birthday',
      'Get Well Soon',
      'Apology / Reconciliation',
      'Graduation / Success',
      'Just Because'
    ];
    final vibes = [
      'Romantic Red',
      'Pastel Soft & Sweet',
      'Sunny Vibrant',
      'Rustic Earthy',
      'Modern Luxury White'
    ];
    final budgets = [
      '₱500 - ₱1,000',
      '₱1,000 - ₱2,500',
      '₱2,500 - ₱5,000',
      'Luxury Unlimited'
    ];
    final tones = [
      'Heartfelt & Deep',
      'Playful & Cheerful',
      'Poetic & Elegant',
      'Short & Sweet'
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 36),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Personal Floral Matchmaker',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Answer 5 quick preferences and let Gemini create a custom flower formula & card note!',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quiz Fields
          _buildDropdownSection(
              '1. Who is this for?', _selectedRecipient, recipients, (val) {
            if (val != null) setState(() => _selectedRecipient = val);
          }, isDark),

          _buildDropdownSection(
              '2. What is the occasion?', _selectedOccasion, occasions, (val) {
            if (val != null) setState(() => _selectedOccasion = val);
          }, isDark),

          _buildDropdownSection('3. Desired Color Vibe', _selectedVibe, vibes,
                  (val) {
                if (val != null) setState(() => _selectedVibe = val);
              }, isDark),

          _buildDropdownSection('4. Budget Range', _selectedBudget, budgets,
                  (val) {
                if (val != null) setState(() => _selectedBudget = val);
              }, isDark),

          _buildDropdownSection(
              '5. Card Message Sentiment', _selectedTone, tones, (val) {
            if (val != null) setState(() => _selectedTone = val);
          }, isDark),

          const SizedBox(height: 16),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isGeneratingMatch ? null : _generateMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isGeneratingMatch
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.favorite_rounded),
              label: Text(
                _isGeneratingMatch
                    ? 'Curating Custom Creation...'
                    : 'Generate AI Creation & Card Note',
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Results
          if (_matchResult != null) ...[
            Text(
              'Your Custom AI Creation',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF121212),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border:
                Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bouquet Preview Image
                  if (_matchResult!['imageUrl'] != null)
                    ClipRRect(
                      borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Stack(
                        children: [
                          Image.network(
                            _matchResult!['imageUrl'],
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4),
                                ],
                              ),
                              child: Text(
                                _matchResult!['estimatedPrice'] ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _matchResult!['title'] ??
                                    'Custom Floral Creation',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF121212),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _matchResult!['explanation'] ?? '',
                          style: TextStyle(
                              fontSize: 13,
                              color:
                              isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.4),
                        ),

                        const Divider(height: 24),

                        // Stem Formula Breakdown
                        Text(
                          'Stem Formula (For 3D Builder):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        ...((_matchResult!['flowerFormula'] as List?) ?? [])
                            .map(
                              (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B)
                                        .withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.local_florist,
                                      color: Color(0xFFF59E0B), size: 14),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "${f['count']}x ${f['flower']} (${f['color']})",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.grey[200]
                                            : Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Card Note
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF282828)
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                const Color(0xFFF59E0B).withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.card_membership,
                                          color: Color(0xFFF59E0B), size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'AI Generated Card Note:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy,
                                        size: 18, color: Color(0xFFF59E0B)),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text:
                                          _matchResult!['cardNote'] ?? ''));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Card note copied to clipboard!')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '"${_matchResult!['cardNote']}"',
                                style: GoogleFonts.cormorantGaramond(
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF121212),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Care Tip
                        if (_matchResult!['careTip'] != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.tips_and_updates_outlined,
                                  color: Color(0xFFF59E0B), size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "Care Tip: ${_matchResult!['careTip']}",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600]),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 20),

                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const BuilderPage()));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.view_in_ar),
                          label: const Text('Build This Bouquet in 3D Studio'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownSection(String title, String selected,
      List<String> options, ValueChanged<String?> onChanged, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262626) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF262626) : Colors.white,
                items: options
                    .map(
                        (opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: FLORA AI CONCIERGE CHAT
  // ---------------------------------------------------------------------------
  Widget _buildChatConciergeTab(bool isDark) {
    final suggestedQuestions = [
      'What flowers represent gratitude & thankfulness?',
      'How do I make my roses stay fresh for 2 weeks?',
      'Best flower arrangement for a 1st anniversary?',
      'Explain the meaning of yellow vs red roses',
    ];

    return Column(
      children: [
        // Concierge Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFF7ED),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFF59E0B),
                child: Icon(Icons.support_agent, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Flora - AI Floriography Specialist',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                        'Ask anything about flower meanings, care tips & bouquet advice!',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                            isDark ? Colors.grey[400] : Colors.grey[600])),
                  ],
                ),
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
                      color: const Color(0xFFF59E0B).withOpacity(0.4)),
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          color:
                          isUser ? Colors.white70 : const Color(0xFFF59E0B),
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
                            if (chatImg == null) return const SizedBox.shrink();
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
                  color: Colors.black.withOpacity(0.05),
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
                      hintText: 'Ask Flora about flower meanings, care...',
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
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: () => _sendChatMessage(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PottedFlowerPainter extends CustomPainter {
  final String flowerType;
  final String potType;

  PottedFlowerPainter({
    required this.flowerType,
    required this.potType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // 1. Draw Stems & Leaves inside vase
    _drawStemsAndLeaves(canvas, w, h);

    // 2. Draw Flowers on top
    _drawFlowers(canvas, w, h);

    // 3. Draw Pot / Glass Crystal Vase (Paso) over stems for realistic glass transparency!
    _drawPot(canvas, w, h);
  }

  void _drawPot(Canvas canvas, double w, double h) {
    final potPath = Path();
    final potTopY = h * 0.62;
    final potBottomY = h * 0.95;
    final potTopWidth = w * 0.55;
    final potBottomWidth = w * 0.38;

    final potLeftTop = (w - potTopWidth) / 2;
    final potRightTop = potLeftTop + potTopWidth;
    final potLeftBottom = (w - potBottomWidth) / 2;
    final potRightBottom = potLeftBottom + potBottomWidth;

    // Body
    potPath.moveTo(potLeftTop, potTopY);
    potPath.lineTo(potRightTop, potTopY);
    potPath.lineTo(potRightBottom, potBottomY);
    potPath.quadraticBezierTo(w / 2, potBottomY + 6, potLeftBottom, potBottomY);
    potPath.close();

    Color potColor;
    Color rimColor;
    switch (potType) {
      case 'ceramic':
        potColor = const Color(0xEEF3F4F6);
        rimColor = const Color(0xFFD1D5DB);
        break;
      case 'glass':
        potColor = const Color(0x66E0F2FE); // Semi-transparent glass vase water
        rimColor = const Color(0xCC38BDF8);
        break;
      case 'gold':
        potColor = const Color(0xEEF59E0B);
        rimColor = const Color(0xFFCA8A04);
        break;
      case 'terracotta':
      default:
        potColor = const Color(0xEEC2410C);
        rimColor = const Color(0xFF9A3412);
        break;
    }

    final potPaint = Paint()
      ..color = potColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(potPath, potPaint);

    // Water level for Glass Vase
    if (potType == 'glass') {
      final waterPath = Path();
      final waterY = potTopY + (potBottomY - potTopY) * 0.35;
      waterPath.moveTo(potLeftTop + 3, waterY);
      waterPath.lineTo(potRightTop - 3, waterY);
      waterPath.lineTo(potRightBottom - 1, potBottomY - 2);
      waterPath.quadraticBezierTo(
          w / 2, potBottomY + 4, potLeftBottom + 1, potBottomY - 2);
      waterPath.close();

      canvas.drawPath(
        waterPath,
        Paint()..color = const Color(0x440284C7),
      );

      // Glass shine highlight
      final shinePath = Path()
        ..moveTo(potLeftTop + 8, potTopY + 4)
        ..lineTo(potLeftTop + 16, potTopY + 4)
        ..lineTo(potLeftBottom + 10, potBottomY - 6)
        ..lineTo(potLeftBottom + 4, potBottomY - 6)
        ..close();
      canvas.drawPath(
        shinePath,
        Paint()..color = Colors.white.withOpacity(0.45),
      );
    }

    // Rim
    final rimRect = RRect.fromLTRBR(
      potLeftTop - 4,
      potTopY - 8,
      potRightTop + 4,
      potTopY + 4,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rimRect,
      Paint()..color = rimColor,
    );

    // Glass / Pot 3D outline highlight
    canvas.drawPath(
      potPath,
      Paint()
        ..color = potType == 'glass'
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  void _drawStemsAndLeaves(Canvas canvas, double w, double h) {
    final stemPaint = Paint()
      ..color = const Color(0xFF15803D)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final leafPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..style = PaintingStyle.fill;

    final potTopY = h * 0.60;

    // Stem 1 (Center)
    final path1 = Path()
      ..moveTo(w * 0.5, potTopY)
      ..quadraticBezierTo(w * 0.48, h * 0.4, w * 0.5, h * 0.22);
    canvas.drawPath(path1, stemPaint);

    // Stem 2 (Left)
    final path2 = Path()
      ..moveTo(w * 0.48, potTopY)
      ..quadraticBezierTo(w * 0.3, h * 0.45, w * 0.28, h * 0.32);
    canvas.drawPath(path2, stemPaint);

    // Stem 3 (Right)
    final path3 = Path()
      ..moveTo(w * 0.52, potTopY)
      ..quadraticBezierTo(w * 0.7, h * 0.42, w * 0.72, h * 0.28);
    canvas.drawPath(path3, stemPaint);

    // Leaves
    _drawLeaf(canvas, w * 0.38, h * 0.48, -0.6, leafPaint);
    _drawLeaf(canvas, w * 0.62, h * 0.46, 0.6, leafPaint);
    _drawLeaf(canvas, w * 0.42, h * 0.35, -0.4, leafPaint);
    _drawLeaf(canvas, w * 0.58, h * 0.38, 0.5, leafPaint);
  }

  void _drawLeaf(Canvas canvas, double x, double y, double angle, Paint paint) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(12, -8, 22, 0)
      ..quadraticBezierTo(12, 8, 0, 0);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawFlowers(Canvas canvas, double w, double h) {
    switch (flowerType) {
      case 'rose':
        _drawRose(canvas, w * 0.5, h * 0.20, 22);
        _drawRose(canvas, w * 0.28, h * 0.30, 18);
        _drawRose(canvas, w * 0.72, h * 0.26, 19);
        break;
      case 'tulip':
        _drawTulip(canvas, w * 0.5, h * 0.20, 20);
        _drawTulip(canvas, w * 0.28, h * 0.30, 16);
        _drawTulip(canvas, w * 0.72, h * 0.26, 17);
        break;
      case 'lily':
        _drawLily(canvas, w * 0.5, h * 0.20, 24);
        _drawLily(canvas, w * 0.28, h * 0.30, 20);
        _drawLily(canvas, w * 0.72, h * 0.26, 21);
        break;
      case 'carnation':
        _drawCarnation(canvas, w * 0.5, h * 0.20, 22);
        _drawCarnation(canvas, w * 0.28, h * 0.30, 18);
        _drawCarnation(canvas, w * 0.72, h * 0.26, 19);
        break;
      case 'sunflower':
      default:
        _drawSunflower(canvas, w * 0.5, h * 0.20, 26);
        _drawSunflower(canvas, w * 0.28, h * 0.30, 20);
        _drawSunflower(canvas, w * 0.72, h * 0.26, 22);
        break;
    }
  }

  void _drawSunflower(Canvas canvas, double cx, double cy, double radius) {
    // Inner Layer 1: Outer Petals with Gradient
    for (int i = 0; i < 16; i++) {
      final angle = (i * math.pi / 8);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final petalPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(7, -radius * 0.6, 0, -radius)
        ..quadraticBezierTo(-7, -radius * 0.6, 0, 0);

      final petalPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, -radius),
          [
            const Color(0xFFD97706),
            const Color(0xFFFBBF24),
            const Color(0xFFFEF08A)
          ],
        );
      canvas.drawPath(petalPath, petalPaint);
      canvas.restore();
    }

    // Inner Layer 2: Secondary Petals
    for (int i = 0; i < 16; i++) {
      final angle = (i * math.pi / 8) + (math.pi / 16);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final petalPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(5, -radius * 0.5, 0, -radius * 0.85)
        ..quadraticBezierTo(-5, -radius * 0.5, 0, 0);

      final petalPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, -radius * 0.85),
          [const Color(0xFFB45309), const Color(0xFFF59E0B)],
        );
      canvas.drawPath(petalPath, petalPaint);
      canvas.restore();
    }

    // Textured Center Disk with Radial Shading
    final centerRect =
    Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.45);
    final centerPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx - 2, cy - 2),
        radius * 0.45,
        [
          const Color(0xFF451A03),
          const Color(0xFF78350F),
          const Color(0xFF92400E)
        ],
      );
    canvas.drawCircle(Offset(cx, cy), radius * 0.45, centerPaint);

    // Center seed texture dots
    final dotPaint = Paint()..color = const Color(0xFFFDE68A).withOpacity(0.4);
    for (int d = 0; d < 12; d++) {
      final dotAngle = d * (math.pi / 6);
      final dx = cx + math.cos(dotAngle) * (radius * 0.25);
      final dy = cy + math.sin(dotAngle) * (radius * 0.25);
      canvas.drawCircle(Offset(dx, dy), 1.2, dotPaint);
    }
  }

  void _drawRose(Canvas canvas, double cx, double cy, double radius) {
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    final rosePaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx - radius * 0.3, cy - radius * 0.3),
        radius * 1.2,
        [
          const Color(0xFFEF4444),
          const Color(0xFFDC2626),
          const Color(0xFF991B1B),
          const Color(0xFF450A0A)
        ],
      );

    canvas.drawCircle(Offset(cx, cy), radius, rosePaint);

    // Overlapping Rose Petal Swirls
    final swirlPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.75),
        0.2,
        2.5,
        false,
        swirlPaint);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.55),
        2.8,
        2.8,
        false,
        swirlPaint);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius * 0.35),
        1.0,
        3.1,
        false,
        swirlPaint);
    canvas.drawCircle(Offset(cx, cy), radius * 0.18,
        Paint()..color = const Color(0xFF450A0A));
  }

  void _drawTulip(Canvas canvas, double cx, double cy, double radius) {
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    final tulipPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, cy + radius),
        Offset(cx, cy - radius),
        [
          const Color(0xFFBE185D),
          const Color(0xFFEC4899),
          const Color(0xFFFBCFE8)
        ],
      );

    final path = Path()
      ..moveTo(cx - radius, cy + radius * 0.5)
      ..quadraticBezierTo(cx - radius * 1.2, cy - radius, cx, cy - radius * 1.2)
      ..quadraticBezierTo(
          cx + radius * 1.2, cy - radius, cx + radius, cy + radius * 0.5)
      ..quadraticBezierTo(
          cx, cy + radius * 1.2, cx - radius, cy + radius * 0.5);
    canvas.drawPath(path, tulipPaint);
  }

  void _drawLily(Canvas canvas, double cx, double cy, double radius) {
    for (int i = 0; i < 6; i++) {
      final angle = (i * math.pi / 3);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final petalPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(9, -radius * 0.5, 0, -radius)
        ..quadraticBezierTo(-9, -radius * 0.5, 0, 0);

      final lilyPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, -radius),
          [const Color(0xFFFDE047), Colors.white, Colors.white],
        );
      canvas.drawPath(petalPath, lilyPaint);
      canvas.restore();
    }
    canvas.drawCircle(Offset(cx, cy), radius * 0.22,
        Paint()..color = const Color(0xFFCA8A04));
  }

  void _drawCarnation(Canvas canvas, double cx, double cy, double radius) {
    for (int i = 0; i < 10; i++) {
      final angle = (i * math.pi / 5);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      final carnationPaint = Paint()
        ..shader = ui.Gradient.radial(
          const Offset(0, 0),
          radius,
          [
            const Color(0xFFF472B6),
            const Color(0xFFDB2777),
            const Color(0xFF9D174D)
          ],
        );
      canvas.drawCircle(
          Offset(0, -radius * 0.4), radius * 0.45, carnationPaint);
      canvas.restore();
    }
    canvas.drawCircle(
        Offset(cx, cy), radius * 0.3, Paint()..color = const Color(0xFF831843));
  }

  @override
  bool shouldRepaint(covariant PottedFlowerPainter oldDelegate) {
    return oldDelegate.flowerType != flowerType ||
        oldDelegate.potType != potType;
  }
}