import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  // Every 3D flower is a WebView. Too many at once will freeze a phone,
  // so we never draw more than this many in one preview.
  static const int _maxFlowers = 6;

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      // A camera problem should never stop the wrapper and flowers from showing.
      if (mounted) setState(() => _cameraError = 'Camera unavailable');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Reads the model link no matter which field name the product map used.
  String? _readModelUrl(Map<String, dynamic> product) {
    final dynamic raw = product['model'] ?? product['modelUrl'] ?? product['model_url'];
    if (raw is! String) return null;
    final url = raw.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return null;
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

          // LAYER 2: close button
          Positioned(
            top: 60,
            left: 24,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // LAYER 3: the wrapper + the flowers
          Center(
            child: SizedBox(
              width: 350,
              height: 600,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 3A. The 2D wrapper. It does not depend on any model,
                  // so it always stays on screen.
                  Positioned(
                    bottom: 80,
                    left: (350 - 240) / 2,
                    child: Container(
                      width: 240,
                      height: 320,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.wrapColor.withOpacity(0.4),
                            widget.wrapColor.withOpacity(0.7),
                          ],
                        ),
                        borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(120)),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1),
                      ),
                    ).animate().fadeIn().scale(delay: 200.ms),
                  ),

                  // 3B. The flowers (each one is a Positioned directly in this Stack)
                  ..._build3DFlowers(),
                ],
              ),
            ),
          ),

          // LAYER 4: status text
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
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
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .tint(color: Colors.greenAccent, duration: 1000.ms),
                    const SizedBox(width: 10),
                    const Text(
                      '3D Bouquet Placed',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _build3DFlowers() {
    final List<Widget> flowerWidgets = [];
    int globalIndex = 0;

    for (final product in widget.selectedProducts) {
      final int count = (product['qty'] is num) ? (product['qty'] as num).toInt() : 1;
      final String? modelUrl = _readModelUrl(product);
      final String name = (product['name'] ?? 'Flower').toString();

      for (int i = 0; i < count; i++) {
        if (globalIndex >= _maxFlowers) return flowerWidgets;

        final double xOffset = (globalIndex % 3 - 1) * 70.0 + (i * 10);

        flowerWidgets.add(
          // Positioned must be the DIRECT child of the Stack.
          Positioned(
            bottom: 250,
            left: 175 + xOffset - 75,
            child: SizedBox(
              width: 150,
              height: 300,
              child: modelUrl != null
              // The WebView is NOT animated on purpose (see changelog).
                  ? ModelViewer(
                // Key: if the URL changes, Flutter builds a fresh viewer.
                key: ValueKey('$modelUrl#$globalIndex'),
                src: modelUrl,
                alt: name,
                autoRotate: true,
                cameraControls: false,
                backgroundColor: Colors.transparent,
                disableZoom: true,
                autoPlay: true,
              )
                  : _buildNoModelCard(globalIndex),
            ),
          ),
        );
        globalIndex++;
      }
    }

    return flowerWidgets;
  }

  // Shown when a product has no usable model link.
  Widget _buildNoModelCard(int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: const Center(
        child: Text(
          'No 3D Model\nYet',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    ).animate().fadeIn(delay: (index * 150).ms).scale();
  }
}