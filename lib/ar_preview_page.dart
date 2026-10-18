import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ARPreviewPage extends StatefulWidget {
  // We now pass the full list of products
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

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.high);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _isInitialized = true);
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
          if (_isInitialized)
            SizedBox.expand(child: CameraPreview(_controller!))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          Positioned(
            top: 60,
            left: 24,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          Center(
            child: Container(
              width: 350,
              height: 600,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: 80,
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
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(120)),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                      ),
                    ).animate().fadeIn().scale(delay: 200.ms),
                  ),
                  ..._build3DFlowers(),
                ],
              ),
            ),
          ),

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
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ).animate(onPlay: (c) => c.repeat()).tint(color: Colors.greenAccent, duration: 1000.ms),
                    const SizedBox(width: 10),
                    const Text(
                      '3D Bouquet Placed',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w300),
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
    List<Widget> flowerWidgets = [];
    int globalIndex = 0;

    widget.selectedProducts.forEach((product) {
      final int count = product['qty'] ?? 1;
      final String? modelUrl = product['model'];
      final String name = product['name'] ?? 'Flower';

      for (int i = 0; i < count; i++) {
        double xOffset = (globalIndex % 3 - 1) * 70.0 + (i * 10);
        double yOffset = (globalIndex / 3).floor() * -40.0 - 220;

        flowerWidgets.add(
          Positioned(
            bottom: 250,
            left: 175 + xOffset - 60,
            child: Container(
              width: 150,
              height: 300,
              child: (modelUrl != null && modelUrl.isNotEmpty)
                  ? ModelViewer(
                // THE GUARANTEE: We pass the exact URL from Firestore
                src: modelUrl,
                alt: name,
                autoRotate: true,
                cameraControls: false,
                backgroundColor: Colors.transparent,
                disableZoom: true,
                autoPlay: true,
              )
                  : Container(
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
              ),
            ),
          ).animate().fadeIn(delay: (globalIndex * 150).ms).scale(),
        );
        globalIndex++;
      }
    });

    return flowerWidgets;
  }
}