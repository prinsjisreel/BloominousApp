import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // reads every branch's inventory
import 'package:url_launcher/url_launcher.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:camera/camera.dart';
import 'dart:math' as math;
import 'dart:ui'; // Added for Glassmorphism blur effects
import 'inventory_data.dart';
import 'payment_service.dart';
import 'delivery_details_page.dart';
import 'auth_page.dart';

// ---------------------------------------------------------------------------
// BLOOMINOUS AR PALETTE
// One place for every colour on this screen. The rose tones are taken from the
// wrapper paper itself, so the panels and the bouquet look like one family.
// ---------------------------------------------------------------------------
const Color _kAmber = Color(0xFFF59E0B); // brand amber (buttons, accents)
const Color _kAmberDeep = Color(0xFFD97706); // prices, selected text
const Color _kRose = Color(0xFF9E5460); // same family as the wrapper paper
const Color _kRoseDeep = Color(0xFF5A2A32); // dark text on light backgrounds
const Color _kBlush = Color(0xFFFFF1F3); // soft petal pink
const Color _kCharcoal = Color(0xFF4A5C66); // left sidebar

class BuilderPage extends StatefulWidget {
  const BuilderPage({super.key});

  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  final List<Map<String, dynamic>> _selectedItems = [];

  // The search box above the flower list (was the unused "AI generator" box).
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  String _paymentMethod = 'paymongo';
  bool _isMenuOpen = true;
  bool _showPanel = true;
  bool _isSearchMinimized = false;
  bool _isFlowersMinimized = false;
  bool _isSummaryMinimized = true;
  bool _isArEnabled = true; // Added AR Toggle state
  bool _showWrapper = true; // Added showWrapper state variable
  String? _manualModelSelection;

  // The flower list. Built once in initState (and rebuilt by the Retry button),
  // so the StreamBuilder does not open a brand-new Firestore listener on every redraw.
  late Stream<List<Map<String, dynamic>>> _inventoryStream;

  // -------------------------------------------------------------------------
  // OPTIONAL 3D WRAPPER
  // Today the wrapper is drawn by Flutter code (the two painter classes at the
  // bottom of this file). If you ever get real .glb wrapper models, put the
  // asset paths here and the painters are replaced automatically:
  //   _wrapperBackModel  = the paper BEHIND the flowers
  //   _wrapperFrontModel = the collar, skirt and ribbon IN FRONT of the flowers
  // Leave both null to keep the drawn wrapper.
  // -------------------------------------------------------------------------
  final String? _wrapperBackModel = null; // e.g. 'assets/models/wrapper_back.glb'
  final String? _wrapperFrontModel = null; // e.g. 'assets/models/wrapper_front.glb'

