import 'dart:convert';
import 'package:flutter/material.dart';

/// Shared "Proof of Order" photo helpers, used by the Orders page and the
/// Invoice detail page so both open the photo the same way.
///
/// The photo is taken at the POS (pos_scanner_page.dart) and saved on the
/// order as `proofPhotoUrl` (the web also reads the older `proofOfOrderPhoto`).

/// Returns the proof photo URL stored on an order, or null if it has none.
String? proofOfOrderUrl(Map<String, dynamic> order) {
  final raw = order['proofPhotoUrl'] ?? order['proofOfOrderPhoto'];
  final url = raw?.toString().trim() ?? '';
  return url.isEmpty ? null : url;
}

/// Draws a network (or base64 "data:") image, with a loading spinner and a
/// broken-image fallback so a bad link can never crash the screen.
Widget proofImage(String url, {BoxFit fit = BoxFit.cover}) {
  if (url.startsWith('data:') || url.contains(';base64,')) {
    try {
      return Image.memory(base64Decode(url.split(',').last), fit: fit);
    } catch (_) {
      return const Center(child: Icon(Icons.broken_image));
    }
  }
  return Image.network(
    url,
    fit: fit,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B), strokeWidth: 2)),
    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
  );
}

/// Full-screen, pinch-to-zoom viewer for the proof photo.
Future<void> showProofOfOrderViewer(BuildContext context, {required String url, String? caption}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(child: proofImage(url, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}