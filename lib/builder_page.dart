import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:camera/camera.dart';
import 'dart:math' as math;
import 'inventory_data.dart';
import 'payment_service.dart';
import 'delivery_details_page.dart';
import 'auth_page.dart';

class BuilderPage extends StatefulWidget {
  const BuilderPage({super.key});

  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  final List<Map<String, dynamic>> _selectedItems = [];
  final TextEditingController _aiController = TextEditingController();
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  String _paymentMethod = 'paymongo';
  bool _isMenuOpen = true;
  bool _showPanel = true;
  bool _isAISectionMinimized = false;
  bool _isFlowersMinimized = false;
  bool _isSummaryMinimized = true;
  bool _isArEnabled = true; // Added AR Toggle state
  bool _showWrapper = true; // Added showWrapper state variable
  String? _manualModelSelection;

  final Map<String, String> _modelMapping = {
    'Red Rose': 'assets/models/Rose.glb',
    'Pink Rose': 'assets/models/Rose.glb',
    'White Rose': 'assets/models/Rose.glb',
    'red rose': 'assets/models/Rose.glb',
    'pink rose': 'assets/models/Rose.glb',
    'white rose': 'assets/models/Rose.glb',
    'rose': 'assets/models/Rose.glb',
    'Rose': 'assets/models/Rose.glb',
    'Sunflower': 'assets/models/Sunflower.glb',
    'sunflower': 'assets/models/Sunflower.glb',
    'Lily': 'assets/models/lily.glb',
    'lily': 'assets/models/lily.glb',
    'Tulip': 'assets/models/tulip 3.glb',
    'tulip': 'assets/models/tulip 3.glb',
    'Chivas Regal': 'assets/models/flowerBear.glb',
    'chivas regal': 'assets/models/flowerBear.glb',
    'Ferrero Bouquet': 'assets/models/flowerBear.glb',
    'ferrero bouquet': 'assets/models/flowerBear.glb',
    'Teddy Bear': 'assets/models/flowerBear.glb',
    'teddy bear': 'assets/models/flowerBear.glb',
    'Heart Pillow': 'assets/models/flowerBear.glb',
    'heart pillow': 'assets/models/flowerBear.glb',
  };

  void _addItem(Map<String, dynamic> item) {
    setState(() {
      _selectedItems.add(item);
      _manualModelSelection = item['name'];
    });
  }

