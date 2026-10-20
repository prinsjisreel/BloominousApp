import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// TEMPORARY TESTING SWITCH.
/// true  -> when every provider fails, the red message also lists WHY each one
///          failed (useful while testing, because some phones hide app logs).
/// false -> customers only see the friendly sentence.
/// Set this to false before you demo the app to real customers.
const bool _showProviderDetails = true;

/// Prepares the room photo for Pixazo's image editors.
/// Qwen keeps the input photo's size, so this is where the 1536x1024
/// resolution is decided:
///   landscape (or square) photo -> exactly 1536 x 1024
///   portrait photo              -> exactly 1024 x 1536
/// The photo is centre-cropped to that shape first, then resized, so it
/// is never stretched. Runs in a background isolate via compute(), so it
/// MUST be a top-level function.
Uint8List _prepareRoomPhotoForPixazo(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const FormatException('Unreadable image');
  }
  final photo = img.bakeOrientation(decoded);

  final isLandscape = photo.width >= photo.height;
  final targetW = isLandscape ? 1536 : 1024;
  final targetH = isLandscape ? 1024 : 1536;
  final targetRatio = targetW / targetH;

  // Biggest centred box with the target shape that fits inside the photo.
  int cropW = photo.width;
  int cropH = (photo.width / targetRatio).round();
  if (cropH > photo.height) {
    cropH = photo.height;
    cropW = (photo.height * targetRatio).round();
  }

  final cropped = img.copyCrop(
    photo,
    x: ((photo.width - cropW) / 2).round(),
    y: ((photo.height - cropH) / 2).round(),
    width: cropW,
    height: cropH,
  );
  final sized = img.copyResize(cropped, width: targetW, height: targetH);
  return Uint8List.fromList(img.encodeJpg(sized, quality: 85));
}

/// A stylist image error with a customer-safe message.
/// `code` mirrors generate_stylist_image.php (DAILY_LIMIT, PROVIDER_BALANCE,
/// GENERATION_FAILED, INVALID_PHOTO, ...) or a client reason (NETWORK,
/// TIMEOUT, BAD_RESPONSE, BAD_PHOTO, DOWNLOAD_FAILED, NO_SESSION, ALL_FAILED).
class StylistImageException implements Exception {
  final String message;
  final String? code;
  final List<String> details; // per-provider failure notes, for debugging only

  StylistImageException(this.message, {this.code, this.details = const []});

  @override
  String toString() => message;
}

/// One finished image. `provider` is the display name used in snackbars
/// and the photo badge ('Gemini', 'Stability AI', 'Pixazo').
class StylistImageResult {
  final String provider;
  final String? imageUrl;
  final Uint8List? imageBytes;

  const StylistImageResult({required this.provider, this.imageUrl, this.imageBytes});

  bool get hasImage =>
      (imageUrl != null && imageUrl!.isNotEmpty) || (imageBytes != null && imageBytes!.isNotEmpty);
}

/// One link in the fallback chain: a display name + the function that makes the image.
class StylistImageStep {
  final String name;
  final Future<StylistImageResult> Function(String prompt) run;

  const StylistImageStep(this.name, this.run);
}

class StylistImageService {
  StylistImageService._(); // static-only helper, like OnlinePaymentService

  static const String _endpoint =
      'https://honeydew-duck-132160.hostingersite.com/generate_stylist_image.php';

  static const Duration _pollEvery = Duration(seconds: 4);
  // About 3 minutes in total. The server may start a second model (GPT Image)
  // when the first one (Qwen) fails, so the wait can be longer than before.
  static const int _maxPolls = 45;
  static const int _maxConsecutiveNetworkErrors = 3;
  static const int maxPromptChars = 1200; // same cap as the server

  // How much of each provider's error to show on screen.
  static const int _detailMaxChars = 180;

  // ---------------------------------------------------------------------
  // Pixazo: text -> image (no room photo) - GPT Image 2.5 Flare, paid
  // ---------------------------------------------------------------------

  static Future<StylistImageResult> generateWithPixazo(
      String prompt, {
        void Function(String status)? onStatus,
      }) async {
    final url = await _runPixazoJob(
      {'action': 'submit', 'prompt': _cleanPrompt(prompt)},
      onStatus,
    );
    onStatus?.call('Downloading your preview...');
    return StylistImageResult(provider: 'Pixazo', imageUrl: url, imageBytes: await _downloadImage(url));
  }

  // ---------------------------------------------------------------------
  // Pixazo: edit the customer's room photo.
  // The server tries Qwen Image 3.0 Pro first, then GPT Image 2.5 Flare.
  // ---------------------------------------------------------------------

  static Future<StylistImageResult> editWithPixazo({
    required Uint8List roomBytes,
    required String prompt,
    void Function(String status)? onStatus,
  }) async {
    if (roomBytes.isEmpty) {
      throw StylistImageException('Please upload a room photo first.', code: 'BAD_PHOTO');
    }
    final cleanPrompt = _cleanPrompt(prompt);

    onStatus?.call('Preparing your photo...');
    Uint8List preparedPhoto;
    try {
      preparedPhoto = await compute(_prepareRoomPhotoForPixazo, roomBytes);
    } catch (e) {
      debugPrint('StylistImageService: could not prepare photo: $e');
      throw StylistImageException('We could not read your photo. Please try another one.', code: 'BAD_PHOTO');
    }

    final url = await _runPixazoJob(
      {
        'action': 'edit',
        'prompt': cleanPrompt,
        'image': 'data:image/jpeg;base64,${base64Encode(preparedPhoto)}',
      },
      onStatus,
    );
    onStatus?.call('Downloading your preview...');
    return StylistImageResult(provider: 'Pixazo', imageUrl: url, imageBytes: await _downloadImage(url));
  }

