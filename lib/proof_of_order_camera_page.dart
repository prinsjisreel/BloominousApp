import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// The result handed back to the POS page after a successful capture.
/// `bytes` is the FINAL JPEG with the date/time already burned into it.
class ProofOfOrderPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;

  const ProofOfOrderPhoto({required this.bytes, required this.capturedAt});
}

// Same format is used for the live on-screen clock and the burned-in stamp,
// so what the cashier sees is exactly what ends up on the photo.
final DateFormat _stampDateTime = DateFormat('MMM dd, yyyy  hh:mm:ss a');
final DateFormat _clockTime = DateFormat('hh:mm:ss a');
final DateFormat _clockDate = DateFormat('EEEE, MMM dd, yyyy');

/// Runs in a background isolate (via compute) so the UI doesn't freeze
/// while a large photo is decoded, stamped, and re-encoded.
///
/// MUST be a top-level function — compute() cannot run class methods.
Uint8List _stampProofPhoto(Map<String, Object> args) {
  final Uint8List rawBytes = args['bytes'] as Uint8List;
  final List<String> lines = List<String>.from(args['lines'] as List);

  img.Image? photo = img.decodeImage(rawBytes);
  if (photo == null) {
    throw Exception('Could not read the captured photo.');
  }

  // Phones often save photos sideways + an "orientation" tag. This rotates
  // the real pixels so the stamp lands at the true bottom of the picture.
  photo = img.bakeOrientation(photo);

  // Shrink very large photos: smaller upload, and the bitmap font stays
  // readable relative to the image size.
  if (photo.width > 1280) {
    photo = img.copyResize(photo, width: 1280);
  }

  const int padding = 16;
  const int lineHeight = 56; // arial48 glyphs + a little spacing
  final int boxHeight = (lines.length * lineHeight) + (padding * 2);
  final int boxTop = photo.height - boxHeight;

  // Semi-transparent black strip so white text is readable on any background.
  img.fillRect(
    photo,
    x1: 0,
    y1: boxTop,
    x2: photo.width,
    y2: photo.height,
    color: img.ColorRgba8(0, 0, 0, 170),
  );

  for (int i = 0; i < lines.length; i++) {
    img.drawString(
      photo,
      lines[i],
      font: img.arial48,
      x: padding,
      y: boxTop + padding + (i * lineHeight),
      color: i == 0
          ? img.ColorRgb8(244, 180, 0) // first line (date/time) in brand gold
          : img.ColorRgb8(255, 255, 255),
    );
  }

  return Uint8List.fromList(img.encodeJpg(photo, quality: 85));
}

/// Camera-ONLY proof-of-order screen. There is intentionally no gallery
/// option: every proof photo must be taken live, at the counter.
///
/// Returns a [ProofOfOrderPhoto] through Navigator.pop when the cashier
/// taps "USE PHOTO", or null if they close the screen.
class ProofOfOrderCameraPage extends StatefulWidget {
  final String orderId;
  final String staffLabel;

  const ProofOfOrderCameraPage({
    super.key,
    required this.orderId,
    required this.staffLabel,
  });

  @override
  State<ProofOfOrderCameraPage> createState() => _ProofOfOrderCameraPageState();
}

class _ProofOfOrderCameraPageState extends State<ProofOfOrderCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitializing = false;
  bool _isCapturing = false;
  String? _errorMessage;

  // Live clock shown on the viewfinder, refreshed every second.
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  // Holds the stamped photo while the cashier reviews it.
  ProofOfOrderPhoto? _captured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Releases the camera when the app goes to the background, and
  /// re-opens it when the cashier comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;

    if (state == AppLifecycleState.inactive) {
      // Only release a camera that actually finished opening. During the
      // first permission prompt the controller is still null, so nothing
      // is disposed by mistake.
      if (controller == null || !controller.value.isInitialized) return;
      _controller = null;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _captured == null) _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _errorMessage = 'No camera was found on this device.');
        }
        return;
      }

      // Prefer the rear camera (pointing at the bouquet / customer).
      final rearCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = (e.code == 'CameraAccessDenied' ||
              e.code == 'CameraAccessDeniedWithoutPrompt')
              ? 'Camera permission is required to record proof of order. '
              'Please allow camera access in your phone settings.'
              : 'Could not open the camera (${e.code}).';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Could not open the camera: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      // Record the time at the moment the shutter is pressed, not after
      // the (slower) image processing finishes.
      final capturedAt = DateTime.now();
      final XFile shot = await controller.takePicture();
      final Uint8List rawBytes = await shot.readAsBytes();

      final Uint8List stampedBytes = await compute(_stampProofPhoto, <String, Object>{
        'bytes': rawBytes,
        'lines': <String>[
          _stampDateTime.format(capturedAt),
          'ORDER ${widget.orderId}',
          'BY ${widget.staffLabel}',
        ],
      });

      if (!mounted) return;
      setState(() {
        _captured = ProofOfOrderPhoto(bytes: stampedBytes, capturedAt: capturedAt);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retake() => setState(() => _captured = null);

  void _usePhoto() => Navigator.pop(context, _captured);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _captured != null ? _buildReview(_captured!) : _buildCamera(),
      ),
    );
  }

  // ─────────────────────── Live camera view ───────────────────────

  Widget _buildCamera() {
    if (_errorMessage != null) {
      return _buildMessage(Icons.no_photography_outlined, _errorMessage!);
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFF4B400)));
    }

    return Stack(
      children: [
        Positioned.fill(child: Center(child: CameraPreview(controller))),

        // Top bar: close + title + "camera only" badge.
        Positioned(
          top: 8,
          left: 8,
          right: 16,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                tooltip: 'Cancel sale',
                onPressed: () => Navigator.pop(context, null),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'PROOF OF ORDER',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'CAMERA ONLY',
                  style: TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // Bottom panel: live date/time + shutter button.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            color: Colors.black.withOpacity(0.55),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _clockTime.format(_now),
                  style: const TextStyle(
                    color: Color(0xFFF4B400),
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _clockDate.format(_now),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Order ${widget.orderId}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _isCapturing ? null : _capture,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isCapturing ? Colors.grey : Colors.white,
                      ),
                      child: _isCapturing
                          ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.black),
                      )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────── Review captured photo ───────────────────────

  Widget _buildReview(ProofOfOrderPhoto photo) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'REVIEW PROOF PHOTO',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
        ),
        Expanded(
          child: Center(child: Image.memory(photo.bytes, fit: BoxFit.contain)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Taken ${_stampDateTime.format(photo.capturedAt)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETAKE'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _usePhoto,
                  icon: const Icon(Icons.check),
                  label: const Text('USE PHOTO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('CLOSE', style: TextStyle(color: Color(0xFFF4B400))),
            ),
          ],
        ),
      ),
    );
  }
}