  // -------------------------------------------------------------------------
  // FLOWER LAYOUT TUNING (all numbers are in the 320 x 440 bouquet space)
  // -------------------------------------------------------------------------
  static const double _flowerBoxW = 350.0; // a flower's viewer box at scale 1.0
  static const double _flowerBoxH = 311.6; // (380 * 0.82, same crop as before)
  static const double _stemBaseX = 160.0; // middle of the bouquet
  static const double _headFromTop = 0.25; // flower head sits 25% below the box top

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
    _inventoryStream = _buildInventoryStream();
    _initializeCamera();
  }

  // "Red Rose", " red  rose " and "RED ROSE" all count as the same product.
  String _normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool _isHttpUrl(dynamic value) =>
      value is String &&
          (value.trim().startsWith('http://') || value.trim().startsWith('https://'));

  // The flower list for the builder.
  //   1. It listens to the inventory of EVERY branch (branches/*/inventory).
  //   2. Same product name = ONE row. The row from the branch the customer is
  //      browsing wins; a product that only another branch has still appears.
  //   3. If the winning row has no 3D model but another branch's copy does,
  //      the model link is borrowed, so the AR preview can show it.
  // Errors are NOT swallowed here: the StreamBuilder shows them on screen.
  Stream<List<Map<String, dynamic>>> _buildInventoryStream() {
    final String selected = InventoryData.selectedBranchId ?? 'main_branch';
    final String currentBranch = selected == 'all' ? 'main_branch' : selected;

    return FirebaseFirestore.instance
        .collectionGroup('inventory')
        .snapshots()
        .map((snapshot) {
      final Map<String, Map<String, dynamic>> rowByName = {};
      final Map<String, String> modelByName = {};

      for (final doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        if (data['isDeleted'] == true || data['status'] == 'archived') continue;

        final String name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        // Only real branch products: branches/{branchId}/inventory/{docId}
        final List<String> parts = doc.reference.path.split('/');
        if (parts.length != 4 || parts[0] != 'branches') continue;
        final String branchId = parts[1];
        final bool isCurrentBranch = branchId == currentBranch;

        final String key = _normalizeName(name);
        final Map<String, dynamic> row = <String, dynamic>{
          ...data,
          'id': doc.id,
          'branchId': branchId,
        };

        final Map<String, dynamic>? existing = rowByName[key];
        if (existing == null ||
            (isCurrentBranch && existing['branchId'] != currentBranch)) {
          rowByName[key] = row;
        }

        if (_isHttpUrl(data['model'])) {
          if (!modelByName.containsKey(key) || isCurrentBranch) {
            modelByName[key] = (data['model'] as String).trim();
          }
        }
      }

      final List<Map<String, dynamic>> rows = rowByName.entries.map((entry) {
        final Map<String, dynamic> row = entry.value;
        if (!_isHttpUrl(row['model']) && modelByName[entry.key] != null) {
          row['model'] = modelByName[entry.key];
        }
        return row;
      }).toList();

      rows.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
      return rows;
    });
  }

  // "Retry" button: open a fresh listener.
  void _retryInventory() {
    setState(() => _inventoryStream = _buildInventoryStream());
  }

  // Empties the search box and shows the full flower list again.
  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
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
    _searchController.dispose();
    super.dispose();
  }

  // One wrapper layer (back or front): a 3D model if a path was given,
  // otherwise the Flutter-drawn painter.
  Widget _buildWrapperLayer({
    required String? modelPath,
    required CustomPainter painter,
  }) {
    if (modelPath == null) {
      return IgnorePointer(
        child: CustomPaint(size: const Size(320, 440), painter: painter),
      );
    }
    return IgnorePointer(
      child: SizedBox(
        width: 320,
        height: 440,
        child: ModelViewer(
          key: ValueKey('wrapper_$modelPath'),
          src: modelPath,
          ar: false,
          autoRotate: false,
          cameraControls: false,
          disableZoom: true,
          backgroundColor: Colors.transparent,
          cameraOrbit: '0deg 80deg auto',
        ),
      ),
    );
  }

  Widget _buildModelLayer() {
    if (_selectedItems.isEmpty) {
      // Sits in the open space above the wrapper, so the wrapper stays visible.
      return Align(
        alignment: const Alignment(0, -0.62),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_florist_outlined,
                size: 52,
                color: _isArEnabled
                    ? Colors.white.withOpacity(0.55)
                    : _kRose.withOpacity(0.55)),
            const SizedBox(height: 10),
            Text(
              'YOUR BOUQUET IS EMPTY',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _isArEnabled
                    ? Colors.white.withOpacity(0.85)
                    : _kRose.withOpacity(0.8),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a flower from the list',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _isArEnabled
                    ? Colors.white.withOpacity(0.6)
                    : _kRose.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    // ---- 1. Group the picked items: one prototype per flower name ----
    final Map<String, Map<String, dynamic>> itemPrototypes = {};
    final Map<String, int> itemGroups = {};
    for (final item in _selectedItems) {
      final name = item['name'] as String;
      itemGroups[name] = (itemGroups[name] ?? 0) + 1;
      itemPrototypes.putIfAbsent(name, () => item);
    }

    // ---- 2. Flatten to one entry per visible flower ----
    List<Map<String, dynamic>> visualItems = [];
    itemGroups.forEach((name, count) {
      final proto = itemPrototypes[name]!;
      final String src =
      (proto['model'] != null && proto['model'].toString().trim().isNotEmpty)
          ? proto['model'].toString().trim()
          : (_modelMapping[name] ?? _modelMapping['Red Rose']!);

      // Limit to 6 visible of each flower type to avoid heavy resources but show fullness
      final int limit = count > 6 ? 6 : count;
      for (int i = 0; i < limit; i++) {
        visualItems.add({'name': name, 'src': src, 'index': i});
      }
    });

    // Every flower is a WebView, so cap the total (max 18 across all varieties)
    if (visualItems.length > 18) {
      visualItems = visualItems.sublist(0, 18);
    }

    // ---- 3. Decide HOW MANY ROWS and HOW BIG each flower is ----
    // Few flowers = one row of big heads. Many flowers = 2-3 rows of smaller
    // heads, so the wrapper opening never turns into a pile of overlapping blobs.
    final int total = visualItems.length;
    final int rows = total <= 5 ? 1 : (total <= 11 ? 2 : 3);
    final double baseScale = total <= 1
        ? 0.80
        : total <= 3
        ? 0.72
        : total <= 5
        ? 0.64
        : total <= 11
        ? 0.56
        : 0.48;

    // ---- 4. Work out where each flower HEAD goes ----
    final List<Map<String, dynamic>> placed = [];
    for (int i = 0; i < total; i++) {
      final item = visualItems[i];

      // Deal flowers out like cards: row 0, row 1, row 2, row 0, row 1 ...
      final int row = i % rows;
      final int indexInRow = i ~/ rows;
      final int rowCount = (total - row + rows - 1) ~/ rows;

      // norm: -1 = far left of its row, 0 = middle, +1 = far right
      final double norm =
      rowCount == 1 ? 0.0 : (indexInRow / (rowCount - 1)) * 2 - 1;

      double spreadX; // how far left/right this row's heads reach
      double headY; // how high this row's heads sit (smaller = higher)
      double rowSize; // back row is taller, front row is shorter
      if (rows == 1) {
        spreadX = math.min(84.0, 26.0 * (total - 1));
        headY = 122.0;
        rowSize = 1.0;
      } else if (row == 0) {
        spreadX = 88.0; // back row
        headY = 104.0;
        rowSize = 1.08;
      } else if (row == 1) {
        spreadX = 60.0; // middle row
        headY = 124.0;
        rowSize = 1.0;
      } else {
        spreadX = 32.0; // front row
        headY = 144.0;
        rowSize = 0.9;
      }

      placed.add({
        'name': item['name'],
        'src': item['src'],
        'index': item['index'],
        'row': row,
        'norm': norm,
        'scale': baseScale * rowSize * (1 - 0.08 * norm * norm),
        'hx': _stemBaseX + norm * spreadX,
        // outer flowers sit a little lower, like a natural dome
        'hy': headY + 16.0 * norm * norm,
        // outer flowers lean outward; their stems tilt toward the middle
        'theta': norm * 0.30,
      });
    }

    // Paint order: back row first, and inside a row the outer flowers first,
    // so the middle flower of the front row ends up on top.
    placed.sort((a, b) {
      final int byRow = (a['row'] as int).compareTo(b['row'] as int);
      if (byRow != 0) return byRow;
      return (b['norm'] as double).abs().compareTo((a['norm'] as double).abs());
    });

    // ---- 5. Turn every placement into a positioned 3D viewer ----
    final List<Widget> layers = [];
    for (int k = 0; k < placed.length; k++) {
      final p = placed[k];
      final String name = p['name'] as String;
      final String src = p['src'] as String;
      final int itemIndex = p['index'] as int;
      final double scale = p['scale'] as double;
      final double hx = p['hx'] as double;
      final double hy = p['hy'] as double;
      final double theta = p['theta'] as double;

      final double w = _flowerBoxW * scale;
      final double h = _flowerBoxH * scale;

      // Camera framing per flower type (unchanged from before)
      String cameraTarget = "0m 0.08m 0m";
      String cameraOrbit = "0deg 75deg 90%";
      final String nameLower = name.toLowerCase();
      if (src.contains('Rose') || nameLower.contains('rose')) {
        cameraTarget = "0m 0.09m 0m";
        cameraOrbit = "0deg 75deg 88%";
      } else if (src.contains('Sunflower') || nameLower.contains('sunflower')) {
        cameraTarget = "0m 0.09m 0m";
        cameraOrbit = "0deg 75deg 88%";
      } else if (src.contains('lily') || nameLower.contains('lily')) {
        cameraTarget = "0m 0.10m 0m";
        cameraOrbit = "0deg 75deg 90%";
      } else if (src.contains('tulip') || nameLower.contains('tulip')) {
        cameraTarget = "0m 0.09m 0m";
        cameraOrbit = "0deg 75deg 88%";
      }

      // The LAST layer is painted on top, so it is the one the finger can touch.
      final bool isLead = k == placed.length - 1;

      layers.add(
        Positioned(
          left: hx - w / 2,
          top: hy - h * _headFromTop,
          width: w,
          height: h,
          child: Transform.rotate(
            angle: theta,
            // Tilt around the flower HEAD, so the head stays where we put it
            alignment: Alignment(0, _headFromTop * 2 - 1),
            child: ModelViewer(
              key: ValueKey('model_${name}_${itemIndex}_${k}_${_isArEnabled}_$src'),
              src: src,
              ar: isLead && _isArEnabled,
              autoRotate: isLead,
              cameraControls: isLead,
              // Spin-only: no pinch zoom, no panning, no tilting up/down.
              disableZoom: true,
              disablePan: true,
              disableTap: true,
              minCameraOrbit: 'auto 75deg auto',
              maxCameraOrbit: 'auto 75deg auto',
              backgroundColor: Colors.transparent,
              arModes: const ['scene-viewer', 'webxr', 'quick-look'],
              cameraOrbit: cameraOrbit,
              cameraTarget: cameraTarget,
              fieldOfView: "auto",
              loading: Loading.eager,
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

  // Aesthetic Glassmorphism Base for all floating panels
  Widget _buildAestheticPanel({required Widget child}) {
    // Always a LIGHT glass panel, even when the phone is in dark mode,
    // so the dark-rose text on top of it is always readable.
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kRose.withOpacity(0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: _kRoseDeep.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6))
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // The screen behind the bouquet: the camera when it works, otherwise a soft
  // studio gradient (never a flat black or white screen).
  Widget _buildBackdrop() {
    if (_isArEnabled && _isCameraInitialized && _cameraController != null) {
      return Positioned.fill(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width /
                _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isArEnabled
                ? const [Color(0xFF2B1A20), Color(0xFF4A2A33), Color(0xFF1E1216)]
                : const [Color(0xFFFFF7F2), Color(0xFFFFE4E8), _kBlush],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.of(context).size.width < 600;
    final Color topBarText = _isArEnabled ? Colors.white70 : _kRoseDeep;

    return Scaffold(
      // The keyboard slides OVER the screen instead of squashing the panels.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 0. BACKDROP (camera, or a soft gradient when there is no camera)
          _buildBackdrop(),

          // 1. BOUQUET SYSTEM: wrapper + flowers. The wrapper is ALWAYS drawn
          // (even with an empty bouquet) so it never "disappears".
          Positioned(
            top: 100, // Pushed down to clear the top logo bar
            bottom: 100, // Pushed up to clear AR toggles
            left: 16,
            // Dynamically adjust right padding based on device width and panel state to prevent squishing
            right: _isMenuOpen && _showPanel ? (narrow ? 300 : 370) : 16,
            child: Center(
              // The FittedBox ensures the 320x440 wrapper AND the 3D models
              // scale up or down proportionally on ANY screen size
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 320,
                  height: 440,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Soft ground shadow so the bouquet looks like it stands
                      Positioned(
                        left: 70,
                        right: 70,
                        top: 396,
                        height: 14,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.10),
                              borderRadius: const BorderRadius.all(
                                  Radius.elliptical(90, 12)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.28),
                                    blurRadius: 18,
                                    spreadRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Layer 1: Back Wrapper (Outer fanning sheets)
                      if (_showWrapper)
                        _buildWrapperLayer(
                          modelPath: _wrapperBackModel,
                          painter: BouquetBackWrapperPainter(),
                        ),

                      // Layer 2: Harmonized flowers (or the "empty" hint)
                      _buildModelLayer(),

                      // Layer 3: Front Wrapper (White collar tissue, handle, crimson bow)
                      if (_showWrapper)
                        _buildWrapperLayer(
                          modelPath: _wrapperFrontModel,
                          painter: BouquetFrontWrapperPainter(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. LOGO TOP BAR
          Positioned(
            top: 30,
            left: narrow ? 70 : 100,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_florist, color: _kAmber, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'bloomypro',
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _kAmber,
                        ),
                      ),
                    ],
                  ),
                  if (!narrow)
                    Row(
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            color: topBarText, size: 16),
                        const SizedBox(width: 8),
                        Text('Support',
                            style: GoogleFonts.inter(
                                color: topBarText, fontSize: 11)),
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
            width: narrow ? 50 : 70,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: _kCharcoal.withOpacity(0.6), // Glassmorphism sidebar
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
            ),
          ),

          // 4. FLOATING PANELS (Right Side - More compact on mobile)
          if (_isMenuOpen && _showPanel)
            Positioned(
              right: narrow ? 10 : 20,
              top: 80,
              bottom: 20,
              width: narrow ? 280 : 350,
              child: Column(
                children: [
                  _buildSearchSection(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildFlowerSelection()),
                  const SizedBox(height: 12),
                  _buildSummaryPanel(),
                ],
              ),
            ),

          // 5. AR TRACKING INDICATOR & TOGGLE
          Positioned(
            bottom: 120,
            left: narrow ? 60 : 90,
            child: GestureDetector(
              onTap: () => setState(() => _isArEnabled = !_isArEnabled),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isArEnabled
                          ? Colors.black.withOpacity(0.4)
                          : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                          color: _isArEnabled
                              ? Colors.greenAccent
                              : _kRose.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _isArEnabled
                                ? const Color(0xFF4CAF50)
                                : Colors.grey[600],
                            shape: BoxShape.circle,
                            boxShadow: [
                              if (_isArEnabled)
                                BoxShadow(
                                    color: Colors.greenAccent.withOpacity(0.8),
                                    blurRadius: 8,
                                    spreadRadius: 2)
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isArEnabled ? 'AR IS ON' : 'AR IS OFF',
                          style: TextStyle(
                              color: _isArEnabled ? Colors.white : _kRoseDeep,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 6. TOGGLE INTERFACE BUTTON
          Positioned(
            bottom: 180,
            right: _isMenuOpen && _showPanel ? (narrow ? 300 : 380) : 20,
            child: FloatingActionButton.small(
              heroTag: 'toggle_ui',
              backgroundColor: Colors.white.withOpacity(0.95),
              tooltip: 'Show / hide the panels',
              onPressed: () => setState(() => _showPanel = !_showPanel),
              child: Icon(_showPanel ? Icons.visibility_off : Icons.visibility,
                  color: _kAmber),
            ),
          ),

          // 7. TOGGLE WRAPPER COVER BUTTON
          Positioned(
            bottom: 240,
            right: _isMenuOpen && _showPanel ? (narrow ? 300 : 380) : 20,
            child: FloatingActionButton.small(
              heroTag: 'toggle_wrapper',
              backgroundColor:
              _showWrapper ? _kAmber : Colors.white.withOpacity(0.95),
              onPressed: () => setState(() => _showWrapper = !_showWrapper),
              tooltip: 'Toggle Wrapper Cover',
              child: Icon(Icons.layers_clear_outlined,
                  color: _showWrapper ? Colors.white : _kAmber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarIcon(IconData icon,
      {bool isAction = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: onTap ?? () {},
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: isAction
            ? IconButton.styleFrom(
            padding: const EdgeInsets.all(8), backgroundColor: _kAmber)
            : null,
      ),
    );
  }

  // The search box. Typing here filters the flower list below it live.
  Widget _buildSearchSection() {
    return _buildAestheticPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.search, size: 14, color: _kAmberDeep),
                  const SizedBox(width: 6),
                  Text(
                    'FIND A FLOWER',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _kRoseDeep,
                        letterSpacing: 1.5),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(_isSearchMinimized ? Icons.add : Icons.remove,
                    size: 14, color: _kRoseDeep),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _isSearchMinimized = !_isSearchMinimized),
              ),
            ],
          ),
          if (!_isSearchMinimized) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.inter(fontSize: 13, color: _kRoseDeep),
              cursorColor: _kAmberDeep,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search roses, tulips, bears...',
                hintStyle: GoogleFonts.inter(
                    color: _kRose.withOpacity(0.55), fontSize: 13),
                prefixIcon:
                const Icon(Icons.search, size: 18, color: _kAmberDeep),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.close, size: 16, color: _kRose),
                  onPressed: _clearSearch,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.75),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _kRose.withOpacity(0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _kAmber, width: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowerSelection() {
    return _buildAestheticPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_florist, size: 14, color: _kAmberDeep),
                  const SizedBox(width: 6),
                  Text(
                    'FLOWERS',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _kRoseDeep,
                        letterSpacing: 1.5),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(_isFlowersMinimized ? Icons.add : Icons.remove,
                    size: 14, color: _kRoseDeep),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _isFlowersMinimized = !_isFlowersMinimized),
              ),
            ],
          ),
          if (!_isFlowersMinimized) ...[
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _inventoryStream,
                builder: (context, snapshot) {
                  // A real problem (no permission, no network...) is shown, not hidden.
                  if (snapshot.hasError) {
                    return _buildListMessage(
                      icon: Icons.error_outline,
                      iconColor: Colors.redAccent,
                      title: 'Could not load flowers',
                      detail: '${snapshot.error}',
                      buttonLabel: 'Retry',
                      onPressed: _retryInventory,
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kAmber));
                  }

                  final List<Map<String, dynamic>> allFlowers =
                      snapshot.data ?? [];

                  if (allFlowers.isEmpty) {
                    return _buildListMessage(
                      icon: Icons.inventory_2_outlined,
                      iconColor: Colors.grey,
                      title: 'No flowers found',
                      detail:
                      'Checked every branch (browsing: ${InventoryData.selectedBranchId ?? 'main_branch'})',
                      buttonLabel: 'Retry',
                      onPressed: _retryInventory,
                    );
                  }

                  // ---- SEARCH FILTER: keep flowers whose name or category matches ----
                  final String query = _searchQuery.trim().toLowerCase();
                  final List<Map<String, dynamic>> flowers = query.isEmpty
                      ? allFlowers
                      : allFlowers.where((f) {
                    final String name =
                    (f['name'] ?? '').toString().toLowerCase();
                    final String category =
                    (f['category'] ?? '').toString().toLowerCase();
                    return name.contains(query) || category.contains(query);
                  }).toList();

                  if (flowers.isEmpty) {
                    return _buildListMessage(
                      icon: Icons.search_off,
                      iconColor: _kRose,
                      title: 'No match for "${_searchQuery.trim()}"',
                      detail: 'Try another name, or clear the search.',
                      buttonLabel: 'Clear search',
                      onPressed: _clearSearch,
                    );
                  }

                  return ListView.builder(
                    itemCount: flowers.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) =>
                        _buildFlowerRow(flowers[index]),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // One small centered message (error / empty / no match) with a button.
  Widget _buildListMessage({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String detail,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kRoseDeep)),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[600])),
          TextButton(
            onPressed: onPressed,
            child: Text(buttonLabel,
                style: const TextStyle(fontSize: 12, color: _kAmberDeep)),
          ),
        ],
      ),
    );
  }

  // One flower card in the list: photo, name, price, and the - / + counter.
  Widget _buildFlowerRow(Map<String, dynamic> f) {
    final int count = _getItemCount(f['id']);
    final bool selected = count > 0;
    final bool hasModel = _isHttpUrl(f['model']);
    // A missing/blank photo must not crash the row.
    final String imageUrl =
    _isHttpUrl(f['image']) ? (f['image'] as String).trim() : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // Solid light colours: text stays readable in light AND dark mode.
        color: selected ? const Color(0xFFFFF4D6) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: selected ? _kAmber : _kRose.withOpacity(0.15),
            width: selected ? 1.6 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kBlush,
              borderRadius: BorderRadius.circular(12),
              image: imageUrl.isEmpty
                  ? null
                  : DecorationImage(
                  image: NetworkImage(imageUrl), fit: BoxFit.cover),
            ),
            child: imageUrl.isEmpty
                ? const Icon(Icons.local_florist, color: _kRose, size: 20)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _manualModelSelection = f['name']),
              child: Container(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${f['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _manualModelSelection == f['name']
                                    ? _kAmberDeep
                                    : _kRoseDeep),
                          ),
                        ),
                        // Small cube icon = this product has its own 3D model
                        if (hasModel) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.view_in_ar,
                              size: 12, color: _kAmberDeep),
                        ],
                      ],
                    ),
                    Text('₱${f['price']}',
                        style: GoogleFonts.cormorantGaramond(
                            color: _kAmberDeep,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _buildCounterBtn(Icons.remove, () => _removeItem(f['id'])),
              // Quantity badge: turns solid amber with a white number once picked
              Container(
                constraints: const BoxConstraints(minWidth: 26),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? _kAmberDeep : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kAmber.withOpacity(0.5)),
                ),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: selected ? Colors.white : _kRoseDeep)),
              ),
              _buildCounterBtn(Icons.add, () => _addItem(f), filled: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPanel() {
    final int stems = _selectedItems.length;
    return _buildAestheticPanel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kRoseDeep,
                            letterSpacing: 1.5)),
                    Text(
                        stems == 0
                            ? 'Your bouquet is empty'
                            : '$stems ${stems == 1 ? 'stem' : 'stems'} + wrapping',
                        style: GoogleFonts.inter(
                            fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
              ),
              Text('₱${_total.toStringAsFixed(2)}',
                  style: GoogleFonts.cormorantGaramond(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: _kAmberDeep)),
              IconButton(
                icon: Icon(
                    _isSummaryMinimized
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: _kRoseDeep),
                padding: const EdgeInsets.only(left: 6),
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _isSummaryMinimized = !_isSummaryMinimized),
              ),
            ],
          ),
          if (!_isSummaryMinimized) ...[
            const SizedBox(height: 10),
            _buildSummaryLine('Flowers', _subtotal),
            _buildSummaryLine('Wrapping', _customizationCost),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _initiateCheckout,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAmber,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                label: const Text('CHECKOUT',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // "Flowers ........ ₱500.00" style line inside the summary.
  Widget _buildSummaryLine(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[700])),
          Text('₱${amount.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kRoseDeep)),
        ],
      ),
    );
  }

  // Round-cornered +/- button. filled = the amber "add" button.
  Widget _buildCounterBtn(IconData icon, VoidCallback onTap,
      {bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: filled ? _kAmber : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kAmber.withOpacity(0.5)),
        ),
        child: Icon(icon, size: 16, color: filled ? Colors.white : _kAmber),
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