  // ---------------------------------------------------------------------
  // Fallback chain: try each provider in order until one returns an image
  // ---------------------------------------------------------------------

  static Future<StylistImageResult> generateWithFallbacks({
    required String prompt,
    required List<StylistImageStep> steps,
    void Function(String status)? onStatus,
  }) async {
    final failures = <String>[];

    for (final step in steps) {
      try {
        onStatus?.call('Styling with ${step.name}...');
        final result = await step.run(prompt);
        if (result.hasImage) return result;
        failures.add('${step.name}: returned no image');
      } on StylistImageException catch (e) {
        // A daily limit is a decision, not an outage - stop and tell the customer.
        if (e.code == 'DAILY_LIMIT') rethrow;
        failures.add('${step.name}: ${e.code ?? ''} ${e.message}');
      } catch (e) {
        failures.add('${step.name}: $e');
      }
      debugPrint('StylistImageService: ${failures.last} - trying next provider.');
    }

    const friendlyMessage =
        'We could not create a preview right now. Please try again in a moment.';

    // TESTING: show why each provider failed, right on screen, because some
    // phones (e.g. Honor) hide app logs. Turn off with _showProviderDetails.
    final message = _showProviderDetails
        ? '$friendlyMessage\n\n[DETAILS]\n${failures.map(_shortReason).join('\n')}'
        : friendlyMessage;

    throw StylistImageException(
      message,
      code: 'ALL_FAILED',
      details: failures,
    );
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Keeps one provider's failure reason short enough to read in a snackbar.
  static String _shortReason(String reason) {
    final oneLine = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > _detailMaxChars
        ? '${oneLine.substring(0, _detailMaxChars)}...'
        : oneLine;
  }

  static String _cleanPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.length < 3) {
      throw StylistImageException('Please describe the arrangement first.', code: 'INVALID_PROMPT');
    }
    return trimmed.length > maxPromptChars ? trimmed.substring(0, maxPromptChars) : trimmed;
  }

  /// Starts a Pixazo job through our server, then polls until it finishes.
  /// Returns the finished image's URL.
  static Future<String> _runPixazoJob(
      Map<String, dynamic> startBody,
      void Function(String status)? onStatus,
      ) async {
    final start = await _post(startBody);
    final requestId = start['requestId'];
    if (requestId is! String || requestId.isEmpty) {
      throw StylistImageException('The image service gave an incomplete answer.', code: 'BAD_RESPONSE');
    }
    onStatus?.call('Your design is in the queue...');

    int consecutiveNetworkErrors = 0;
    for (int attempt = 1; attempt <= _maxPolls; attempt++) {
      await Future.delayed(_pollEvery);

      Map<String, dynamic> status;
      try {
        status = await _post({'action': 'status', 'requestId': requestId});
        consecutiveNetworkErrors = 0;
      } on StylistImageException catch (e) {
        final isBlip = e.code == 'NETWORK' || e.code == 'TIMEOUT';
        if (isBlip && ++consecutiveNetworkErrors < _maxConsecutiveNetworkErrors) {
          continue; // skip this round, try again next tick
        }
        rethrow;
      }

      final state = status['status']?.toString() ?? '';
      if (state == 'COMPLETED') {
        final url = status['imageUrl'];
        if (url is String && url.startsWith('https://')) return url;
        throw StylistImageException('The preview finished without an image.', code: 'BAD_RESPONSE');
      }

      onStatus?.call(state == 'PROCESSING'
          ? 'Arranging flowers in your room...'
          : 'Your design is in the queue...');
    }

    throw StylistImageException('The preview is taking too long. Please try again.', code: 'TIMEOUT');
  }

  /// Downloads the finished image so the page can keep working with bytes
  /// (display + reservation upload), exactly like Gemini's results.
  static Future<Uint8List> _downloadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      debugPrint('StylistImageService: download HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('StylistImageService: download failed: $e');
    }
    throw StylistImageException(
      'Your preview was created but could not be downloaded. Please try again.',
      code: 'DOWNLOAD_FAILED',
    );
  }

  /// Same shape as OrderSubmissionService: fresh ID token, timeout, one error type.
  static Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StylistImageException('Please sign in to use the Visual Stylist.', code: 'NO_SESSION');
    }
    final idToken = await user.getIdToken();

    http.Response response;
    try {
      response = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw StylistImageException('The image service is slow to respond.', code: 'TIMEOUT');
    } catch (e) {
      debugPrint('StylistImageService: request failed: $e');
      throw StylistImageException('Could not reach the image service.', code: 'NETWORK');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw StylistImageException(
        'The image service returned an unexpected response (HTTP ${response.statusCode}).',
        code: 'BAD_RESPONSE',
      );
    }

    if (data['success'] != true) {
      throw StylistImageException(
        data['message']?.toString() ?? 'The image service could not finish the request.',
        code: data['code']?.toString(),
      );
    }
    return data;
  }
}