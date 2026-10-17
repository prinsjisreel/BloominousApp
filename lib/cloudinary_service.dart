import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_keys.dart';

/// Thrown when a Cloudinary upload fails for a reason the caller might
/// want to surface to the user (preset misconfigured, cloud name wrong,
/// file too large, etc). Network-level failures are wrapped in here too,
/// so the ImageUploadService fallback path only has to catch ONE type.
class CloudinaryException implements Exception {
  final String message;
  final String? code;

  CloudinaryException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Result of a successful Cloudinary upload.
class CloudinaryUploadResult {
  final String url;        // public_url — what goes into Firestore
  final String publicId;   // Cloudinary's asset id — useful for later delete
  final int bytes;

  const CloudinaryUploadResult({
    required this.url,
    required this.publicId,
    required this.bytes,
  });
}

/// Direct Cloudinary upload using the UNSIGNED upload preset.
///
/// Why unsigned: a signed upload needs your API secret on the device,
/// which is exactly the kind of secret that ends up in a decompiled APK.
/// An unsigned preset is designed specifically for client-side uploads
/// from a mobile/browser app — Cloudinary enforces the size limit, the
/// allowed formats, and the folder on the server side via the preset
/// configuration, so nothing sensitive ever lives in the app.
///
/// Requires two values from your Cloudinary dashboard:
///   - Cloud name:    Settings → Account → Cloud name
///   - Upload preset: Settings → Upload → Upload presets (mode = Unsigned)
///
/// Both are read from lib/api_keys.dart (which is gitignored), keeping
/// this file itself free of any hardcoded secrets.
class CloudinaryService {
  CloudinaryService._();

  /// Uploads raw bytes to Cloudinary. Works on Android, iOS, and web —
  /// always sends bytes, never a File path, so the same code path runs
  /// on all three platforms.
  ///
  /// [folder] is optional. If your preset already fixes a folder (most
  /// do), leave this null. If not, pass a logical folder like
  /// 'bloom/profile_photos' and it will be honored as long as the
  /// preset allows it.
  static Future<CloudinaryUploadResult> uploadBytes(
      Uint8List bytes, {
        required String fileName, // e.g. 'profile_uid123.jpg'
        String? folder,
        String? contentType,     // 'image/jpeg' if known; Cloudinary infers otherwise
      }) async {
    final cloudName = ApiKeys.cloudinaryCloudName.trim();
    final preset = ApiKeys.cloudinaryUploadPreset.trim();

    if (cloudName.isEmpty || cloudName.startsWith('PASTE_')) {
      throw CloudinaryException(
        'Cloudinary is not configured (missing cloud name).',
        code: 'NOT_CONFIGURED',
      );
    }
    if (preset.isEmpty || preset.startsWith('PASTE_')) {
      throw CloudinaryException(
        'Cloudinary is not configured (missing upload preset).',
        code: 'NOT_CONFIGURED',
      );
    }

    // Unsigned endpoint: no Authorization header, no signature — the
    // preset itself is the entire credential.
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = preset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName.isEmpty ? 'upload.jpg' : fileName,
        ),
      );

    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw CloudinaryException(
        'Cloudinary upload timed out. Please try again.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      debugPrint('CloudinaryService: transport error: $e');
      throw CloudinaryException(
        'Could not reach Cloudinary. Please check your connection.',
        code: 'NETWORK',
      );
    }

    final body = await streamed.stream.bytesToString();

    // Cloudinary returns JSON for both success and error, with a
    // distinguishable shape: {secure_url, public_id, ...} on success,
    // {error: {message: ...}} on failure. A missing JSON body (e.g. a
    // WAF HTML page) is also treated as a failure.
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      json = decoded;
    } catch (_) {
      debugPrint('CloudinaryService: non-JSON response '
          '(HTTP ${streamed.statusCode}): ${body.length > 300 ? body.substring(0, 300) : body}');
      throw CloudinaryException(
        'Cloudinary returned an unexpected response (HTTP ${streamed.statusCode}).',
        code: 'BAD_RESPONSE',
      );
    }

    if (streamed.statusCode != 200) {
      final msg = (json['error'] is Map)
          ? (json['error']['message']?.toString() ?? 'Upload failed')
          : 'Upload failed (HTTP ${streamed.statusCode})';
      throw CloudinaryException(msg, code: 'UPLOAD_FAILED');
    }

    final url = json['secure_url']?.toString();
    final publicId = json['public_id']?.toString();
    final size = (json['bytes'] is num) ? (json['bytes'] as num).toInt() : bytes.length;

    if (url == null || url.isEmpty || publicId == null || publicId.isEmpty) {
      throw CloudinaryException(
        'Cloudinary did not return a URL. Please try again.',
        code: 'BAD_RESPONSE',
      );
    }

    return CloudinaryUploadResult(
      url: url,
      publicId: publicId,
      bytes: size,
    );
  }

  /// Convenience for a local File (used by profile_page's image picker,
  /// which gives us a File on mobile). Reads the bytes and delegates.
  /// On web this is never called — the picker path on web already gives
  /// bytes — but keep the File import for mobile builds.
  static Future<CloudinaryUploadResult> uploadFile(
      File file, {
        String? fileName,
        String? folder,
      }) async {
    final bytes = await file.readAsBytes();
    return uploadBytes(
      bytes,
      fileName: fileName ?? _basename(file.path),
      folder: folder,
    );
  }

  static String _basename(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    return i >= 0 ? path.substring(i + 1) : path;
  }
}