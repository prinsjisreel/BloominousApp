import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

class ARPreviewPage extends StatefulWidget {
  // The full list of products. Each map should contain:
  //   'name'  : String
  //   'qty'   : int (optional, defaults to 1)
  //   'model' : String (the 3D model URL stored in Firestore inventory)
  final List<Map<String, dynamic>> selectedProducts;
  final Color wrapColor;

  const ARPreviewPage({
    super.key,
    required this.selectedProducts,
    required this.wrapColor,
  });

  @override
  State<ARPreviewPage> createState() => _ARPreviewPageState();
}

class _ARPreviewPageState extends State<ARPreviewPage> {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _cameraError;

  // The ONE web view that holds the whole 3D bouquet (wrapper + flowers).
  late final WebViewController _web;
  bool _populating = false; // guards against filling the scene twice
  bool _sceneLoaded = false; // true once every model finished loading
  String? _sceneNote; // small message shown under the status text

  // Too many flowers in one scene will slow a phone down.
  static const int _maxFlowers = 6;
  static const String _wrapperAsset = 'assets/models/wrapper.glb';
  static const Duration _downloadTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initScene();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found');
        return;
      }
      _controller = CameraController(cameras[0], ResolutionPreset.high);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      // A camera problem should never stop the bouquet from showing.
      if (mounted) setState(() => _cameraError = 'Camera unavailable');
    }
  }

  // Creates the web view and loads the 3D scene page into it.
  void _initScene() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent) // so the camera shows through
      ..addJavaScriptChannel('BloomChannel', onMessageReceived: _onSceneMessage)
      ..loadHtmlString(_sceneHtml);

    // Safety net: if the 3D engine never starts (e.g. no internet), say so.
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_sceneLoaded && _sceneNote == null) {
        setState(() => _sceneNote =
        'The 3D view is taking too long. Check your internet connection.');
      }
    });
  }

  // Messages sent FROM the web page TO Flutter.
  void _onSceneMessage(JavaScriptMessage message) {
    final msg = message.message;
    if (msg == 'ready') {
      // The 3D engine started, now we can send it the models.
      _populateScene();
    } else if (msg == 'loaded') {
      if (mounted) setState(() => _sceneLoaded = true);
    } else if (msg.startsWith('error:')) {
      debugPrint('3D scene: $msg');
      if (mounted && _sceneNote == null) {
        setState(() => _sceneNote = 'Some 3D parts could not load.');
      }
    }
  }

  // Reads the model link no matter which field name the product map used.
  String? _readModelUrl(Map<String, dynamic> product) {
    final dynamic raw = product['model'] ?? product['modelUrl'] ?? product['model_url'];
    if (raw is! String) return null;
    final url = raw.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return null;
  }

  // One entry per flower that will be drawn (qty is expanded, capped at _maxFlowers).
  // A null entry means that product has no usable model link.
  List<String?> _expandFlowerUrls() {
    final out = <String?>[];
    for (final product in widget.selectedProducts) {
      final int count =
      (product['qty'] is num) ? (product['qty'] as num).toInt() : 1;
      final String? url = _readModelUrl(product);
      for (int i = 0; i < count; i++) {
        if (out.length >= _maxFlowers) return out;
        out.add(url);
      }
    }
    return out;
  }

  // '#RRGGBB' text that the web page understands.
  String _cssHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // Sends the wrapper and every flower into the 3D scene.
  Future<void> _populateScene() async {
    if (_populating) return;
    _populating = true;
    final notes = <String>[];

    try {
      // 1. The wrapper comes from the app's own assets.
      try {
        final data = await rootBundle.load(_wrapperAsset);
        final b64 = base64Encode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        await _web.runJavaScript(
            'bloomSetWrapper(${jsonEncode(b64)}, ${jsonEncode(_cssHex(widget.wrapColor))});');
      } catch (e) {
        notes.add('Wrapper model not found ($_wrapperAsset).');
      }

      // 2. Count how many copies of each flower model we need.
      final Map<String, int> countsByUrl = {};
      int missing = 0;
      for (final url in _expandFlowerUrls()) {
        if (url == null) {
          missing++;
        } else {
          countsByUrl[url] = (countsByUrl[url] ?? 0) + 1;
        }
      }

      // 3. Download each DIFFERENT model once, then hand it to the scene.
      // Flutter downloads it (not the web page) so server CORS rules can't block it.
      for (final entry in countsByUrl.entries) {
        if (!mounted) return;
        try {
          final res =
          await http.get(Uri.parse(entry.key)).timeout(_downloadTimeout);
          if (res.statusCode != 200) {
            throw Exception('HTTP ${res.statusCode}');
          }
          await _web.runJavaScript(
              'bloomAddFlower(${jsonEncode(base64Encode(res.bodyBytes))}, ${entry.value});');
        } catch (e) {
          debugPrint('Flower model failed (${entry.key}): $e');
          missing += entry.value;
        }
      }

      if (missing > 0) notes.add('$missing flower(s) have no 3D model yet.');

      // 4. Tell the scene we are done; it replies 'loaded' when parsing finishes.
      if (!mounted) return;
      await _web.runJavaScript('bloomDone();');
    } catch (e) {
      debugPrint('Could not fill the 3D scene: $e');
      notes.add('Could not build the 3D bouquet.');
    }

    if (mounted && notes.isNotEmpty) {
      setState(() => _sceneNote = notes.join(' '));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // LAYER 1: camera (or a loader / message while it is not ready)
          if (_isInitialized && _controller != null)
            SizedBox.expand(child: CameraPreview(_controller!))
          else if (_cameraError != null)
            Center(
              child: Text(
                _cameraError!,
                style: const TextStyle(color: Colors.white54),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // LAYER 2: the 3D scene (wrapper + flowers in ONE world).
          // Drag sideways on it to spin the bouquet.
          Positioned.fill(child: WebViewWidget(controller: _web)),

          // LAYER 3: close button (after the web view so it stays tappable)
          Positioned(
            top: 60,
            left: 24,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // LAYER 4: status text
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Column(
                children: [
                  Text(
                    'AR TRACKING ACTIVE',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 3,
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: _sceneLoaded ? Colors.green : Colors.amber,
                            shape: BoxShape.circle),
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .tint(color: Colors.greenAccent, duration: 1000.ms),
                      const SizedBox(width: 10),
                      Text(
                        _sceneLoaded
                            ? '3D Bouquet Placed'
                            : 'Building your bouquet...',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w300),
                      ),
                    ],
                  ),
                  if (_sceneNote != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _sceneNote!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // The 3D scene (three.js). Flutter talks to it through the bloom* functions
  // at the bottom, and it talks back with BloomChannel.postMessage(...).
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

// ---- Tweak the look here -------------------------------------------------
const CONFIG = {
  wrapperHeight: 2.2,    // wrapper height in scene units
  wrapperTiltXDeg: 0,    // use 90, -90 or 180 if wrapper.glb loads lying down / upside down
  tintWrapper: true,     // false = keep the wrapper's own colours and texture
  flowerHeight: 1.6,     // every flower is scaled to this height
  flowerBaseY: 0.9,      // how deep the stems sit inside the wrapper (0 = at the tip)
  spread: 0.30,          // how far flowers sit from the centre (0..1 of the mouth radius)
  fanTilt: 0.28,         // radians the outer flowers lean outward
  autoSpin: 0.006        // spin speed (radians per frame)
};
// --------------------------------------------------------------------------

function post(msg) {
  if (window.BloomChannel) window.BloomChannel.postMessage(msg);
}

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setClearColor(0x000000, 0);              // transparent: the camera shows through
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;  // soft studio light
const sun = new THREE.DirectionalLight(0xffffff, 1.2);
sun.position.set(3, 6, 4);
scene.add(sun);

const camera = new THREE.PerspectiveCamera(35, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.set(0, 2.2, 8.5);
camera.lookAt(0, 1.4, 0);

// "spin" holds everything, so the wrapper and the flowers rotate TOGETHER.
const spin = new THREE.Group();
const wrapperGroup = new THREE.Group();
const flowerGroup = new THREE.Group();
spin.add(wrapperGroup);
spin.add(flowerGroup);
scene.add(spin);

const loader = new GLTFLoader();
const flowers = [];       // one pivot group per flower
let mouthRadius = 1.0;    // updated when the wrapper loads
const pending = [];       // every loading job, so bloomDone() can wait for them

function b64ToBuffer(b64) {
  return fetch('data:application/octet-stream;base64,' + b64).then(r => r.arrayBuffer());
}
function parseGlb(buffer) {
  return new Promise((resolve, reject) => loader.parse(buffer, '', resolve, reject));
}
function track(promise) {
  pending.push(promise.catch(err => post('error:' + ((err && err.message) || err))));
}

// Puts the flowers in a small fan inside the wrapper's mouth.
function layoutFlowers() {
  const n = flowers.length;
  if (n === 0) return;
  const hasCenter = n >= 5;                       // 5+ flowers: one in the middle, the rest around it
  const ringCount = hasCenter ? n - 1 : n;
  const radius = mouthRadius * CONFIG.spread;
  let ringIndex = 0;

  flowers.forEach((pivot, i) => {
    if (n === 1 || (hasCenter && i === 0)) {
      pivot.position.set(0, CONFIG.flowerBaseY, 0);
      pivot.quaternion.identity();
      return;
    }
    const angle = (ringIndex / ringCount) * Math.PI * 2;
    ringIndex++;
    pivot.position.set(Math.cos(angle) * radius, CONFIG.flowerBaseY, Math.sin(angle) * radius);
    // Lean the flower outward, pivoting around its base.
    const axis = new THREE.Vector3(Math.sin(angle), 0, -Math.cos(angle));
    pivot.quaternion.setFromAxisAngle(axis, CONFIG.fanTilt);
  });
}

async function setWrapper(b64, colorHex) {
  const gltf = await parseGlb(await b64ToBuffer(b64));
  const model = gltf.scene;
  model.rotation.x = THREE.MathUtils.degToRad(CONFIG.wrapperTiltXDeg);

  model.traverse(obj => {
    if (!obj.isMesh) return;
    const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
    mats.forEach(m => {
      m.side = THREE.DoubleSide;                  // show the inside AND the outside of the paper
      if (CONFIG.tintWrapper && colorHex && m.color) m.color.set(colorHex);
    });
  });

  // Scale to a fixed height, centre it, and stand its tip on y = 0.
  let box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  model.scale.setScalar(CONFIG.wrapperHeight / (size.y || 1));
  box = new THREE.Box3().setFromObject(model);
  const centre = box.getCenter(new THREE.Vector3());
  model.position.set(-centre.x, -box.min.y, -centre.z);

  const finalSize = box.getSize(new THREE.Vector3());
  mouthRadius = Math.max(finalSize.x, finalSize.z) / 2;

  wrapperGroup.add(model);
  layoutFlowers();
}

async function addFlower(b64, count) {
  const gltf = await parseGlb(await b64ToBuffer(b64));
  const model = gltf.scene;

  // Scale to a fixed height and put the bottom-centre at the origin.
  let box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  model.scale.setScalar(CONFIG.flowerHeight / (size.y || 1));
  box = new THREE.Box3().setFromObject(model);
  const centre = box.getCenter(new THREE.Vector3());
  model.position.set(-centre.x, -box.min.y, -centre.z);

  for (let i = 0; i < count; i++) {
    const pivot = new THREE.Group();
    pivot.add(i === 0 ? model : SkeletonUtils.clone(model));
    flowers.push(pivot);
    flowerGroup.add(pivot);
  }
  layoutFlowers();
}

// ---- Functions Flutter calls ----------------------------------------------
window.bloomSetWrapper = (b64, colorHex) => { track(setWrapper(b64, colorHex)); };
window.bloomAddFlower = (b64, count) => { track(addFlower(b64, count)); };
window.bloomDone = async () => {
  await Promise.all(pending);
  post('loaded');
};

// ---- Drag to spin, auto-spin otherwise ------------------------------------
let dragging = false;
let lastX = 0;
renderer.domElement.addEventListener('pointerdown', e => { dragging = true; lastX = e.clientX; });
window.addEventListener('pointerup', () => { dragging = false; });
window.addEventListener('pointermove', e => {
  if (!dragging) return;
  spin.rotation.y += (e.clientX - lastX) * 0.01;
  lastX = e.clientX;
});

window.addEventListener('resize', () => {
  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
});

renderer.setAnimationLoop(() => {
  if (!dragging) spin.rotation.y += CONFIG.autoSpin;
  renderer.render(scene, camera);
});

post('ready');   // tells Flutter: "send me the models now"
</script>
</body>
</html>
''';
}