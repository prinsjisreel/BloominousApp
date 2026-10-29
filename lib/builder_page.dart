import 'dart:convert'; // jsonEncode / base64Encode: how models travel to the 3D scene
import 'dart:typed_data'; // Uint8List: raw bytes of a .glb file
import 'dart:ui'; // Added for Glassmorphism blur effects
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; // reads the app's own assets
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // reads every branch's inventory
import 'package:url_launcher/url_launcher.dart';
import 'package:camera/camera.dart';
import 'package:webview_flutter/webview_flutter.dart'; // the 3D scene lives in one WebView
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

// ---------------------------------------------------------------------------
// WRAPPER COLOUR CHOICES
// One entry = one round swatch in the "WRAPPER COLOUR" panel.
//   color == null  -> keep the wrapper model's own colours (no tint)
//   color != null  -> the wrapper is tinted with this colour
// To add a colour, add one line here. Nothing else needs to change.
// ---------------------------------------------------------------------------
class _WrapSwatch {
  final String name;
  final Color? color;
  const _WrapSwatch(this.name, this.color);
}

const List<_WrapSwatch> _kWrapSwatches = [
  _WrapSwatch('Original', null),
  _WrapSwatch('Blush', Color(0xFFF4B6C2)),
  _WrapSwatch('Rose', Color(0xFFD9708A)),
  _WrapSwatch('Red', Color(0xFFC62828)),
  _WrapSwatch('Lavender', Color(0xFFB39DDB)),
  _WrapSwatch('Sky', Color(0xFF90CAF9)),
  _WrapSwatch('Mint', Color(0xFFA5D6A7)),
  _WrapSwatch('Sunshine', Color(0xFFFFE082)),
  _WrapSwatch('Cream', Color(0xFFFFF3E0)),
  _WrapSwatch('Charcoal', Color(0xFF455A64)),
];

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
  // THE 3D BOUQUET SCENE
  // The wrapper and ALL the flowers live together in ONE 3D scene (one WebView).
  // That is what lets the whole bouquet turn 360 degrees as one piece, and what
  // makes the flowers sit truly INSIDE the wrapper (the scene handles depth).
  // The look (sizes, how far flowers fan out, spin speed) is tuned in the
  // CONFIG block at the top of _sceneHtml, at the bottom of this class.
  // -------------------------------------------------------------------------
  final String? _wrapperModel = 'assets/models/wrapper.glb';

  // Safety limits so the phone never has to draw an enormous bouquet.
  static const int _maxPerType = 12; // most stems shown of ONE flower type
  static const int _maxFlowers = 24; // most stems shown in total

  late final WebViewController _web;
  bool _sceneReady = false; // the 3D page started and can receive models
  bool _sceneSynced = false; // the first batch of flowers has been sent
  bool _syncing = false; // a send is running right now
  bool _syncAgain = false; // flowers changed again while a send was running
  final Set<String> _sentModels = {}; // models the scene already has
  final Set<String> _failedModels = {}; // models that could not be loaded
  final Map<String, Future<void>> _modelJobs = {}; // one download + send per model
  final Set<String> _knownSources = {}; // models of the flowers in the list
  bool _prefetching = false; // the background pre-loader is running
  final Set<String> _loadingModels = {}; // server models the page is fetching right now
  static const int _maxPrefetch = 0; // 0 = a model loads only when a flower is picked
  String? _wrapperNote; // e.g. "wrapper.glb not found"
  String? _flowerNote; // e.g. "2 flower(s) have no 3D model yet"

  // The colour the customer picked for the wrapper (starts on "Original").
  _WrapSwatch _wrapSwatch = _kWrapSwatches.first;

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
    _pushFlowers(); // the flower shows up at once (a stand-in until its model arrives)
    _syncScene(); // then make sure the real model gets there
  }

  void _removeItem(String id) {
    setState(() {
      final index = _selectedItems.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        _selectedItems.removeAt(index);
      }
    });
    _pushFlowers(); // the flower disappears at once
    _syncScene();
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
    _initScene();
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
      _rememberSources(rows); // start loading their 3D models in the background
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

  // ---------------------------------------------------------------------
  // 3D SCENE: Flutter <-> web page
  //   Flutter -> page : _web.runJavaScript('bloomXxx(...)')
  //   page -> Flutter : BloomChannel.postMessage('ready' / 'error:...')
  // ---------------------------------------------------------------------

  // Creates the WebView and loads the 3D page into it.
  void _initScene() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent) // the camera shows through
      ..addJavaScriptChannel('BloomChannel', onMessageReceived: _onSceneMessage)
      ..loadHtmlString(_sceneHtml);

    // Safety net: if the 3D engine never starts (e.g. no internet), say so.
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_sceneReady) {
        setState(() => _wrapperNote =
        'The 3D view is taking too long. Check your internet connection.');
      }
    });
  }

  // Messages sent FROM the page TO Flutter.
  void _onSceneMessage(JavaScriptMessage message) {
    final String msg = message.message;
    if (msg == 'ready') {
      // The page is alive: send the wrapper, then the flowers picked so far.
      _sceneReady = true;
      _pushWrapperToScene();
      _syncScene();
      _prefetchAll(); // warm up the models of the flowers in the list
    } else if (msg.startsWith('modelready:')) {
      // The page finished reading a model: hide the "Loading..." note.
      final String src = msg.substring('modelready:'.length);
      if (mounted) setState(() => _loadingModels.remove(src));
    } else if (msg.startsWith('modelerror:')) {
      // A flower model downloaded fine but the 3D page could not read it.
      // Format: modelerror:<source>|<reason>
      final String body = msg.substring('modelerror:'.length);
      final int cut = body.indexOf('|');
      final String src = cut == -1 ? body : body.substring(0, cut);
      final String why = cut == -1 ? '' : body.substring(cut + 1);
      debugPrint('3D model unreadable ($src): $why');
      _sentModels.remove(src);
      _failedModels.add(src);
      if (mounted) setState(() => _loadingModels.remove(src));
      _syncScene(); // refresh the "no 3D model" note
    } else if (msg.startsWith('info:')) {
      // Measurements the page took (wrapper size, flower head size): handy for tuning.
      debugPrint('3D scene $msg');
    } else if (msg.startsWith('error:')) {
      debugPrint('3D scene: $msg');
    }
  }

  // Runs one JavaScript call in the page (does nothing before the page is ready).
  Future<void> _runJs(String js) async {
    if (!_sceneReady || !mounted) return;
    try {
      await _web.runJavaScript(js);
    } catch (e) {
      debugPrint('3D scene call failed: $e');
    }
  }

  // '#RRGGBB' text that the page understands.
  String _cssHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // Gets the raw bytes of a model that lives INSIDE the app ('assets/...').
  // Returns null if it cannot be read. (Server models are not handled here:
  // the 3D page fetches those links itself, see _ensureModelInScene.)
  Future<Uint8List?> _loadAssetBytes(String path) async {
    try {
      final ByteData data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e) {
      debugPrint('Asset failed to load ($path): $e');
      return null;
    }
  }

  // Sends the wrapper model, its colour and whether it is visible.
  Future<void> _pushWrapperToScene() async {
    final String? path = _wrapperModel;
    if (path != null) {
      final Uint8List? bytes = await _loadAssetBytes(path);
      if (bytes != null) {
        await _runJs('bloomSetWrapper(${jsonEncode(base64Encode(bytes))});');
      } else if (mounted) {
        setState(() => _wrapperNote = 'Wrapper model not found ($path).');
      }
    }
    await _applyWrapperColor();
    await _applyWrapperVisibility();
  }

  Future<void> _applyWrapperColor() {
    final Color? c = _wrapSwatch.color;
    // '' means "Original": the page puts the model's own colours back.
    return _runJs("bloomSetWrapperColor('${c == null ? '' : _cssHex(c)}');");
  }

  Future<void> _applyWrapperVisibility() =>
      _runJs('bloomShowWrapper($_showWrapper);');

  // Which model file a picked flower uses: its own link, else the built-in one.
  String _modelSourceFor(Map<String, dynamic> item) {
    final String name = (item['name'] ?? '').toString();
    final String model = (item['model'] ?? '').toString().trim();
    if (model.isNotEmpty) return model;
    return _modelMapping[name] ?? _modelMapping['Red Rose']!;
  }

  // What the scene should show: one entry per model, with how many copies.
  // Example: [{src: 'assets/models/Rose.glb', count: 3}, {src: 'https://..', count: 2}]
  List<Map<String, dynamic>> _desiredFlowers() {
    final Map<String, int> countBySrc = {};
    final Map<String, int> countByName = {};
    int total = 0;
    for (final item in _selectedItems) {
      final String name = (item['name'] ?? '').toString();
      if (total >= _maxFlowers || (countByName[name] ?? 0) >= _maxPerType) {
        continue;
      }
      final String src = _modelSourceFor(item);
      countByName[name] = (countByName[name] ?? 0) + 1;
      countBySrc[src] = (countBySrc[src] ?? 0) + 1;
      total++;
    }
    return countBySrc.entries
        .map((e) => <String, dynamic>{'src': e.key, 'count': e.value})
        .toList();
  }

  // Tells the scene right now how many flowers of each model to show. It does
  // NOT wait for any download: flowers whose model is still on its way are drawn
  // as a stand-in bud, then swapped by the real model when it arrives.
  // Models that failed to load are left out, so no fake bud stays forever.
  Future<void> _pushFlowers() {
    final List<Map<String, dynamic>> shown = _desiredFlowers()
        .where((d) => !_failedModels.contains(d['src']))
        .toList();
    return _runJs('bloomSetFlowers(${jsonEncode(shown)});');
  }

  // Downloads one model and sends it to the scene, ONCE. If the pre-loader is
  // already busy with this model, a tap on "+" simply waits for that same job
  // instead of downloading the model a second time.
  Future<void> _ensureModelInScene(String src) {
    if (!_sceneReady) return Future.value(); // retried when the page says 'ready'
    return _modelJobs.putIfAbsent(src, () async {
      _sentModels.add(src);
      if (src.startsWith('http://') || src.startsWith('https://')) {
        // SERVER model: only hand the link over. The page downloads it by itself
        // and reports back 'modelready:' / 'modelerror:'.
        if (mounted) setState(() => _loadingModels.add(src));
        await _runJs('bloomLoadUrl(${jsonEncode(src)});');
      } else {
        // BUILT-IN model: it is inside the app, so Flutter hands over its bytes.
        final Uint8List? bytes = await _loadAssetBytes(src);
        if (bytes == null) {
          _sentModels.remove(src);
          _failedModels.add(src);
        } else {
          await _runJs(
              'bloomLoadModel(${jsonEncode(src)}, ${jsonEncode(base64Encode(bytes))});');
        }
      }
    });
  }

  // Remembers which models the flower list uses (the first few only).
  void _rememberSources(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (_knownSources.length >= _maxPrefetch) break;
      _knownSources.add(_modelSourceFor(row));
    }
    _prefetchAll();
  }

  // Loads those models in the background, one at a time, so the first tap on
  // "+" does not have to wait for a download.
  Future<void> _prefetchAll() async {
    if (!_sceneReady || _prefetching) return;
    _prefetching = true;
    try {
      for (final src in _knownSources.toList()) {
        if (_failedModels.contains(src)) continue;
        await _ensureModelInScene(src);
      }
    } finally {
      _prefetching = false;
    }
  }

  // Makes the scene match the picked flowers. Called after every + / - tap.
  // Taps that arrive while a send is running are merged into one more pass.
  Future<void> _syncScene() async {
    if (!_sceneReady) return; // runs again when the page says 'ready'
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final List<Map<String, dynamic>> desired = _desiredFlowers();

        // 1. Make sure the scene has every model it needs (usually it already
        // does, because the pre-loader sent them while the customer was browsing).
        for (final d in desired) {
          final String src = d['src'] as String;
          if (_failedModels.contains(src)) continue;
          await _ensureModelInScene(src);
        }

        // 2. Final update (also removes the stand-in of a model that failed).
        await _pushFlowers();

        // 3. Note flowers that have no usable 3D model.
        int missing = 0;
        for (final d in desired) {
          if (_failedModels.contains(d['src'])) missing += d['count'] as int;
        }
        if (mounted) {
          setState(() {
            _sceneSynced = true;
            _flowerNote =
            missing > 0 ? '$missing flower(s) have no 3D model yet.' : null;
          });
        }
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  // The hint shown over the scene while no flower is picked.
  Widget _buildEmptyHint() {
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
    // Height of the phone's gesture/nav bar. viewPadding (not padding) is used
    // because this Scaffold has resizeToAvoidBottomInset: false.
    final double bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final Color topBarText = _isArEnabled ? Colors.white70 : _kRoseDeep;

    return Scaffold(
      // The keyboard slides OVER the screen instead of squashing the panels.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 0. BACKDROP (camera, or a soft gradient when there is no camera)
          _buildBackdrop(),

          // 1. THE 3D BOUQUET: wrapper + flowers in ONE scene. Drag sideways on
          // it to turn the whole bouquet 360 degrees (it also spins slowly by itself).
          Positioned(
            top: 100, // Pushed down to clear the top logo bar
            bottom: 100 + bottomInset, // Pushed up to clear AR toggles + system bar
            left: 16,
            // Dynamically adjust right padding based on device width and panel state to prevent squishing
            right: _isMenuOpen && _showPanel ? (narrow ? 300 : 370) : 16,
            child: Stack(
              children: [
                Positioned.fill(child: WebViewWidget(controller: _web)),
                if (_selectedItems.isEmpty) IgnorePointer(child: _buildEmptyHint()),
                // Small status line: loading, or what could not be loaded.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Text(
                      !_sceneSynced
                          ? 'Building your 3D bouquet...'
                          : _loadingModels.isNotEmpty
                          ? 'Loading 3D flower...'
                          : [_wrapperNote, _flowerNote]
                          .whereType<String>()
                          .join(' '),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _isArEnabled ? Colors.white70 : _kRoseDeep),
                    ),
                  ),
                ),
              ],
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
                      SizedBox(height: 30 + bottomInset),
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
              bottom: 20 + bottomInset,
              width: narrow ? 280 : 350,
              child: Column(
                children: [
                  _buildSearchSection(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildFlowerSelection()),
                  if (_showWrapper && _wrapperModel != null) ...[
                    const SizedBox(height: 12),
                    _buildWrapperColorSection(),
                  ],
                  const SizedBox(height: 12),
                  _buildSummaryPanel(),
                ],
              ),
            ),

          // 5. AR TRACKING INDICATOR & TOGGLE
          Positioned(
            bottom: 120 + bottomInset,
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
            bottom: 180 + bottomInset,
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
            bottom: 240 + bottomInset,
            right: _isMenuOpen && _showPanel ? (narrow ? 300 : 380) : 20,
            child: FloatingActionButton.small(
              heroTag: 'toggle_wrapper',
              backgroundColor:
              _showWrapper ? _kAmber : Colors.white.withOpacity(0.95),
              onPressed: () {
                setState(() => _showWrapper = !_showWrapper);
                _applyWrapperVisibility();
              },
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

  // The "WRAPPER COLOUR" panel: a row of round swatches.
  Widget _buildWrapperColorSection() {
    return _buildAestheticPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 14, color: _kAmberDeep),
              const SizedBox(width: 6),
              Text(
                'WRAPPER COLOUR',
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _kRoseDeep,
                    letterSpacing: 1.5),
              ),
              const Spacer(),
              Text(
                _wrapSwatch.name,
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kWrapSwatches.map(_buildWrapSwatch).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // One round colour button. The picked one gets an amber ring.
  Widget _buildWrapSwatch(_WrapSwatch swatch) {
    final bool picked = identical(swatch, _wrapSwatch);
    return GestureDetector(
      onTap: () {
        if (picked) return;
        setState(() => _wrapSwatch = swatch);
        _applyWrapperColor(); // instant: no reload, the scene just recolours
      },
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: swatch.color ?? Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: picked ? _kAmber : _kRose.withOpacity(0.25),
            width: picked ? 2.5 : 1,
          ),
        ),
        // "Original" has no colour, so it shows a small reset icon instead.
        child: swatch.color == null
            ? const Icon(Icons.format_color_reset, size: 15, color: _kRose)
            : null,
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

  // ---------------------------------------------------------------------
  // The 3D scene page (three.js, a JavaScript 3D library). It is loaded from
  // the internet when the screen opens, so this screen needs a connection.
  // ---------------------------------------------------------------------
  static const String _sceneHtml = r'''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; height: 100%; background: transparent; overflow: hidden; touch-action: none; }
  canvas { display: block; }
</style>
<script type="importmap">
{ "imports": {
    "three": "https://unpkg.com/three@0.160.0/build/three.module.js",
    "three/addons/": "https://unpkg.com/three@0.160.0/examples/jsm/"
} }
</script>
</head>
<body>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';

// ---- Tweak the look here -------------------------------------------------
const CONFIG = {
  wrapperHeight: 2.2,    // wrapper height in scene units
  wrapperTiltXDeg: 0,    // use 90, -90 or 180 if wrapper.glb loads lying down / upside down
  mouthRatio: 0.70,      // width of the wrapper OPENING as a fraction of the wrapper's widest width
  mouthY: 0.79,          // height of the opening plane (fraction of wrapper height; the tallest paper tips are higher)
  headLift: 0.0,        // height of the head centres vs the wrapper rim (fraction of wrapper height; negative = nested slightly inside)
  dome: 0.08,            // the middle heads sit this much higher than the edge ones (a gentle dome, like a real bouquet)
  spread: 0.72,          // how far from the middle the outer heads may go (fraction of the opening radius)
  headWidth: 0.38,       // width of EVERY flower head, as a fraction of the wrapper opening (never changes with the count)
  gap: 0.90,             // spacing between heads when there is room (1 = just touching, lower = overlapping a bit)
  headFrac: 0.88,        // fallback only: how high up a flower its head centre is (each model is measured)
  faceAxis: 'z',         // which way the flower's FACE points in its own 3D model when the stem is upright:
                         //   'z' = toward you (most models), '-z', 'x', '-x', or 'y' = straight up along the stem
  fanYawDeg: 50,         // flowers on the left/right turn their faces this much to the left/right (a fan, like a real bouquet)
  faceElevationDeg: 40,  // how far the faces tilt UP from sideways (0 = look straight out, 90 = look straight up)
  clipBelow: 0.55,       // flower parts below this point inside the wrapper are hidden (0 = at the waist, 1 = at the rim)
  camLift: 0.25,         // how far above the bouquet the camera sits (0 = eye level, bigger = looks more down into it)
  autoSpin: 0,           // 0 = the bouquet only turns when the customer drags it
  viewHeight: 3.1,       // how much of the scene must fit on screen (height)
  viewWidth: 2.5,        // ... and (width)
  lookY: 1.15,           // the camera looks at this height
  // Wrapper paper look: matte, soft and even (not glossy plastic)
  wrapperRoughness: 0.92, // 0 = shiny, 1 = fully matte
  wrapperMetalness: 0,    // paper is not metal
  wrapperEnv: 0.55,       // how strongly the room reflects on it (lower = flatter, softer)
  sunLight: 0.55,         // the one directional light (lower = softer shadows)
  fillLight: 1.1          // even light from all sides (higher = brighter creases)
};
// --------------------------------------------------------------------------

function post(msg) {
  if (window.BloomChannel) window.BloomChannel.postMessage(msg);
}

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setClearColor(0x000000, 0);              // transparent: the camera shows through
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.localClippingEnabled = true;             // lets us cut the hidden lower part of the flowers
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;   // soft studio light
const sun = new THREE.DirectionalLight(0xffffff, CONFIG.sunLight);
sun.position.set(3, 6, 4);
scene.add(sun);
scene.add(new THREE.HemisphereLight(0xffffff, 0xe8e8f0, CONFIG.fillLight));   // soft light from every side

const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 100);

// "spin" holds the wrapper AND the flowers, so they always rotate TOGETHER.
const spin = new THREE.Group();
const wrapperGroup = new THREE.Group();
const flowerGroup = new THREE.Group();
spin.add(wrapperGroup);
spin.add(flowerGroup);
scene.add(spin);

// Soft shadow on the "floor" (does not spin).
(function addShadow() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  grad.addColorStop(0, 'rgba(0,0,0,0.45)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(2.2, 2.2),
    new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(c), transparent: true, depthWrite: false })
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.01;
  scene.add(mesh);
})();

const loader = new GLTFLoader();
// Many exported models are compressed (Draco / Meshopt). Without these two
// decoders such a model silently fails to load and the flower never appears.
const draco = new DRACOLoader();
draco.setDecoderPath('https://unpkg.com/three@0.160.0/examples/jsm/libs/draco/gltf/');
loader.setDRACOLoader(draco);
loader.setMeshoptDecoder(MeshoptDecoder);
// A simple stand-in flower (green stem + pink bud). It is shown instantly while
// the real 3D model is still downloading, then swapped for the real one.
const placeholder = (function () {
  const g = new THREE.Group();
  const stem = new THREE.Mesh(
    new THREE.CylinderGeometry(0.012, 0.012, 0.8, 8),
    new THREE.MeshStandardMaterial({ color: 0x4f7a3a, roughness: 0.8 })
  );
  stem.position.y = 0.4;
  const bud = new THREE.Mesh(
    new THREE.SphereGeometry(0.09, 20, 14),
    new THREE.MeshStandardMaterial({ color: 0xe8a0b4, roughness: 0.6 })
  );
  bud.position.y = 0.86;
  bud.scale.y = 1.25;
  g.add(stem, bud);
  g.userData.width = 0.18;     // widest part, at height 1 (used by the fit rule)
  g.userData.headFrac = 0.86;  // how high the bud sits
  return g;
})();
const modelCache = {};      // model source -> ready-to-clone flower (scaled, bottom-centred)
let desired = [];           // [{src, count}] sent by Flutter
// Measured from the REAL wrapper model when it loads (these are only fallbacks):
//   waistY = height of the narrow "tie" where the stems are gathered
//   rimY   = height of the top edge
//   openR  = radius of the opening at the top
let fit = { waistY: CONFIG.wrapperHeight * 0.4, rimY: CONFIG.wrapperHeight, openR: CONFIG.wrapperHeight * 0.35 };
let wrapperColor = '';      // '' = keep the wrapper's own colours
let wrapperVisible = true;

function b64ToBuffer(b64) {
  return fetch('data:application/octet-stream;base64,' + b64).then(r => r.arrayBuffer());
}
function parseGlb(buffer) {
  return new Promise((resolve, reject) => loader.parse(buffer, '', resolve, reject));
}
function fail(err) { post('error:' + ((err && err.message) || err)); }

function materialsOf(obj) {
  if (!obj.isMesh) return [];
  return Array.isArray(obj.material) ? obj.material : [obj.material];
}

// Tints every material of the wrapper, or puts the original colours back.
function applyWrapperColor() {
  wrapperGroup.traverse(obj => {
    materialsOf(obj).forEach(m => {
      if (!m.color) return;
      if (!m.userData.origColor) m.userData.origColor = m.color.clone();
      if (wrapperColor) m.color.set(wrapperColor);
      else m.color.copy(m.userData.origColor);
    });
  });
}

// Looks at every point of the wrapper and works out where its waist and opening are.
function measureWrapper() {
  spin.updateMatrixWorld(true);
  const H = CONFIG.wrapperHeight;
  const SLICES = 40;
  const widest = new Array(SLICES).fill(0);   // widest point of each horizontal slice
  const v = new THREE.Vector3();
  wrapperGroup.traverse(o => {
    if (!o.isMesh || !o.geometry.attributes.position) return;
    const pos = o.geometry.attributes.position;
    for (let k = 0; k < pos.count; k++) {
      v.fromBufferAttribute(pos, k).applyMatrix4(o.matrixWorld);
      const r = Math.hypot(v.x, v.z);
      const s = Math.min(SLICES - 1, Math.max(0, Math.floor(v.y / H * SLICES)));
      if (r > widest[s]) widest[s] = r;
    }
  });

  // Waist = the narrowest slice in the middle part of the wrapper.
  let bestSlice = -1, bestWidth = Infinity;
  for (let s = Math.floor(SLICES * 0.25); s <= Math.floor(SLICES * 0.7); s++) {
    const w = ((widest[s - 1] || widest[s]) + widest[s] + (widest[s + 1] || widest[s])) / 3;
    if (w > 0 && w < bestWidth) { bestWidth = w; bestSlice = s; }
  }
  fit.waistY = bestSlice >= 0 ? (bestSlice + 0.5) / SLICES * H : H * 0.4;

  // The opening: the widest part of the wrapper is its full width; the mouth is a fixed
  // share of that. (Reading the opening from the paper tips is unreliable: they are thin.)
  const maxR = Math.max.apply(null, widest);
  fit.openR = Math.max(H * 0.2, CONFIG.mouthRatio * maxR);
  fit.rimY = CONFIG.mouthY * H;                                   // the plane the heads sit on
  fit.waistY = Math.min(H * 0.6, Math.max(H * 0.3, fit.waistY));  // keep the waist believable
  post('info:wrapper widest=' + (maxR * 2).toFixed(2) + ' height=' + H + ' waistY=' + fit.waistY.toFixed(2) +
       ' mouthR=' + fit.openR.toFixed(2) + ' mouthY=' + fit.rimY.toFixed(2));
}

// Where do the heads go? A list of {x, z, u} spots on the wrapper opening.
//   u = 0 in the middle ... 1 at the outer edge (used to make a gentle dome).
const GOLDEN = 2.399963;   // golden angle: spreads points evenly, like sunflower seeds
function layoutHeads(n, headW, R) {
  const pts = [];
  if (n === 1) return [{ x: 0, z: 0, u: 0 }];
  if (n <= 6) {
    // A few flowers: one in the middle (from 5 up) and the rest in a ring, just touching.
    const ring = n >= 5 ? n - 1 : n;
    const rho = Math.min(R, (headW * 0.5 / Math.sin(Math.PI / ring)) * 0.9);
    if (n >= 5) pts.push({ x: 0, z: 0, u: 0 });
    for (let k = 0; k < ring; k++) {
      const a = (k / ring) * Math.PI * 2 + 0.4;
      pts.push({ x: Math.sin(a) * rho, z: -Math.cos(a) * rho, u: rho / R });
    }
    return pts;
  }
  // Many flowers: a sunflower-seed spiral. The heads keep their size and spacing;
  // only when the opening is full do they start to overlap (the spiral is squeezed to fit).
  const c = Math.min(headW * CONFIG.gap / 1.8, R / Math.sqrt(n));
  for (let i = 0; i < n; i++) {
    const r = c * Math.sqrt(i + 0.5);
    const a = i * GOLDEN;
    pts.push({ x: Math.sin(a) * r, z: -Math.cos(a) * r, u: r / R });
  }
  return pts;
}

const UP = new THREE.Vector3(0, 1, 0);

// Everything of a flower that is far down INSIDE the wrapper is invisible anyway,
// but leaves and stems can poke through the paper at the waist. So the part of each
// flower below this height is cut off. (Not when the wrapper is hidden.)
const clipPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
function applyFlowerClip() {
  clipPlane.constant = -(fit.waistY + CONFIG.clipBelow * (fit.rimY - fit.waistY));
  const templates = Object.values(modelCache).concat([placeholder]);
  templates.forEach(tpl => tpl.traverse(o => {
    materialsOf(o).forEach(m => {
      const want = wrapperVisible ? [clipPlane] : null;
      if ((m.clippingPlanes && m.clippingPlanes.length) !== (want && want.length)) m.needsUpdate = true;
      m.clippingPlanes = want;
    });
  }));
}

// Turns a flower so (1) its stem points along `dir` and (2) its FACE looks toward the
// FRONT of the bouquet and a bit upward, fanned slightly to the left or right depending
// on which side of the bouquet the flower is on. Like a real florist bouquet, nothing
// faces the back: from behind you only see the wrapper. (The flowers cannot be turned
// one by one, so they are placed facing the right way from the start.)
const _Y = new THREE.Vector3(), _Z = new THREE.Vector3(), _X = new THREE.Vector3(), _F = new THREE.Vector3();
const _M = new THREE.Matrix4();
function orientFlower(q, dir, p, i) {
  if (CONFIG.faceAxis === 'y') { q.setFromUnitVectors(UP, dir); return; }

  // The direction the face should look: toward the front (+z), fanned left/right by
  // where the flower stands (left flowers look a bit left, right ones a bit right),
  // and tilted upward.
  const xn = Math.max(-1, Math.min(1, p.x / (fit.openR * CONFIG.spread)));
  const yaw = THREE.MathUtils.degToRad(CONFIG.fanYawDeg) * xn;
  const elev = THREE.MathUtils.degToRad(CONFIG.faceElevationDeg + 8 * Math.sin(i * 2.1));
  _F.set(Math.sin(yaw) * Math.cos(elev), Math.sin(elev), Math.cos(yaw) * Math.cos(elev)).normalize();

  // Keep the face direction at a right angle to the stem, then build the flower's 3 axes.
  _Y.copy(dir);
  _F.addScaledVector(_Y, -_F.dot(_Y));
  if (_F.lengthSq() < 1e-6) { q.setFromUnitVectors(UP, dir); return; }
  _F.normalize();
  switch (CONFIG.faceAxis) {
    case '-z': _Z.copy(_F).negate(); _X.crossVectors(_Y, _Z); break;
    case 'x':  _X.copy(_F); _Z.crossVectors(_X, _Y); break;
    case '-x': _X.copy(_F).negate(); _Z.crossVectors(_X, _Y); break;
    default:   _Z.copy(_F); _X.crossVectors(_Y, _Z);      // 'z'
  }
  _M.makeBasis(_X, _Y, _Z);
  q.setFromRotationMatrix(_M);
}

// Builds the bouquet. For each flower we first decide WHERE ITS HEAD goes (a spot
// inside the wrapper opening), then we size and tilt the flower so the head lands
// exactly there, with the stem running back down to the wrapper's waist.
function rebuild() {
  while (flowerGroup.children.length) flowerGroup.remove(flowerGroup.children[0]);
  applyFlowerClip();

  // Mix the flower types (round-robin) so they are not grouped by kind.
  const lanes = desired
    .map(d => ({ tpl: modelCache[d.src] || placeholder, left: d.count }));
  const list = [];
  let added = true;
  while (added) {
    added = false;
    lanes.forEach(l => { if (l.left > 0) { list.push(l.tpl); l.left--; added = true; } });
  }

  const n = list.length;
  if (n === 0) return;
  const H = CONFIG.wrapperHeight;
  const headW = CONFIG.headWidth * 2 * fit.openR;        // the SAME for every flower, whatever n is
  const spots = layoutHeads(n, headW, fit.openR * CONFIG.spread);
  const base = new THREE.Vector3(0, fit.waistY, 0);      // where all the stems gather

  list.forEach((tpl, i) => {
    const p = spots[i];
    const headFrac = tpl.userData.headFrac || CONFIG.headFrac;   // measured on this flower model

    // 1. Where the head centre must end up.
    const headY = fit.rimY + CONFIG.headLift * H + CONFIG.dome * H * (1 - p.u * p.u);
    const target = new THREE.Vector3(p.x, headY, p.z);
    const dir = target.clone().sub(base).normalize();    // the way the stem leans

    // 2. Size: every head has the same width. It depends only on the flower model and
    //    the wrapper, NEVER on how many flowers there are. (A very long flower is capped
    //    so its stem never pokes out of the bottom of the wrapper.)
    const highestHead = fit.rimY + CONFIG.headLift * H + CONFIG.dome * H;
    const s = Math.min(headW / (tpl.userData.width || 1), (highestHead - fit.waistY * 0.5) / headFrac);

    const inst = SkeletonUtils.clone(tpl);
    inst.scale.setScalar(s);

    // 3. Tilt the flower along the stem direction and slide it so the head lands on the spot.
    const pivot = new THREE.Group();
    pivot.add(inst);
    orientFlower(pivot.quaternion, dir, p, i);
    pivot.position.copy(target).addScaledVector(dir, -headFrac * s);
    flowerGroup.add(pivot);
  });
}

async function setWrapper(b64) {
  const gltf = await parseGlb(await b64ToBuffer(b64));
  const model = gltf.scene;
  model.rotation.x = THREE.MathUtils.degToRad(CONFIG.wrapperTiltXDeg);

  model.traverse(obj => {
    materialsOf(obj).forEach(m => {
      m.side = THREE.DoubleSide;                       // show inside AND outside of the paper
      if (m.metalness !== undefined) m.metalness = CONFIG.wrapperMetalness;   // matte paper, not shiny
      if (m.roughness !== undefined) m.roughness = CONFIG.wrapperRoughness;
      m.envMapIntensity = CONFIG.wrapperEnv;
      m.needsUpdate = true;
    });
  });

  // Scale to a fixed height, centre it, and stand its tip on y = 0.
  let box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  model.scale.setScalar(CONFIG.wrapperHeight / (size.y || 1));
  box = new THREE.Box3().setFromObject(model);
  const centre = box.getCenter(new THREE.Vector3());
  model.position.set(-centre.x, -box.min.y, -centre.z);

  while (wrapperGroup.children.length) wrapperGroup.remove(wrapperGroup.children[0]);
  wrapperGroup.add(model);
  wrapperGroup.visible = wrapperVisible;
  applyWrapperColor();
  measureWrapper();   // find the waist and the opening of THIS wrapper
  rebuild();          // flowers re-fit to them
}

// Turns the raw bytes of a flower .glb into a ready-to-clone template.
async function loadFlowerBuffer(src, buffer) {
  const gltf = await parseGlb(buffer);
  const model = gltf.scene;

  // Normalise to height 1 with the bottom-centre at the origin.
  // rebuild() later multiplies it to the size that fits THIS wrapper.
  let box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  model.scale.setScalar(1 / (size.y || 1));
  box = new THREE.Box3().setFromObject(model);
  const centre = box.getCenter(new THREE.Vector3());
  model.position.set(-centre.x, -box.min.y, -centre.z);

  const holder = new THREE.Group();     // keeps the offset above when the flower is cloned
  holder.add(model);

  // Measure the HEAD. Leaves and stems can be wider than the head, so only the TOP
  // 40% of the flower is looked at: that is where the head is on every flower.
  // From it we learn how high the head centre sits and how wide the head is.
  holder.updateMatrixWorld(true);
  const SL = 25;
  const FIRST = Math.floor(SL * 0.6);
  const wide = new Array(SL).fill(0);
  const v = new THREE.Vector3();
  holder.traverse(o => {
    if (!o.isMesh || !o.geometry.attributes.position) return;
    const pos = o.geometry.attributes.position;
    for (let k = 0; k < pos.count; k++) {
      v.fromBufferAttribute(pos, k).applyMatrix4(o.matrixWorld);
      const s = Math.min(SL - 1, Math.max(0, Math.floor(v.y * SL)));
      const half = Math.max(Math.abs(v.x), Math.abs(v.z));
      if (half > wide[s]) wide[s] = half;
    }
  });
  let topMax = 0;
  for (let s = FIRST; s < SL; s++) topMax = Math.max(topMax, wide[s]);
  let sum = 0, cnt = 0;
  for (let s = FIRST; s < SL; s++) if (wide[s] >= topMax * 0.7) { sum += s + 0.5; cnt++; }
  holder.userData.headFrac = cnt ? Math.min(0.98, Math.max(0.6, sum / cnt / SL)) : CONFIG.headFrac;
  // A head is never thinner than 12% or wider than 60% of the flower's height.
  holder.userData.width = Math.min(0.6, Math.max(0.12, topMax * 2));
  post('info:flower ' + src.slice(-40) + ' headFrac=' + holder.userData.headFrac.toFixed(2) +
       ' headWidth(at height 1)=' + (topMax * 2).toFixed(2));
  modelCache[src] = holder;
  rebuild();
  post('modelready:' + src);
}

// Built-in models: Flutter sends the bytes (they live inside the app).
async function loadFlower(src, b64) {
  await loadFlowerBuffer(src, await b64ToBuffer(b64));
}

// Server models: THIS PAGE fetches the link straight from the server, like the
// old model-viewer did. Flutter never touches the file.
async function loadFlowerFromUrl(src) {
  const res = await fetch(src);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  await loadFlowerBuffer(src, await res.arrayBuffer());
}

// ---- Functions Flutter calls ----------------------------------------------
window.bloomSetWrapper = b64 => { setWrapper(b64).catch(fail); };
window.bloomSetWrapperColor = hex => { wrapperColor = hex || ''; applyWrapperColor(); };
window.bloomShowWrapper = visible => { wrapperVisible = !!visible; wrapperGroup.visible = wrapperVisible; applyFlowerClip(); };
window.bloomLoadModel = (src, b64) => {
  loadFlower(src, b64).catch(err => post('modelerror:' + src + '|' + ((err && err.message) || err)));
};
window.bloomLoadUrl = src => {
  loadFlowerFromUrl(src).catch(err => post('modelerror:' + src + '|' + ((err && err.message) || err)));
};
window.bloomSetFlowers = list => { desired = list || []; rebuild(); };

// ---- Camera: always fits the whole bouquet, on any screen shape ------------
function fitCamera() {
  const w = window.innerWidth, h = window.innerHeight;
  if (!w || !h) return;
  renderer.setSize(w, h);
  camera.aspect = w / h;
  const half = Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2);
  const distH = (CONFIG.viewHeight / 2) / half;
  const distW = (CONFIG.viewWidth / 2) / (half * camera.aspect);
  const dist = Math.max(distH, distW);
  camera.position.set(0, CONFIG.lookY + dist * CONFIG.camLift, dist);   // a bit from above, so the flowers inside the opening are visible
  camera.lookAt(0, CONFIG.lookY, 0);
  camera.updateProjectionMatrix();
}
fitCamera();
window.addEventListener('resize', fitCamera);

// ---- Drag sideways to turn the bouquet 360 degrees (no auto-spin) ------------
let dragging = false;
let lastX = 0;
renderer.domElement.addEventListener('pointerdown', e => { dragging = true; lastX = e.clientX; });
window.addEventListener('pointerup', () => { dragging = false; });
window.addEventListener('pointercancel', () => { dragging = false; });
window.addEventListener('pointermove', e => {
  if (!dragging) return;
  spin.rotation.y += (e.clientX - lastX) * 0.01;
  lastX = e.clientX;
});

let lastW = 0, lastH = 0;
renderer.setAnimationLoop(() => {
  // The page can start with a 0 x 0 size; catch up as soon as it has one.
  if (window.innerWidth !== lastW || window.innerHeight !== lastH) {
    lastW = window.innerWidth;
    lastH = window.innerHeight;
    fitCamera();
  }
  if (!dragging && CONFIG.autoSpin) spin.rotation.y += CONFIG.autoSpin;
  renderer.render(scene, camera);
});

post('ready');   // tells Flutter: "send me the models now"
</script>
</body>
</html>
''';
}