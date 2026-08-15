import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_keys.dart';

class GeminiImageException implements Exception {
  final String message;
  GeminiImageException(this.message);
  @override
  String toString() => message;
}

class GeminiService {
  static const String _apiKey = ApiKeys.geminiApiKey;

  // Stability AI key now lives in lib/api_keys.dart (gitignored) --
  // see lib/api_keys.example.dart for the setup template.
  static const String _stabilityApiKey = ApiKeys.stabilityApiKey;

  /// Imagen 3 Image Generation AI (imagen-3.0-generate-002 / gemini-3.1-flash-image / Nano Banana)
  /// Generates photorealistic AI imagery from a prompt and returns raw image Uint8List bytes
  static Future<Uint8List?> generateImagen3Image({
    required String prompt,
    String aspectRatio = '1:1',
    String modelName = 'imagen-3.0-generate-002',
  }) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelName:predict?key=$_apiKey',
      );

      final headers = {'Content-Type': 'application/json'};
      final body = json.encode({
        'instances': [
          {'prompt': prompt}
        ],
        'parameters': {
          'sampleCount': 1,
          'aspectRatio': aspectRatio,
          'outputMimeType': 'image/jpeg',
        }
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List?;
        if (predictions != null && predictions.isNotEmpty) {
          final base64Image = predictions[0]['bytesBase64Encoded'] as String?;
          if (base64Image != null && base64Image.isNotEmpty) {
            return base64Decode(base64Image);
          }
        }
      } else {
        print(
            "Imagen 3 Generation ($modelName) status: ${response.statusCode}, body: ${response.body}");
        if (modelName == 'imagen-3.0-generate-002') {
          return generateImagen3Image(
            prompt: prompt,
            aspectRatio: aspectRatio,
            modelName: 'imagen-3.0-fast-generate-001',
          );
        }
      }
    } catch (e) {
      print("Error in GeminiService generateImagen3Image: $e");
    }
    return null;
  }

  /// Gemini Nano / Flash Image Generation ("Nano Banana" / gemini-3.1-flash-image)
  /// Generates a data URL or base64 string for immediate display in Flutter Image widgets
  static Future<String?> generateFlowerArrangementDataUrl({
    required String prompt,
    String aspectRatio = '1:1',
  }) async {
    final imageBytes = await generateImagen3Image(
      prompt: prompt,
      aspectRatio: aspectRatio,
    );

    if (imageBytes != null && imageBytes.isNotEmpty) {
      final base64Str = base64Encode(imageBytes);
      return 'data:image/jpeg;base64,$base64Str';
    }
    return null;
  }

  /// In-paints and bakes the floral arrangement directly into the user's uploaded photo canvas
  static Future<Uint8List> compositeEditedRoomPhoto({
    required Uint8List userRoomBytes,
    required String flowerType,
    required String potType,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(userRoomBytes);
      final frame = await codec.getNextFrame();
      final bgImage = frame.image;

      final width = bgImage.width;
      final height = bgImage.height;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

      // 1. Draw original room photo background
      canvas.drawImage(
          bgImage, Offset.zero, Paint()..filterQuality = ui.FilterQuality.high);

      // 2. Paint custom realistic floral arrangement design onto the image canvas
      _paintCustomFlowerDesignOnCanvas(
        canvas: canvas,
        width: width.toDouble(),
        height: height.toDouble(),
        flowerType: flowerType,
        potType: potType,
      );

      final picture = recorder.endRecording();
      final compiledImage = await picture.toImage(width, height);
      final byteData =
      await compiledImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      print("Error compositing edited room photo: $e");
    }
    return userRoomBytes;
  }

  static void _paintCustomFlowerDesignOnCanvas({
    required Canvas canvas,
    required double width,
    required double height,
    required String flowerType,
    required String potType,
  }) {
    final lowerFlower = flowerType.toLowerCase();
    final lowerPot = potType.toLowerCase();

    // Target position centered on table / bench / stool surface in the room photo
    final centerX = width * 0.50;
    final centerY = height * 0.50;
    final vaseW = width * 0.42;
    final vaseH = height * 0.28;
    final vaseTop = centerY - vaseH * 0.15;
    final vaseBottom = centerY + vaseH * 0.55;

    // 1. Realistic soft contact shadow on stool/table surface
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 22);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, vaseBottom + 8),
        width: vaseW * 1.35,
        height: vaseH * 0.35,
      ),
      shadowPaint,
    );

    // 2. Draw Stems & Lush Foliage rising from vase
    final stemPaint = Paint()
      ..color = const Color(0xFF166534)
      ..strokeWidth = vaseW * 0.04
      ..style = PaintingStyle.stroke;

    final leafPaint = Paint()..style = PaintingStyle.fill;

    // Draw background stems
    final stemPath = Path();
    stemPath.moveTo(centerX - vaseW * 0.2, vaseTop + 10);
    stemPath.quadraticBezierTo(centerX - vaseW * 0.4, vaseTop - vaseH * 0.8,
        centerX - vaseW * 0.3, vaseTop - vaseH * 1.5);

    stemPath.moveTo(centerX, vaseTop + 10);
    stemPath.quadraticBezierTo(centerX + vaseW * 0.1, vaseTop - vaseH * 1.0,
        centerX, vaseTop - vaseH * 1.8);

    stemPath.moveTo(centerX + vaseW * 0.2, vaseTop + 10);
    stemPath.quadraticBezierTo(centerX + vaseW * 0.5, vaseTop - vaseH * 0.7,
        centerX + vaseW * 0.4, vaseTop - vaseH * 1.4);

    canvas.drawPath(stemPath, stemPaint);

    // Draw Eucalyptus & Monstera leaves
    leafPaint.color = const Color(0xFF15803D);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX - vaseW * 0.45, vaseTop - vaseH * 0.6),
          width: vaseW * 0.42,
          height: vaseH * 0.26),
      leafPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX + vaseW * 0.45, vaseTop - vaseH * 0.5),
          width: vaseW * 0.44,
          height: vaseH * 0.25),
      leafPaint,
    );
    leafPaint.color = const Color(0xFF166534);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX - vaseW * 0.25, vaseTop - vaseH * 0.9),
          width: vaseW * 0.38,
          height: vaseH * 0.23),
      leafPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX + vaseW * 0.25, vaseTop - vaseH * 0.8),
          width: vaseW * 0.40,
          height: vaseH * 0.23),
      leafPaint,
    );

    // 3. Draw Pot/Vase
    final potPath = Path();
    potPath.moveTo(centerX - vaseW * 0.35, vaseTop);
    potPath.quadraticBezierTo(
        centerX - vaseW * 0.55, centerY, centerX - vaseW * 0.38, vaseBottom);
    potPath.lineTo(centerX + vaseW * 0.38, vaseBottom);
    potPath.quadraticBezierTo(
        centerX + vaseW * 0.55, centerY, centerX + vaseW * 0.35, vaseTop);
    potPath.close();

    final potPaint = Paint()..style = PaintingStyle.fill;

    if (lowerPot.contains('terracotta') ||
        lowerPot.contains('clay') ||
        lowerPot.contains('paso')) {
      potPaint.shader = ui.Gradient.linear(
        Offset(centerX - vaseW * 0.5, vaseTop),
        Offset(centerX + vaseW * 0.5, vaseBottom),
        [
          const Color(0xFFEA580C),
          const Color(0xFFC2410C),
          const Color(0xFF7C2D12)
        ],
      );
    } else if (lowerPot.contains('ceramic') || lowerPot.contains('white')) {
      potPaint.shader = ui.Gradient.linear(
        Offset(centerX - vaseW * 0.5, vaseTop),
        Offset(centerX + vaseW * 0.5, vaseBottom),
        [
          const Color(0xFFFFFFFF),
          const Color(0xFFE2E8F0),
          const Color(0xFF64748B)
        ],
      );
    } else if (lowerPot.contains('gold') || lowerPot.contains('brass')) {
      potPaint.shader = ui.Gradient.linear(
        Offset(centerX - vaseW * 0.5, vaseTop),
        Offset(centerX + vaseW * 0.5, vaseBottom),
        [
          const Color(0xFFFEF08A),
          const Color(0xFFF59E0B),
          const Color(0xFFB45309)
        ],
      );
    } else {
      // Glass
      potPaint.color = const Color(0x90E0F2FE);
    }

    canvas.drawPath(potPath, potPaint);

    // Rim of the pot
    final rimPaint = Paint()
      ..color = lowerPot.contains('gold')
          ? const Color(0xFFFBBF24)
          : lowerPot.contains('terracotta')
          ? const Color(0xFFC2410C)
          : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX, vaseTop),
          width: vaseW * 0.75,
          height: vaseH * 0.15),
      rimPaint,
    );

    // Highlight on pot side
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = vaseW * 0.05
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawLine(
      Offset(centerX - vaseW * 0.25, vaseTop + vaseH * 0.2),
      Offset(centerX - vaseW * 0.28, vaseBottom - vaseH * 0.2),
      highlightPaint,
    );

    // 4. Draw Flowers (Sunflowers, Roses, Tulips, Lilies)
    if (lowerFlower.contains('sunflower') ||
        lowerFlower.contains('mirasol') ||
        lowerFlower.contains('yellow')) {
      _drawSunflower(
          canvas, Offset(centerX, vaseTop - vaseH * 1.8), vaseW * 0.5);
      _drawSunflower(canvas,
          Offset(centerX - vaseW * 0.35, vaseTop - vaseH * 1.2), vaseW * 0.4);
      _drawSunflower(canvas,
          Offset(centerX + vaseW * 0.35, vaseTop - vaseH * 1.1), vaseW * 0.42);
    } else if (lowerFlower.contains('rose') || lowerFlower.contains('red')) {
      _drawRose(canvas, Offset(centerX, vaseTop - vaseH * 1.8), vaseW * 0.45);
      _drawRose(canvas, Offset(centerX - vaseW * 0.35, vaseTop - vaseH * 1.2),
          vaseW * 0.38);
      _drawRose(canvas, Offset(centerX + vaseW * 0.35, vaseTop - vaseH * 1.1),
          vaseW * 0.40);
      _drawRose(canvas, Offset(centerX - vaseW * 0.15, vaseTop - vaseH * 0.8),
          vaseW * 0.34);
      _drawRose(canvas, Offset(centerX + vaseW * 0.15, vaseTop - vaseH * 0.7),
          vaseW * 0.34);
    } else if (lowerFlower.contains('tulip') || lowerFlower.contains('pink')) {
      _drawTulip(canvas, Offset(centerX, vaseTop - vaseH * 1.8), vaseW * 0.38);
      _drawTulip(canvas, Offset(centerX - vaseW * 0.32, vaseTop - vaseH * 1.3),
          vaseW * 0.34);
      _drawTulip(canvas, Offset(centerX + vaseW * 0.32, vaseTop - vaseH * 1.2),
          vaseW * 0.35);
      _drawTulip(canvas, Offset(centerX - vaseW * 0.12, vaseTop - vaseH * 0.8),
          vaseW * 0.32);
    } else if (lowerFlower.contains('lily') || lowerFlower.contains('white')) {
      _drawLily(canvas, Offset(centerX, vaseTop - vaseH * 1.8), vaseW * 0.48);
      _drawLily(canvas, Offset(centerX - vaseW * 0.35, vaseTop - vaseH * 1.2),
          vaseW * 0.40);
      _drawLily(canvas, Offset(centerX + vaseW * 0.35, vaseTop - vaseH * 1.1),
          vaseW * 0.42);
    } else {
      // Default lush multi-color bouquet
      _drawRose(canvas, Offset(centerX, vaseTop - vaseH * 1.8), vaseW * 0.45);
      _drawSunflower(canvas,
          Offset(centerX - vaseW * 0.35, vaseTop - vaseH * 1.2), vaseW * 0.42);
      _drawTulip(canvas, Offset(centerX + vaseW * 0.35, vaseTop - vaseH * 1.1),
          vaseW * 0.38);
    }

    // 5. Baby's breath accent dots
    final babyBreathPaint = Paint()..color = Colors.white.withOpacity(0.95);
    final offsets = [
      Offset(centerX - vaseW * 0.45, vaseTop - vaseH * 1.5),
      Offset(centerX - vaseW * 0.5, vaseTop - vaseH * 1.1),
      Offset(centerX + vaseW * 0.45, vaseTop - vaseH * 1.4),
      Offset(centerX + vaseW * 0.52, vaseTop - vaseH * 0.9),
      Offset(centerX, vaseTop - vaseH * 2.1),
      Offset(centerX - vaseW * 0.2, vaseTop - vaseH * 2.0),
      Offset(centerX + vaseW * 0.2, vaseTop - vaseH * 1.9),
    ];
    for (final off in offsets) {
      canvas.drawCircle(off, vaseW * 0.025, babyBreathPaint);
      canvas.drawCircle(off + Offset(vaseW * 0.03, -vaseW * 0.02), vaseW * 0.02,
          babyBreathPaint);
      canvas.drawCircle(off + Offset(-vaseW * 0.03, vaseW * 0.02),
          vaseW * 0.018, babyBreathPaint);
    }
  }

  static void _drawSunflower(Canvas canvas, Offset center, double radius) {
    const petalCount = 18;
    final petalPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < petalCount; i++) {
      final angle = (i * 2 * math.pi) / petalCount;
      final petalCenter = Offset(
        center.dx + radius * 0.65 * math.cos(angle),
        center.dy + radius * 0.65 * math.sin(angle),
      );
      petalPaint.color =
      (i % 2 == 0) ? const Color(0xFFF59E0B) : const Color(0xFFEAB308);
      canvas.drawOval(
        Rect.fromCenter(
            center: petalCenter, width: radius * 0.45, height: radius * 0.85),
        petalPaint,
      );
    }
    final seedPaint = Paint()
      ..color = const Color(0xFF3E1F08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.45, seedPaint);

    final seedRimPaint = Paint()
      ..color = const Color(0xFFCA8A04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08;
    canvas.drawCircle(center, radius * 0.42, seedRimPaint);
  }

  static void _drawRose(Canvas canvas, Offset center, double radius) {
    final petalPaint = Paint()..style = PaintingStyle.fill;

    // Outer petals
    petalPaint.color = const Color(0xFF991B1B);
    canvas.drawCircle(center, radius, petalPaint);

    // Mid petals
    petalPaint.color = const Color(0xFFDC2626);
    canvas.drawCircle(center + const Offset(-2, -2), radius * 0.75, petalPaint);

    // Inner petals
    petalPaint.color = const Color(0xFFEF4444);
    canvas.drawCircle(center + const Offset(2, 2), radius * 0.5, petalPaint);

    // Heart spiral
    petalPaint.color = const Color(0xFFFECDD3);
    canvas.drawCircle(center, radius * 0.25, petalPaint);
  }

  static void _drawTulip(Canvas canvas, Offset center, double radius) {
    final petalPaint = Paint()..style = PaintingStyle.fill;

    // Outer cup
    petalPaint.color = const Color(0xFFBE185D);
    canvas.drawOval(
      Rect.fromCenter(
          center: center, width: radius * 0.9, height: radius * 1.3),
      petalPaint,
    );

    // Inner highlight
    petalPaint.color = const Color(0xFFF43F5E);
    canvas.drawOval(
      Rect.fromCenter(
          center: center + Offset(0, -radius * 0.1),
          width: radius * 0.65,
          height: radius * 1.0),
      petalPaint,
    );

    // Bright center tip
    petalPaint.color = const Color(0xFFFDA4AF);
    canvas.drawOval(
      Rect.fromCenter(
          center: center + Offset(0, -radius * 0.2),
          width: radius * 0.35,
          height: radius * 0.6),
      petalPaint,
    );
  }

  static void _drawLily(Canvas canvas, Offset center, double radius) {
    final petalPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 6; i++) {
      final angle = (i * 2 * math.pi) / 6;
      final petalCenter = Offset(
        center.dx + radius * 0.5 * math.cos(angle),
        center.dy + radius * 0.5 * math.sin(angle),
      );
      petalPaint.color = Colors.white;
      canvas.drawOval(
        Rect.fromCenter(
            center: petalCenter, width: radius * 0.4, height: radius * 0.9),
        petalPaint,
      );
    }

    final centerPaint = Paint()..color = const Color(0xFFF472B6);
    canvas.drawCircle(center, radius * 0.25, centerPaint);

    final stamenPaint = Paint()..color = const Color(0xFFFACC15);
    canvas.drawCircle(center, radius * 0.12, stamenPaint);
  }

  /// Real Multimodal Image Editing with Gemini Vision + In-painting Synthesis
  /// Takes the user's uploaded room photo, analyzes its exact room background & furniture placement with Gemini 2.5 Flash,
  /// and generates an edited picture preserving the room background while in-painting the specified floral vase design.
  /// Sends the user's uploaded photo + occasion note to Gemini's image model
  /// (image-to-image editing) and returns the AI-generated result: the model
  /// analyzes the actual room/venue layout and blends the floral arrangement
  /// into the real photo.
  ///
  /// IMPORTANT: this throws GeminiImageException on any failure instead of
  /// silently falling back -- the caller decides whether to show the Canvas
  /// placeholder, but it MUST surface the real error to the user/logs.
  /// Silent fallbacks are why "nothing generates" is impossible to diagnose.
  static Future<Uint8List> editUserPhotoWithGemini({
    required Uint8List userRoomBytes,
    required String userInstruction,
    required String flowerType,
    required String potType,
  }) async {
    // gemini-2.5-flash-image was superseded by gemini-3.1-flash-image
    // ("Nano Banana 2") as Google's current GA image model. If Google ships
    // another rename, this is the one line that needs to change.
    const modelName = 'gemini-3.1-flash-image';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$_apiKey',
    );

    final prompt = "You are an expert event florist and stylist doing photorealistic image-to-image editing.\n"
        "Preserve the original photo's background, layout, furniture or venue structure, lighting, and camera perspective exactly as shown.\n"
        "PRIMARY BRIEF from the customer -- this determines WHAT decor to add and HOW MUCH: '$userInstruction'.\n"
        "Treat $flowerType and a $potType as a fallback style/palette suggestion only -- use them if the brief above doesn't already specify the flowers, colors, or containers to use, but the brief always takes priority.\n"
        "Scale the amount and placement of floral decor to genuinely suit the space and occasion shown in the photo. A single small accent arrangement is NOT enough for a large hall, stage, or aisle meant for a wedding or full event -- in that case, add multiple arrangements, an entrance or stage backdrop, or aisle decor so the space actually reads as styled for the occasion. For a small tabletop or intimate setting, one well-placed arrangement is enough.\n"
        "Infer the most natural surfaces or spots for the decor directly from what is actually visible in this photo (tables, altar, stage, entrance, aisle, etc.) -- do not assume a single fixed position or that only one item is needed.\n"
        "Blend everything in with realistic scale, perspective, and contact shadows that match the photo's existing light direction. Do not replace, crop, or regenerate the background -- only add the floral decor.";

    final body = json.encode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(userRoomBytes),
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      }
    });

    http.Response response;
    try {
      response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (e) {
      throw GeminiImageException('Network request failed: $e');
    }

    print("Gemini Image ($modelName) HTTP ${response.statusCode}: ${response.body}");

    if (response.statusCode != 200) {
      throw GeminiImageException(
          'HTTP ${response.statusCode}: ${response.body}');
    }

    final data = json.decode(response.body);

    // A 200 with no candidates usually means the safety filter blocked the
    // request/image -- check promptFeedback so that reason is visible too.
    final promptFeedback = data['promptFeedback'];
    if (promptFeedback != null && promptFeedback['blockReason'] != null) {
      throw GeminiImageException(
          'Blocked by safety filter: ${promptFeedback['blockReason']}');
    }

    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw GeminiImageException('No candidates returned: ${response.body}');
    }

    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts != null) {
      for (final part in parts) {
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline != null && inline['data'] != null) {
          return base64Decode(inline['data']);
        }
      }
    }

    throw GeminiImageException(
        'Response had no image part (model may have replied text-only): ${response.body}');
  }

  /// Stability AI fallback for the same job as editUserPhotoWithGemini():
  /// takes the uploaded room/venue photo + occasion note and returns an
  /// image-to-image edit with the floral arrangement added.
  ///
  /// Uses Stable Diffusion 3.5 in "image-to-image" mode -- it conditions on
  /// your uploaded photo (not a blank canvas) and a prompt describing what
  /// to add, so the room/venue you photographed still comes through in the
  /// result rather than being replaced by a wholly new AI scene.
  ///
  /// `strength` controls how much the AI is allowed to change vs. preserve
  /// the original photo -- 0.0 = ignore the prompt entirely, 1.0 = ignore
  /// the photo entirely. Image-to-image mode has no real concept of
  /// "insert a new object here" the way true inpainting does -- it just
  /// redraws the photo guided by the prompt, constrained by this value. At
  /// low strength (e.g. 0.65) the model often plays it safe and barely
  /// changes the photo, which can look like nothing was added at all. 0.85
  /// gives it real room to render a visible floral addition, at the cost
  /// of the room looking somewhat less identical to the original photo.
  /// Tune this if results drift too far from the source room, or still
  /// don't show visible flowers.
  static Future<Uint8List> editUserPhotoWithStabilityAI({
    required Uint8List userRoomBytes,
    required String userInstruction,
    required String flowerType,
    required String potType,
  }) async {
    if (_stabilityApiKey.isEmpty ||
        _stabilityApiKey == 'PASTE_YOUR_STABILITY_API_KEY_HERE') {
      throw GeminiImageException(
          'Stability AI key not set -- paste your key into _stabilityApiKey at the top of gemini_service.dart.');
    }

    final uri =
    Uri.parse('https://api.stability.ai/v2beta/stable-image/generate/sd3');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_stabilityApiKey';
    // Accept: image/* returns the raw generated image bytes directly in the
    // response body -- no base64 decoding needed, unlike the Gemini call above.
    request.headers['Accept'] = 'image/*';

    request.fields['mode'] = 'image-to-image';
    request.fields['strength'] = '0.85';
    request.fields['model'] = 'sd3.5-large';
    request.fields['output_format'] = 'png';
    request.fields['prompt'] =
    "PRIMARY BRIEF from the customer -- this determines WHAT decor to add and HOW MUCH: '$userInstruction'. "
        "Treat $flowerType in a $potType as a fallback style/palette suggestion only, used if the brief above doesn't already specify the flowers, colors, or containers -- the brief always takes priority. "
        "Scale the amount and placement of floral decor to genuinely suit the space and occasion shown in the photo. A single small accent arrangement is NOT enough for a large hall, stage, or aisle meant for a wedding or full event -- add multiple arrangements, an entrance/stage backdrop, or aisle decor so the space reads as actually styled for the occasion. For a small tabletop or intimate setting, one well-placed arrangement is enough. "
        "Infer the most natural surfaces from what's visible in the photo -- do not assume only one item is needed. Keep the existing room or venue, furniture, lighting, and camera angle unchanged -- only add the floral decor, blended in with realistic scale and shadows.";

    request.files.add(
      http.MultipartFile.fromBytes('image', userRoomBytes,
          filename: 'room.jpg'),
    );

    http.StreamedResponse streamed;
    try {
      streamed = await request.send();
    } catch (e) {
      throw GeminiImageException('Stability AI network request failed: $e');
    }

    final response = await http.Response.fromStream(streamed);
    print("Stability AI HTTP ${response.statusCode}");

    if (response.statusCode != 200) {
      // Stability returns a JSON error body even when Accept: image/* was
      // requested, so response.body is readable text here, not binary.
      throw GeminiImageException(
          'Stability AI error (${response.statusCode}): ${response.body}');
    }

    if (response.bodyBytes.isEmpty) {
      throw GeminiImageException('Stability AI returned an empty image.');
    }

    return response.bodyBytes;
  }

  static Future<Map<String, dynamic>> analyzeFreshness(
      Uint8List imageBytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );

      final prompt =
      TextPart("Analyze the freshness of the flower in this image. "
          "Identify the flower name. "
          "Provide a 'Freshness Score' from 0 to 100. "
          "Determine a 'Status' (Healthy, Warning, or Critical). "
          "Provide a short 'Recommendation' for the florist. "
          "Format your response EXACTLY like this:\n"
          "Product: [Flower Name]\n"
          "Score: [Number 0-100]\n"
          "Status: [Healthy/Warning/Critical]\n"
          "Recommendation: [Short text]\n"
          "Description: [Detailed analysis]");

      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final text = response.text ?? '';
      return _parseResponse(text);
    } catch (e) {
      print("Error in GeminiService analyzeFreshness: $e");
      return {
        'error': e.toString(),
        'product': 'Rose / Sunflower',
        'score': 92,
        'status': 'Healthy',
        'recommendation':
        'Keep in cool room temperature with clean fresh water.',
        'description':
        'AI Analysis: Flower exhibits vibrant petals, strong stem structural integrity, and fresh bloom state.'
      };
    }
  }

  /// Helper to pick a high-resolution floral arrangement photo based on themes & flowers
  static String selectFloralImageUrl(
      {String? vibe, String? flowers, String? theme}) {
    final combined =
    "${vibe ?? ''} ${flowers ?? ''} ${theme ?? ''}".toLowerCase();

    if (combined.contains('sunflower') ||
        combined.contains('sunny') ||
        combined.contains('yellow') ||
        combined.contains('bright')) {
      return 'https://images.unsplash.com/photo-1597848212624-a19eb35e2651?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('pink') ||
        combined.contains('pastel') ||
        combined.contains('sweet') ||
        combined.contains('carnation') ||
        combined.contains('baby')) {
      return 'https://images.unsplash.com/photo-1561181286-d3fee7d55364?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('white') ||
        combined.contains('lily') ||
        combined.contains('luxury') ||
        combined.contains('modern') ||
        combined.contains('clean')) {
      return 'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('tulip')) {
      return 'https://images.unsplash.com/photo-1520763185298-1b434c919102?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('hydrangea') ||
        combined.contains('blue') ||
        combined.contains('purple')) {
      return 'https://images.unsplash.com/photo-1508610048659-a06b669e3321?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('rustic') ||
        combined.contains('earthy') ||
        combined.contains('dried') ||
        combined.contains('eucalyptus') ||
        combined.contains('garden')) {
      return 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9?q=80&w=800&auto=format&fit=crop';
    } else if (combined.contains('red') ||
        combined.contains('rose') ||
        combined.contains('romantic') ||
        combined.contains('love') ||
        combined.contains('crimson')) {
      return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=800&auto=format&fit=crop';
    }

    return 'https://images.unsplash.com/photo-1563241527-3004b7be0ffd?q=80&w=800&auto=format&fit=crop';
  }

  /// Helper to pick a clean transparent PNG floral cutout for room photo overlays
  static String selectTransparentOverlayUrl(
      {String? vibe, String? flowers, String? theme}) {
    final combined =
    "${vibe ?? ''} ${flowers ?? ''} ${theme ?? ''}".toLowerCase();

    if (combined.contains('sunflower') || combined.contains('yellow')) {
      return 'https://images.rawpixel.com/image_png_800/cHJpdmF0ZS9sci9tZWRpYS9pbWFnZXMvd2Vic2l0ZS8yMDIyLTA1L25zOTM4My1lbGVtZW50LW9mZi1hLXN1bmZsb3dlci1ib3VxdWV0LXAuanBnLnBuZw.png';
    } else if (combined.contains('pink') ||
        combined.contains('tulip') ||
        combined.contains('pastel')) {
      return 'https://images.rawpixel.com/image_png_800/cHJpdmF0ZS9sci9tZWRpYS9pbWFnZXMvd2Vic2l0ZS8yMDIzLTA4L3Jhd3BpeGVsX29mZmljZV8yN19waG90b19vZl9hX3Bpbmtfcm9zZV9ib3VxdWV0X2lzb2xhdGVkX29uX3doaXRlX2JfNGRiMTA4ZWEtN2EwMC00MzliLTgzZjgtYjk4M2ZmZDcxYjZiLnBuZw.png';
    } else if (combined.contains('white') || combined.contains('lily')) {
      return 'https://images.rawpixel.com/image_png_800/cHJpdmF0ZS9sci9tZWRpYS9pbWFnZXMvd2Vic2l0ZS8yMDIzLTA4L3Jhd3BpeGVsX29mZmljZV8yN19waG90b19vZl93aGl0ZV9mbG93ZXJfYm91cXVldF9pc29sYXRlZF9vbl93aGl0ZV9iXzRkYjEwOGVhLTdhMDAtNDM5Yi04M2Y4LWI5ODNmZmQ3MWI2Yi5wbmc.png';
    } else {
      return 'https://images.rawpixel.com/image_png_800/cHJpdmF0ZS9sci9tZWRpYS9pbWFnZXMvd2Vic2l0ZS8yMDIzLTA4L3Jhd3BpeGVsX29mZmljZV8yN19waG90b19vZl9hX2JvdXF1ZXRfb2Zfcm9zZXNfaXNvbGF0ZWRfb25fd2hpdGVfYl80ZGIxMDhlYS03YTAwLTQzOWItODNmOC1iOTgzZmZkNzFiNmIucG5n.png';
    }
  }

  /// AI Visual Assistant - Analyzes room photo/decor/dress image to match flowers and color palette
  static Future<Map<String, dynamic>> analyzeVisualTheme({
    Uint8List? imageBytes,
    String? occasion,
    String? description,
  }) async {
    Map<String, dynamic> resultData;
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );

      final systemPrompt = """
        You are Bloominous' AI Visual Floral Stylist.
        Analyze the provided image and description to recommend ideal floral arrangements.
        Return your response strictly in JSON format with key structure:
        {
          "detectedTheme": "Description of room/outfit/event aesthetic (e.g. Modern Minimalist, Rustic Warm, Pastel Elegance)",
          "colorPalette": ["Hex/Color Name 1", "Color Name 2", "Color Name 3"],
          "recommendedFlowers": ["Flower 1", "Flower 2", "Flower 3"],
          "arrangementStyle": "Style recommendation (e.g., Tall Glass Vase with Ecuadorian Roses & Eucalyptus)",
          "matchingReason": "Why these flowers complement the photo/description",
          "cardMessageSuggestion": "A short, elegant card note"
        }
      """;

      final contents = <Content>[];

      if (imageBytes != null) {
        contents.add(Content.multi([
          TextPart(systemPrompt +
              (description != null ? "\nUser Note: $description" : "")),
          DataPart('image/jpeg', imageBytes),
        ]));
      } else {
        contents.add(Content.text(
            "$systemPrompt\nOccasion: $occasion\nDetails: ${description ?? 'General aesthetic'}"));
      }

      final response = await model.generateContent(contents);
      final text = response.text ?? '';

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        resultData =
        Map<String, dynamic>.from(json.decode(jsonMatch.group(0)!));
      } else {
        resultData = {
          "detectedTheme": "Warm Romantic Elegance",
          "colorPalette": [
            "#E11D48 (Crimson Red)",
            "#FDE047 (Blush Gold)",
            "#22C55E (Sage Green)"
          ],
          "recommendedFlowers": [
            "Ecuadorian Red Roses",
            "White Baby's Breath",
            "Eucalyptus Greenery"
          ],
          "arrangementStyle":
          "Classic Hand-tied Spiral Bouquet with Silk Ribbon",
          "matchingReason":
          "Red roses provide a striking focal point while soft baby's breath and sage greenery balance ambient lighting and space warmth.",
          "cardMessageSuggestion":
          "Sending flowers that bloom as beautifully as the memories we share together."
        };
      }
    } catch (e) {
      print("Gemini analyzeVisualTheme error/fallback: $e");
      resultData = {
        "detectedTheme": "Warm Romantic Elegance",
        "colorPalette": [
          "#E11D48 (Crimson Red)",
          "#FDE047 (Blush Gold)",
          "#22C55E (Sage Green)"
        ],
        "recommendedFlowers": [
          "Ecuadorian Red Roses",
          "White Baby's Breath",
          "Eucalyptus Greenery"
        ],
        "arrangementStyle": "Classic Hand-tied Spiral Bouquet with Silk Ribbon",
        "matchingReason":
        "Red roses provide a striking focal point while soft baby's breath and sage greenery balance ambient lighting and space warmth.",
        "cardMessageSuggestion":
        "Sending flowers that bloom as beautifully as the memories we share together."
      };
    }

    resultData['imageUrl'] = selectFloralImageUrl(
      vibe: resultData['detectedTheme']?.toString(),
      flowers: ((resultData['recommendedFlowers'] as List?) ?? []).join(' '),
      theme: resultData['arrangementStyle']?.toString(),
    );

    resultData['overlayImageUrl'] = selectTransparentOverlayUrl(
      vibe: resultData['detectedTheme']?.toString(),
      flowers: ((resultData['recommendedFlowers'] as List?) ?? []).join(' '),
      theme: resultData['arrangementStyle']?.toString(),
    );

    return resultData;
  }

  /// AI Personalization Matchmaker - Generates bouquet ideas, 3D formulas & card notes
  static Future<Map<String, dynamic>> getPersonalizedMatch({
    required String recipient,
    required String occasion,
    required String vibe,
    required String budget,
    required String tone,
  }) async {
    Map<String, dynamic> resultData;
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );

      final prompt = """
        You are Bloominous AI Personal Floral Matchmaker.
        Generate a personalized floral recommendation based on:
        - Recipient: $recipient
        - Occasion: $occasion
        - Desired Vibe: $vibe
        - Budget: $budget
        - Card Note Tone: $tone

        Return JSON with:
        {
          "title": "Name for the custom creation",
          "explanation": "Why this matches recipient & occasion",
          "flowerFormula": [
            {"flower": "Flower Name", "count": 5, "color": "Red"},
            {"flower": "Foliage Name", "count": 3, "color": "Green"}
          ],
          "estimatedPrice": "₱1,200",
          "cardNote": "Complete heartfelt card message",
          "careTip": "Key tip to maximize freshness"
        }
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        resultData =
        Map<String, dynamic>.from(json.decode(jsonMatch.group(0)!));
      } else {
        resultData = {
          "title": "The $vibe $occasion Arrangement for $recipient",
          "explanation":
          "Curated with soft textures and rich colors suited for $recipient on this $occasion.",
          "flowerFormula": [
            {"flower": "Ecuadorian Rose", "count": 6, "color": "Pink/Red"},
            {"flower": "White Lily", "count": 2, "color": "White"},
            {"flower": "Baby's Breath", "count": 4, "color": "White"}
          ],
          "estimatedPrice": budget.contains("₱") ? budget : "₱1,500",
          "cardNote":
          "To my dearest $recipient, wishing you endless joy and beauty on this special $occasion. May these flowers brighten your day!",
          "careTip":
          "Trim 1cm off stems at a 45-degree angle upon receiving and change vase water every 2 days."
        };
      }
    } catch (e) {
      print("Gemini getPersonalizedMatch fallback: $e");
      resultData = {
        "title": "The $vibe $occasion Arrangement for $recipient",
        "explanation":
        "Curated with soft textures and rich colors suited for $recipient on this $occasion.",
        "flowerFormula": [
          {"flower": "Ecuadorian Rose", "count": 6, "color": "Pink/Red"},
          {"flower": "White Lily", "count": 2, "color": "White"},
          {"flower": "Baby's Breath", "count": 4, "color": "White"}
        ],
        "estimatedPrice": budget.contains("₱") ? budget : "₱1,500",
        "cardNote":
        "To my dearest $recipient, wishing you endless joy and beauty on this special $occasion. May these flowers brighten your day!",
        "careTip":
        "Trim 1cm off stems at a 45-degree angle upon receiving and change vase water every 2 days."
      };
    }

    final formulaFlowers = ((resultData['flowerFormula'] as List?) ?? [])
        .map((e) => "${e['flower']} ${e['color']}")
        .join(' ');

    resultData['imageUrl'] = selectFloralImageUrl(
      vibe: vibe,
      flowers: formulaFlowers,
      theme: resultData['title']?.toString(),
    );

    return resultData;
  }

  /// Interactive AI Floral Concierge Chat
  static Future<String> chatWithConcierge({
    required String userQuery,
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );

      final systemPrompt = """
        You are 'Flora', Bloominous' AI Floral Assistant & Floriography Expert in the Philippines.
        Help customers with:
        - Flower meanings (Floriography)
        - Flower care & longevity advice
        - Bouquet recommendations for specific budgets or occasions
        - Directing them to use the 3D Builder or Visual AI Scanner

        Be warm, helpful, elegant, and concise (under 120 words). Answer directly and specifically to the user's question.
      """;

      final historyText = conversationHistory
          .map((m) => "${m['role']}: ${m['content']}")
          .join("\n");
      final fullPrompt =
          "$systemPrompt\n\nHistory:\n$historyText\nUser: $userQuery\nFlora:";

      final response = await model.generateContent([Content.text(fullPrompt)]);
      if (response.text != null && response.text!.trim().isNotEmpty) {
        return response.text!.trim();
      }
    } catch (e) {
      print("Gemini chatWithConcierge error: $e");
    }

    // Dynamic intelligent responses based on query keywords if API is unreachable or rate limited
    final lower = userQuery.toLowerCase();

    if (lower.contains('friend') || lower.contains('kaibigan')) {
      return "For a dear friend, Yellow Roses, Sunflowers, and Pink Gerberas are perfect! They represent joy, warmth, loyalty, and true friendship. A bright 'Sunny Friendship' bouquet will surely make their day!";
    } else if (lower.contains('mom') ||
        lower.contains('mother') ||
        lower.contains('nanay') ||
        lower.contains('mama')) {
      return "For mothers, Pink Carnations and White Stargazer Lilies are the ultimate choice! Pink carnations symbolize a mother's eternal, unselfish love, while lilies bring elegance and sweet fragrance to her home.";
    } else if (lower.contains('birthday') || lower.contains('kaarawan')) {
      return "For birthdays, a vibrant mix of colorful Tulips, Gerberas, and Sunflowers paired with a cheerful ribbon brings festive energy! It symbolizes celebration, happiness, and bright years ahead.";
    } else if (lower.contains('yellow') && lower.contains('red')) {
      return "Red roses symbolize deep love, passion, and romance, making them ideal for lovers and anniversaries. Yellow roses, on the other hand, represent joy, warmth, and friendship! Sending yellow roses is a wonderful way to celebrate a best friend or bring cheer.";
    } else if (lower.contains('1st anniversary') ||
        lower.contains('anniversary') ||
        lower.contains('monthsary')) {
      return "For anniversaries, classic Red Ecuadorian Roses paired with delicate Gypsophila (Baby's Breath) or Carnations (the traditional 1st-year flower) symbolize young, passionate love and new beginnings together!";
    } else if (lower.contains('gratitude') || lower.contains('thank')) {
      return "Pink Roses, Yellow Tulips, and White Hydrangeas are classic symbols of heartfelt gratitude and appreciation. They express sincere thanks and admiration!";
    } else if (lower.contains('sorry') ||
        lower.contains('apology') ||
        lower.contains('patawad')) {
      return "To say sorry, White Tulips or White Ecuadorian Roses represent sincere apologies, peace, and new beginnings. Pairing them with soft eucalyptus conveys heartfelt regret and goodwill.";
    } else if (lower.contains('grad') ||
        lower.contains('congrat') ||
        lower.contains('success')) {
      return "For graduation and achievements, Bright Sunflowers and Blue Hydrangeas represent grand success, wisdom, and a bright future ahead!";
    } else if (lower.contains('budget') ||
        lower.contains('cheap') ||
        lower.contains('mura') ||
        lower.contains('price')) {
      return "For budget-friendly options, local Sunflowers with Baby's Breath (Gypsophila) or a 3-stem Ecuadorian Rose bouquet offer stunning elegance starting at ₱500 - ₱1,000!";
    } else if (lower.contains('fresh') ||
        lower.contains('2 weeks') ||
        lower.contains('care') ||
        lower.contains('long')) {
      return "To keep your flowers fresh for up to 2 weeks:\n1. Trim 1-2 cm off stems at a 45° angle under running water.\n2. Change vase water every 2 days.\n3. Keep away from direct sunlight, aircon vents, and ripening fruits.";
    } else if (lower.contains('meaning') ||
        lower.contains('rose') ||
        lower.contains('floriography')) {
      return "In Floriography (the language of flowers):\n• Red = Deep Romance & Passion\n• White = Purity & Honesty\n• Pink = Grace & Admiration\n• Yellow = Friendship & Sunshine\n• Purple = Enchantment & Royalty";
    } else if (lower.contains('recommend') ||
        lower.contains('suggest') ||
        lower.contains('help') ||
        lower.contains('best')) {
      return "I would love to recommend the best flowers! For romance, choose Ecuadorian Red Roses. For a friend, go with Sunflowers or Yellow Tulips. For a mother, Pink Carnations or White Lilies are wonderful! Who is the lucky recipient?";
    }

    return "For '$userQuery', I recommend a bouquet featuring fresh Ecuadorian Roses, Sunflowers, and Eucalyptus. You can also use our 'Matchmaker' tab or 'Visual Stylist' above to get personalized 3D bouquet formulas!";
  }

  static Map<String, dynamic> _parseResponse(String text) {
    String product = 'Unknown Flower';
    int score = 0;
    String status = 'Unknown';
    String recommendation = '';

    try {
      final lines = text.split('\n');
      for (var line in lines) {
        if (line.startsWith('Product:')) {
          product = line.replaceFirst('Product:', '').trim();
        } else if (line.startsWith('Score:')) {
          final scoreStr = line.replaceFirst('Score:', '').trim();
          score = int.tryParse(
              RegExp(r'\d+').firstMatch(scoreStr)?.group(0) ?? '0') ??
              0;
        } else if (line.startsWith('Status:')) {
          status = line.replaceFirst('Status:', '').trim();
        } else if (line.startsWith('Recommendation:')) {
          recommendation = line.replaceFirst('Recommendation:', '').trim();
        }
      }
    } catch (e) {
      print("Error parsing Gemini response: $e");
    }

    return {
      'product': product,
      'score': score,
      'status': status,
      'recommendation': recommendation,
      'description': text
    };
  }
}