  void _removeItem(String id) {
    setState(() {
      final index = _selectedItems.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        _selectedItems.removeAt(index);
      }
    });
  }

  int _getItemCount(String id) {
    return _selectedItems.where((item) => item['id'] == id).length;
  }

  double get _subtotal {
    return _selectedItems.fold(
        0.0, (sum, item) => sum + (item['price'] ?? 0.0));
  }

  double get _customizationCost {
    return _selectedItems.isEmpty ? 0.0 : 300.0; // Base wrapping fee
  }

  double get _total {
    return _subtotal + _customizationCost;
  }

  String _getCurrentModel() {
    if (_manualModelSelection != null) {
      final item = _selectedItems.firstWhere(
        (i) => i['name'] == _manualModelSelection,
        orElse: () => <String, dynamic>{},
      );
      if (item.containsKey('model') && item['model'].toString().isNotEmpty) {
        return item['model'];
      }
    }

    final name = _manualModelSelection ??
        (_selectedItems.isNotEmpty ? _selectedItems.last['name'] : 'Red Rose');
    return _modelMapping[name] ?? _modelMapping['Red Rose']!;
  }

  void _initiateCheckout() {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add some flowers first!')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please log in first to proceed with your bouquet order.'),
          backgroundColor: Color(0xFFF59E0B),
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AuthPage(
            returnAfterLogin: true,
            onLoginSuccess: () {
              _initiateCheckout();
            },
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeliveryDetailsPage(
          cartItems: _selectedItems
              .map((item) => {
                    ...item,
                    'qty': 1,
                  })
              .toList(),
          cartTotal: _total,
          occasion: 'Custom AR Bouquet',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    InventoryData.seedInventoryIfEmpty();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final backCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );
        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _aiController.dispose();
    super.dispose();
  }

  Widget _buildModelLayer() {
    if (_selectedItems.isEmpty) {
      return Container(
        color: _isArEnabled ? Colors.transparent : Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.filter_vintage_outlined,
                  size: 80, color: Colors.pink.withOpacity(0.2)),
              const SizedBox(height: 16),
              Text(
                'YOUR BOUQUET IS EMPTY',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink.withOpacity(0.3),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group items to limit visual clutter but represent quantity
    Map<String, Map<String, dynamic>> itemPrototypes = {};
    Map<String, int> itemGroups = {};
    for (var item in _selectedItems) {
      final name = item['name'] as String;
      itemGroups[name] = (itemGroups[name] ?? 0) + 1;
      if (!itemPrototypes.containsKey(name)) {
        itemPrototypes[name] = item;
      }
    }

    // Flatten to a list of specific visual items to arrange
    List<Map<String, dynamic>> visualItems = [];
    itemGroups.forEach((name, count) {
      final proto = itemPrototypes[name]!;
      String src =
          (proto['model'] != null && proto['model'].toString().isNotEmpty)
              ? proto['model']
              : (_modelMapping[name] ?? _modelMapping['Red Rose']!);

      // Limit to 6 visible of each flower type to avoid heavy resources but show fullness
      int limit = count > 6 ? 6 : count;
      for (int i = 0; i < limit; i++) {
        visualItems.add({
          'name': name,
          'src': src,
          'index': i,
        });
      }
    });

    // Sort or cap visualItems if too many (max 18 flowers across all varieties)
    if (visualItems.length > 18) {
      visualItems = visualItems.sublist(0, 18);
    }

    int totalM = visualItems.length;
    List<Widget> layers = [];

    // Base convergence point for stalks/stems in local 320x440 coordinates
    const double xBase = 160.0;
    const double yBase = 315.0;

    for (int i = 0; i < totalM; i++) {
      final item = visualItems[i];
      final name = item['name'] as String;
      final src = item['src'] as String;
      final itemIndex = item['index'] as int;

      double r = 140.0;
      double theta = 0.0;

      if (totalM == 1) {
        theta = 0.0;
        r = 120.0;
      } else if (totalM <= 5) {
        // Single row, compact fan arrangement
        double maxTheta = 0.18; // Tightly grouped to stay snugly inside wrapper
        theta = -maxTheta + i * ((maxTheta * 2) / (totalM - 1));
        // Parabolic arc lowering outer flowers on left and right sides
        double normalized = (i / (totalM - 1)) * 2 - 1; // -1.0 to 1.0
        r = 145.0 - 32.0 * (normalized * normalized);
      } else {
        // Multi-tier layered arrangement: categorizing into Back, Middle, and Front rows
        int numBack = (totalM * 0.35).ceil();
        int numMiddle = (totalM * 0.35).ceil();
        int numFront = totalM - numBack - numMiddle;

        if (numFront <= 0) numFront = 1;

        int row;
        int indexInRow;
        int rowCount;

        if (i < numBack) {
          row = 0; // Back row
          indexInRow = i;
          rowCount = numBack;
        } else if (i < numBack + numMiddle) {
          row = 1; // Middle row
          indexInRow = i - numBack;
          rowCount = numMiddle;
        } else {
          row = 2; // Front row
          indexInRow = i - numBack - numMiddle;
          rowCount = numFront;
        }

        // Configuration per row to create depths with compact spacing
        double spreadFactor;
        double baseR;

        if (row == 0) {
          // Back row: Tallest flowers, gentle fanning
          spreadFactor = 0.22;
          baseR = 158.0;
        } else if (row == 1) {
          // Middle row: Medium depth, compact fanning
          spreadFactor = 0.14;
          baseR = 132.0;
        } else {
          // Front row: Lowest depth, snug fanning inside tissue collar
          spreadFactor = 0.07;
          baseR = 105.0;
        }

        // Calculate angle of placement within the row
        if (rowCount == 1) {
          theta = 0.0;
        } else {
          theta = -spreadFactor +
              indexInRow * ((spreadFactor * 2) / (rowCount - 1));
        }

        // Parabolic contour for each tier lowering outer side flowers
        double normInRow = rowCount == 1
            ? 0.0
            : (indexInRow / (rowCount - 1)) * 2 - 1; // -1.0 to 1.0
        r = baseR - 25.0 * (normInRow * normInRow);
      }

      // Compute precise local center positions (X, Y)
      double x = xBase + r * math.sin(theta);
      double y = yBase - r * math.cos(theta);

      // Model-specific sizing, offsets, and camera orbit/target configurations
      // to ensure all flower heads look consistently large, proportional, and have their stems completely hidden inside the wrappers!
      double modelWidth = 350.0;
      double modelHeight = 380.0;
      double heightFactor =
          0.78; // generous default crop factor to show top portions cleanly without cutting heads
      String cameraTarget = "0m 0.08m 0m";
      String cameraOrbit = "0deg 75deg 90%";
      double verticalOffset = 0.0;

      final String nameLower = name.toLowerCase();
      final bool isRose = src.contains('Rose') || nameLower.contains('rose');
      final bool isSunflower =
          src.contains('Sunflower') || nameLower.contains('sunflower');
      final bool isLily = src.contains('lily') || nameLower.contains('lily');
      final bool isTulip = src.contains('tulip') || nameLower.contains('tulip');

      if (isRose) {
        modelWidth = 350.0;
        modelHeight = 380.0;
        heightFactor = 0.82;
        cameraTarget =
            "0m 0.09m 0m"; // Center focus on flower head & upper stem
        cameraOrbit =
            "0deg 75deg 88%"; // Balanced fit so bloom is fully visible at top
        verticalOffset =
            18.0; // Lower flower down so head is fully shown & roots buried in wrapper
      } else if (isSunflower) {
        modelWidth = 350.0;
        modelHeight = 380.0;
        heightFactor = 0.82;
        cameraTarget = "0m 0.09m 0m";
        cameraOrbit = "0deg 75deg 88%";
        verticalOffset = 15.0; // Tucked gracefully inside the wrapper
      } else if (isLily) {
        modelWidth = 350.0;
        modelHeight = 380.0;
        heightFactor = 0.82;
        cameraTarget = "0m 0.10m 0m";
        cameraOrbit = "0deg 75deg 90%";
        verticalOffset = 18.0;
      } else if (isTulip) {
        modelWidth = 350.0;
        modelHeight = 380.0;
        heightFactor = 0.82;
        cameraTarget = "0m 0.09m 0m";
        cameraOrbit = "0deg 75deg 88%";
        verticalOffset = 18.0;
      } else {
        // flowerBear items (e.g. teddy bear, heart, chivas, etc.)
        modelWidth = 350.0;
        modelHeight = 380.0;
        heightFactor = 0.82;
        cameraTarget = "0m 0.08m 0m";
        cameraOrbit = "0deg 75deg 90%";
        verticalOffset = 15.0;
      }

      double cropHeight = modelHeight * heightFactor;
      double left = x - (modelWidth / 2);
      double top = y - (cropHeight / 2) + verticalOffset;

      layers.add(
        Positioned(
          width: modelWidth,
          height: cropHeight,
          left: left,
          top: top,
          child: Transform.rotate(
            angle:
                theta, // tilt the model matching its exact direction from stem base
            child: SizedBox(
              width: modelWidth,
              height: cropHeight,
              child: ModelViewer(
                key:
                    ValueKey('model_${name}_${itemIndex}_${i}_${_isArEnabled}'),
                src: src,
                ar: i == 0 && _isArEnabled,
                autoRotate: i == 0,
                cameraControls: i == 0,
                backgroundColor: Colors.transparent,
                arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                cameraOrbit: cameraOrbit,
                cameraTarget: cameraTarget,
                fieldOfView: "auto",
                loading: Loading.eager,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: layers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 0. CAMERA BACKGROUND
          if (_isArEnabled && _isCameraInitialized && _cameraController != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width /
                      _cameraController!.value.aspectRatio,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // 1. AR VIEW BACKGROUND (Empty state) or BOUQUET SYSTEM (Aligned models + wrapper overlay)
          if (_selectedItems.isEmpty)
            _buildModelLayer()
          else
            Positioned(
              bottom: 60, // Unified bottom placement
              left: 0,
              right: _isMenuOpen && _showPanel ? 320 : 0,
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 440,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Layer 1: Back Wrapper (Outer fanning sheets)
                      if (_showWrapper)
                        IgnorePointer(
                          child: CustomPaint(
                            size: const Size(320, 440),
                            painter: BouquetBackWrapperPainter(),
                          ),
                        ),

                      // Layer 2: Harmonized flowers (nested inside)
                      _buildModelLayer(),

                      // Layer 3: Front Wrapper (White collar tissue, handle, crimson bow)
                      if (_showWrapper)
                        IgnorePointer(
                          child: CustomPaint(
                            size: const Size(320, 440),
                            painter: BouquetFrontWrapperPainter(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // 2. LOGO TOP BAR
          Positioned(
            top: 30,
            left: MediaQuery.of(context).size.width < 600 ? 70 : 100,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'bloomypro',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 24, // Smaller
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  if (MediaQuery.of(context).size.width > 600)
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            color: Colors.grey, size: 16),
                        const SizedBox(width: 8),
                        Text('Support',
                            style: GoogleFonts.inter(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // 3. LEFT SIDEBAR (Ultra-Compact on mobile)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width < 600 ? 50 : 70,
            child: Container(
              color: const Color(0xFF4A5C66)
                  .withOpacity(0.9), // Slightly translucent
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  _buildSidebarIcon(Icons.close,
                      isAction: true, onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  _buildSidebarIcon(Icons.visibility_off_outlined,
                      onTap: () => setState(() => _showPanel = !_showPanel)),
                  _buildSidebarIcon(Icons.settings_outlined),
                  _buildSidebarIcon(Icons.layers_outlined),
                  _buildSidebarIcon(Icons.share_outlined),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // 4. FLOATING PANELS (Right Side - More compact on mobile)
          if (_isMenuOpen && _showPanel)
            Positioned(
              right: MediaQuery.of(context).size.width < 600 ? 10 : 20,
              top: 100,
              bottom: 20,
              width: MediaQuery.of(context).size.width < 600 ? 280 : 350,
              child: Column(
                children: [
                  // AI Flower Generator
                  _buildAISection(),
                  const SizedBox(height: 12),
                  // Flower List
                  Expanded(child: _buildFlowerSelection()),
                  const SizedBox(height: 12),
                  // Order Summary
                  _buildSummaryPanel(),
                ],
              ),
            ),

          // 5. AR TRACKING INDICATOR & TOGGLE
          Positioned(
            bottom: 120,
            left: 20,
            child: GestureDetector(
              onTap: () => setState(() => _isArEnabled = !_isArEnabled),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isArEnabled
                      ? Colors.black.withOpacity(0.7)
                      : Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                      color: _isArEnabled
                          ? Colors.green
                          : Colors.grey.withOpacity(0.5),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 8)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _isArEnabled
                            ? const Color(0xFF4CAF50)
                            : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_isArEnabled)
                            BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1)
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isArEnabled ? 'AR IS ON' : 'AR IS OFF',
                      style: TextStyle(
                          color: _isArEnabled ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. TOGGLE INTERFACE BUTTON (Visibility Control)
          Positioned(
            bottom: 180,
            right: _isMenuOpen && _showPanel ? 340 : 20,
            child: FloatingActionButton.small(
              heroTag: 'toggle_ui',
              backgroundColor: Colors.white.withOpacity(0.95),
              onPressed: () => setState(() => _showPanel = !_showPanel),
              child: Icon(_showPanel ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFFF59E0B)),
            ),
          ),

          // 7. TOGGLE WRAPPER COVER BUTTON
          Positioned(
            bottom: 240,
            right: _isMenuOpen && _showPanel ? 340 : 20,
            child: FloatingActionButton.small(
              heroTag: 'toggle_wrapper',
              backgroundColor: _showWrapper
                  ? const Color(0xFFF59E0B)
                  : Colors.white.withOpacity(0.95),
              onPressed: () => setState(() => _showWrapper = !_showWrapper),
              tooltip: 'Toggle Wrapper Cover',
              child: Icon(Icons.layers_clear_outlined,
                  color: _showWrapper ? Colors.white : const Color(0xFFF59E0B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarIcon(IconData icon,
      {bool isAction = false, VoidCallback? onTap}) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 12), // Tighter vertical spacing
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: onTap ?? () {},
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: isAction
            ? IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                backgroundColor: const Color(0xFFF59E0B))
            : null,
      ),
    );
  }

  Widget _buildAISection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI GENERATOR',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                    letterSpacing: 1.5),
              ),
              IconButton(
                icon: Icon(_isAISectionMinimized ? Icons.add : Icons.remove,
                    size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(
                    () => _isAISectionMinimized = !_isAISectionMinimized),
              ),
            ],
          ),
          if (!_isAISectionMinimized) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _aiController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g., Neon Rose',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowerSelection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FLOWERS',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2),
              ),
              IconButton(
                icon: Icon(_isFlowersMinimized ? Icons.add : Icons.remove,
                    size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _isFlowersMinimized = !_isFlowersMinimized),
              ),
            ],
          ),
          if (!_isFlowersMinimized) ...[
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: InventoryData.inventoryStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2));
                  }

                  final flowers = snapshot.data ?? [];

                  if (flowers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              color: Colors.grey, size: 24),
                          const SizedBox(height: 8),
                          Text('No flowers found',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey)),
                          TextButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Retry',
                                style: TextStyle(fontSize: 10)),
                          )
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: flowers.length,
                    itemBuilder: (context, index) {
                      final f = flowers[index];
                      final count = _getItemCount(f['id']);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                    image: NetworkImage(f['image'] ?? ''),
                                    fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(
                                    () => _manualModelSelection = f['name']),
                                child: Container(
                                  color: Colors
                                      .transparent, // Make entire area tappable
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(f['name'],
                                          style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: _manualModelSelection ==
                                                      f['name']
                                                  ? const Color(0xFFF59E0B)
                                                  : Colors.black),
                                          maxLines: 1),
                                      Text('₱${f['price']}',
                                          style: GoogleFonts.cormorantGaramond(
                                              color: const Color(0xFFF59E0B),
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                _buildCounterBtn(
                                    Icons.remove, () => _removeItem(f['id'])),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('$count',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                                _buildCounterBtn(Icons.add, () => _addItem(f)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCounterBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.cyan[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.cyan),
      ),
    );
  }

  Widget _buildSummaryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: const TextStyle(color: Colors.grey, fontSize: 14)),
              Text('₱${_total.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              IconButton(
                icon: Icon(
                    _isSummaryMinimized
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _isSummaryMinimized = !_isSummaryMinimized),
              ),
            ],
          ),
          if (!_isSummaryMinimized) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _initiateCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CHECKOUT',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text('₱${amount.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class BouquetBackWrapperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final rect = Rect.fromLTWH(-60, 0, width + 120, height);

    canvas.save();
    canvas.translate(width * 0.5, height * 0.64);
    canvas.scale(0.80, 0.80);
    canvas.translate(-width * 0.5, -height * 0.64);

    // Soft drop shadow for paper depth & ambient occlusion
    final dropShadow = Paint()
      ..color = const Color(0x3D000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    // 0. Solid Center Backing Sheet Shader
    final backingPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFF381B20), Color(0xFF63333B), Color(0xFF8C4C56)],
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);

    // 1. Far Back Left Wing Shader
    final farLeftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [Color(0xFF452026), Color(0xFF753A44), Color(0xFF9E5460)],
      ).createShader(rect);

    // 2. Far Back Right Wing Shader
    final farRightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF452026), Color(0xFF753A44), Color(0xFF9E5460)],
      ).createShader(rect);

    // 3. Medium Layer Left Fold Shader
    final medLeftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [Color(0xFF5A2A32), Color(0xFF944F5B), Color(0xFFBF7582)],
      ).createShader(rect);

    // 4. Medium Layer Right Fold Shader
    final medRightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF5A2A32), Color(0xFF944F5B), Color(0xFFBF7582)],
      ).createShader(rect);

    // 5. Inner Decorative Folds Shader (Lighter Peach-Rose)
    final innerLeftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [Color(0xFF82414C), Color(0xFFC47D8A), Color(0xFFE8A8B4)],
      ).createShader(rect);

    final innerRightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF82414C), Color(0xFFC47D8A), Color(0xFFE8A8B4)],
      ).createShader(rect);

    // Gold/Cream Metallic Accent Edging
    final goldEdgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFE8C897), Color(0xFFFFF6E5), Color(0xFFD4AF37)],
      ).createShader(rect);

    // White Tissue Paper Liner with soft gradient
    final tissuePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFFDCDCDC), Color(0xFFF7F7F7), Color(0xFFFFFFFF)],
      ).createShader(rect);

    final path = Path();

    // 0. Solid Center Backing Sheet
    final backingPath = Path();
    backingPath.moveTo(60.0, height * 0.12);
    backingPath.quadraticBezierTo(
        width * 0.50, height * 0.04, width - 60.0, height * 0.12);
    backingPath.quadraticBezierTo(
        width * 0.78, height * 0.42, width * 0.50, height * 0.70);
    backingPath.quadraticBezierTo(
        width * 0.22, height * 0.42, 60.0, height * 0.12);
    backingPath.close();
    canvas.drawPath(backingPath, backingPaint);

    // 1. Far Back Left Wing (Trimming maroon width by ~15% to avoid bulkiness)
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(width * 0.12, height * 0.45, -20.0, height * 0.15);
    path.quadraticBezierTo(width * 0.18, height * 0.08, 62.0, height * 0.05);
    path.quadraticBezierTo(
        width * 0.38, height * 0.15, width * 0.5, height * 0.40);
    path.close();
    canvas.drawPath(path.shift(const Offset(0, 3)), dropShadow);
    canvas.drawPath(path, farLeftPaint);

    // 2. Far Back Right Wing
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(
        width * 0.88, height * 0.45, width + 20.0, height * 0.15);
    path.quadraticBezierTo(
        width * 0.82, height * 0.08, width - 62.0, height * 0.05);
    path.quadraticBezierTo(
        width * 0.62, height * 0.15, width * 0.5, height * 0.40);
    path.close();
    canvas.drawPath(path.shift(const Offset(0, 3)), dropShadow);
    canvas.drawPath(path, farRightPaint);

    // 3. Medium Layer Left Fold
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(width * 0.20, height * 0.52, -2.0, height * 0.28);
    path.quadraticBezierTo(width * 0.25, height * 0.22, 80.0, height * 0.18);
    path.quadraticBezierTo(
        width * 0.42, height * 0.32, width * 0.5, height * 0.55);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 3)), dropShadow);
    canvas.drawPath(path, medLeftPaint);

    // Gold/Cream highlight edge for Medium Left Fold
    final highlightPath = Path();
    highlightPath.moveTo(-2.0, height * 0.28);
    highlightPath.quadraticBezierTo(
        width * 0.25, height * 0.22, 80.0, height * 0.18);
    highlightPath.lineTo(75.0, height * 0.19);
    highlightPath.quadraticBezierTo(
        width * 0.23, height * 0.23, 2.0, height * 0.29);
    highlightPath.close();
    canvas.drawPath(highlightPath, goldEdgePaint);

    // 4. Medium Layer Right Fold
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(
        width * 0.80, height * 0.52, width + 2.0, height * 0.28);
    path.quadraticBezierTo(
        width * 0.75, height * 0.22, width - 80.0, height * 0.18);
    path.quadraticBezierTo(
        width * 0.58, height * 0.32, width * 0.5, height * 0.55);
    path.close();
    canvas.drawPath(path.shift(const Offset(-1, 3)), dropShadow);
    canvas.drawPath(path, medRightPaint);

    // Highlight edge for Medium Right Fold
    highlightPath.reset();
    highlightPath.moveTo(width + 2.0, height * 0.28);
    highlightPath.quadraticBezierTo(
        width * 0.75, height * 0.22, width - 80.0, height * 0.18);
    highlightPath.lineTo(width - 75.0, height * 0.19);
    highlightPath.quadraticBezierTo(
        width * 0.73, height * 0.23, width - 2.0, height * 0.29);
    highlightPath.close();
    canvas.drawPath(highlightPath, goldEdgePaint);

    // 5. Inner Decorative Folds
    // Inner Left fold
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(width * 0.30, height * 0.45, 42.0, height * 0.35);
    path.lineTo(98.0, height * 0.24);
    path.quadraticBezierTo(
        width * 0.46, height * 0.40, width * 0.5, height * 0.62);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), dropShadow);
    canvas.drawPath(path, innerLeftPaint);

    // Inner Right fold
    path.reset();
    path.moveTo(width * 0.5, height * 0.70);
    path.quadraticBezierTo(
        width * 0.70, height * 0.45, width - 42.0, height * 0.35);
    path.lineTo(width - 98.0, height * 0.24);
    path.quadraticBezierTo(
        width * 0.54, height * 0.40, width * 0.5, height * 0.62);
    path.close();
    canvas.drawPath(path.shift(const Offset(-1, 2)), dropShadow);
    canvas.drawPath(path, innerRightPaint);

    // PRISTINE WHITE TISSUE PAPER LINER (Fanned outward to cleanly frame flowers and define shape)
    path.reset();
    path.moveTo(width * 0.22, height * 0.70);
    path.quadraticBezierTo(
        width * 0.08, height * 0.42, width * 0.08, height * 0.26);
    path.quadraticBezierTo(
        width * 0.32, height * 0.34, width * 0.50, height * 0.32);
    path.quadraticBezierTo(
        width * 0.68, height * 0.34, width * 0.92, height * 0.26);
    path.quadraticBezierTo(
        width * 0.92, height * 0.42, width * 0.78, height * 0.70);
    path.close();
    canvas.drawPath(path, tissuePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BouquetFrontWrapperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final rect = Rect.fromLTWH(-20, 0, width + 40, height);

    canvas.save();
    canvas.translate(width * 0.5, height * 0.64);
    canvas.scale(0.80, 0.80);
    canvas.translate(-width * 0.5, -height * 0.64);

    // Drop Shadow for Ambient Occlusion
    final dropShadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);

    final softShadow = Paint()
      ..color = const Color(0x28000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    // Shaders for Front Wrapper Folds
    final tissuePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFFDCDCDC), Color(0xFFF7F7F7), Color(0xFFFFFFFF)],
      ).createShader(rect);

    final frontLeftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [Color(0xFF6B333B), Color(0xFFB06873), Color(0xFFD997A0)],
      ).createShader(rect);

    final frontRightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF52252C), Color(0xFF8F4D57), Color(0xFFC27B86)],
      ).createShader(rect);

    final goldEdgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFE8C897), Color(0xFFFFF6E5), Color(0xFFD4AF37)],
      ).createShader(rect);

    final skirtPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5C2C33), Color(0xFF8F4D58), Color(0xFFB8727E)],
      ).createShader(rect);

    final skirtLeftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF38181D), Color(0xFF6E363E), Color(0xFF99535E)],
      ).createShader(rect);

    final skirtRightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF421E23), Color(0xFF7A3C45), Color(0xFFA65E69)],
      ).createShader(rect);

    final path = Path();

    // --- 0. FRONT WRAPPING COLLAR ---
    // White Tissue Paper Collar (Lining inside front paper - pushed outward to define shape)
    final frontTissue = Path();
    frontTissue.moveTo(width * 0.16, height * 0.70);
    frontTissue.quadraticBezierTo(
        width * 0.04, height * 0.42, width * 0.05, height * 0.28);
    frontTissue.quadraticBezierTo(
        width * 0.35, height * 0.36, width * 0.50, height * 0.34);
    frontTissue.quadraticBezierTo(
        width * 0.65, height * 0.36, width * 0.95, height * 0.28);
    frontTissue.quadraticBezierTo(
        width * 0.96, height * 0.42, width * 0.84, height * 0.70);
    frontTissue.close();
    canvas.drawPath(frontTissue, tissuePaint);

    // Front Left Outer Paper Fold (Trimmed width by ~15%)
    final frontLeft = Path();
    frontLeft.moveTo(width * 0.50, height * 0.70);
    frontLeft.quadraticBezierTo(
        width * 0.14, height * 0.46, width * 0.11, height * 0.32);
    frontLeft.quadraticBezierTo(
        width * 0.35, height * 0.37, width * 0.61, height * 0.43);
    frontLeft.quadraticBezierTo(
        width * 0.55, height * 0.58, width * 0.50, height * 0.70);
    frontLeft.close();
    canvas.drawPath(frontLeft.shift(const Offset(1, 3)), dropShadow);
    canvas.drawPath(frontLeft, frontLeftPaint);

    // Gold/Cream border on Front Left Fold
    final frontLeftEdge = Path();
    frontLeftEdge.moveTo(width * 0.11, height * 0.32);
    frontLeftEdge.quadraticBezierTo(
        width * 0.35, height * 0.37, width * 0.61, height * 0.43);
    frontLeftEdge.lineTo(width * 0.60, height * 0.44);
    frontLeftEdge.quadraticBezierTo(
        width * 0.35, height * 0.38, width * 0.12, height * 0.33);
    frontLeftEdge.close();
    canvas.drawPath(frontLeftEdge, goldEdgePaint);

    // Front Right Outer Paper Fold (Trimmed width by ~15%)
    final frontRight = Path();
    frontRight.moveTo(width * 0.50, height * 0.70);
    frontRight.quadraticBezierTo(
        width * 0.86, height * 0.46, width * 0.89, height * 0.32);
    frontRight.quadraticBezierTo(
        width * 0.65, height * 0.37, width * 0.39, height * 0.43);
    frontRight.quadraticBezierTo(
        width * 0.45, height * 0.58, width * 0.50, height * 0.70);
    frontRight.close();
    canvas.drawPath(frontRight.shift(const Offset(-2, 3)), dropShadow);
    canvas.drawPath(frontRight, frontRightPaint);

    // Gold/Cream border on Front Right Fold
    final frontRightEdge = Path();
    frontRightEdge.moveTo(width * 0.89, height * 0.32);
    frontRightEdge.quadraticBezierTo(
        width * 0.65, height * 0.37, width * 0.39, height * 0.43);
    frontRightEdge.lineTo(width * 0.40, height * 0.44);
    frontRightEdge.quadraticBezierTo(
        width * 0.65, height * 0.38, width * 0.88, height * 0.33);
    frontRightEdge.close();
    canvas.drawPath(frontRightEdge, goldEdgePaint);

    // --- 1. THE LUXURY PLEATED LOWER WRAPPER SLING ("Skirt") ---
    // Background layer of skirt
    path.reset();
    path.moveTo(width * 0.42, height * 0.70);
    path.lineTo(width * 0.58, height * 0.70);
    path.quadraticBezierTo(
        width * 0.62, height * 0.88, width * 0.71, height * 0.98);
    path.lineTo(width * 0.29, height * 0.98);
    path.quadraticBezierTo(
        width * 0.38, height * 0.88, width * 0.42, height * 0.70);
    path.close();
    canvas.drawPath(path.shift(const Offset(0, 4)), dropShadow);
    canvas.drawPath(path, skirtPaint);

    // Sculpted Left pleated sheet
    path.reset();
    path.moveTo(width * 0.42, height * 0.70);
    path.lineTo(width * 0.50, height * 0.70);
    path.quadraticBezierTo(
        width * 0.36, height * 0.85, width * 0.25, height * 0.98);
    path.lineTo(width * 0.20, height * 0.98);
    path.quadraticBezierTo(
        width * 0.32, height * 0.85, width * 0.42, height * 0.70);
    path.close();
    canvas.drawPath(path, skirtLeftPaint);

    // Sculpted Right pleated sheet
    path.reset();
    path.moveTo(width * 0.50, height * 0.70);
    path.lineTo(width * 0.58, height * 0.70);
    path.quadraticBezierTo(
        width * 0.64, height * 0.85, width * 0.80, height * 0.98);
    path.lineTo(width * 0.75, height * 0.98);
    path.quadraticBezierTo(
        width * 0.68, height * 0.85, width * 0.58, height * 0.70);
    path.close();
    canvas.drawPath(path, skirtRightPaint);

    // Gold highlight liner on right crease
    final creasePath = Path();
    creasePath.moveTo(width * 0.60, height * 0.70);
    creasePath.quadraticBezierTo(
        width * 0.70, height * 0.85, width * 0.84, height * 0.98);
    creasePath.lineTo(width * 0.82, height * 0.98);
    creasePath.quadraticBezierTo(
        width * 0.68, height * 0.85, width * 0.58, height * 0.70);
    creasePath.close();
    canvas.drawPath(creasePath, goldEdgePaint);

    // --- 2. HIGH-END SATIN RED RIBBON BOW WITH REALISTIC SHADING ---
    const double bowX = 160.0;
    const double bowY = 315.0;

    final ribbonGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF4D4D), Color(0xFFD32F2F), Color(0xFF7A0000)],
      stops: [0.0, 0.5, 1.0],
    ).createShader(const Rect.fromLTWH(bowX - 80, bowY - 40, 160, 160));

    final ribbonPaint = Paint()..shader = ribbonGradient;

    final ribbonShadowGrad = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF520000), Color(0xFF2B0000)],
    ).createShader(const Rect.fromLTWH(bowX - 80, bowY - 40, 160, 160));

    final ribbonShadowPaint = Paint()..shader = ribbonShadowGrad;

    final ribbonSheenPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x88FFFFFF), Color(0x00FFFFFF)],
      ).createShader(const Rect.fromLTWH(bowX - 80, bowY - 40, 160, 160));

    // Shadow cast by bow onto wrapper
    final bowShadow = Path();
    bowShadow.addOval(
        Rect.fromCircle(center: const Offset(bowX, bowY + 8), radius: 36));
    canvas.drawPath(bowShadow, dropShadow);

    // Left Loop of Ribbon
    path.reset();
    path.moveTo(bowX - 10, bowY);
    path.cubicTo(
        bowX - 58, bowY - 35, bowX - 68, bowY + 7, bowX - 10, bowY + 11);
    path.close();
    canvas.drawPath(path, ribbonPaint);

    // Inner shadow of Left Loop
    path.reset();
    path.moveTo(bowX - 10, bowY);
    path.cubicTo(
        bowX - 42, bowY - 22, bowX - 48, bowY - 5, bowX - 10, bowY + 5);
    path.close();
    canvas.drawPath(path, ribbonShadowPaint);

    // Sheen highlight on Left Loop
    path.reset();
    path.moveTo(bowX - 18, bowY - 12);
    path.cubicTo(
        bowX - 45, bowY - 28, bowX - 55, bowY - 10, bowX - 35, bowY - 2);
    path.close();
    canvas.drawPath(path, ribbonSheenPaint);

    // Right Loop of Ribbon
    path.reset();
    path.moveTo(bowX + 10, bowY);
    path.cubicTo(
        bowX + 58, bowY - 35, bowX + 68, bowY + 7, bowX + 10, bowY + 11);
    path.close();
    canvas.drawPath(path, ribbonPaint);

    // Inner shadow of Right Loop
    path.reset();
    path.moveTo(bowX + 10, bowY);
    path.cubicTo(
        bowX + 42, bowY - 22, bowX + 48, bowY - 5, bowX + 10, bowY + 5);
    path.close();
    canvas.drawPath(path, ribbonShadowPaint);

    // Sheen highlight on Right Loop
    path.reset();
    path.moveTo(bowX + 18, bowY - 12);
    path.cubicTo(
        bowX + 45, bowY - 28, bowX + 55, bowY - 10, bowX + 35, bowY - 2);
    path.close();
    canvas.drawPath(path, ribbonSheenPaint);

    // Elegant Left Hanging Ribbon Tail
    path.reset();
    path.moveTo(bowX - 6, bowY + 11);
    path.quadraticBezierTo(bowX - 35, bowY + 45, bowX - 45, bowY + 105);
    path.lineTo(bowX - 25, bowY + 105);
    path.lineTo(bowX - 18, bowY + 95);
    path.lineTo(bowX - 11, bowY + 100);
    path.quadraticBezierTo(bowX - 5, bowY + 50, bowX, bowY + 11);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), softShadow);
    canvas.drawPath(path, ribbonPaint);

    // Elegant Right Hanging Ribbon Tail
    path.reset();
    path.moveTo(bowX + 6, bowY + 11);
    path.quadraticBezierTo(bowX + 35, bowY + 45, bowX + 45, bowY + 105);
    path.lineTo(bowX + 25, bowY + 105);
    path.lineTo(bowX + 18, bowY + 95);
    path.lineTo(bowX + 11, bowY + 100);
    path.quadraticBezierTo(bowX + 5, bowY + 50, bowX, bowY + 11);
    path.close();
    canvas.drawPath(path.shift(const Offset(-1, 2)), softShadow);
    canvas.drawPath(path, ribbonPaint);

    // Center Knot (Sculpted 3D Knot with radial highlight)
    final knotRect = Rect.fromCenter(
        center: const Offset(bowX, bowY + 4), width: 28, height: 22);
    final knotGradient = const RadialGradient(
      center: Alignment(-0.3, -0.4),
      radius: 0.8,
      colors: [Color(0xFFFF6B6B), Color(0xFFC62828), Color(0xFF5E0000)],
    ).createShader(knotRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(knotRect, const Radius.circular(7)),
      Paint()..shader = knotGradient,
    );

    // Knot wrinkle highlights
    final knotHighlight = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(bowX - 6, bowY - 2),
        const Offset(bowX - 4, bowY + 8), knotHighlight);
    canvas.drawLine(const Offset(bowX + 2, bowY - 2),
        const Offset(bowX + 4, bowY + 8), knotHighlight);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
