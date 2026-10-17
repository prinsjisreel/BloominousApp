import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'cloudinary_service.dart';

/// Where the uploaded image actually ended up. The caller writes
/// [url] into Firestore without caring which provider produced it —
/// only the debug log and the `provider` field (if the caller chooses
/// to store it) record which one won.
enum UploadProvider { firebaseStorage, cloudinary }

class ImageUploadResult {
  final String url;
  final UploadProvider provider;

  /// Firebase Storage path (e.g. 'profile_photos/uid.jpg'). Null when the
  /// upload fell back to Cloudinary, because Cloudinary uses public_id
  /// instead — kept as a nullable field so existing callers that only
  /// ever used it for logging keep compiling.
  final String? firebasePath;

  /// Cloudinary public id. Null when Firebase Storage succeeded.
  final String? cloudinaryPublicId;

  const ImageUploadResult({
    required this.url,
    required this.provider,
    this.firebasePath,
    this.cloudinaryPublicId,
  });

  bool get isCloudinary => provider == UploadProvider.cloudinary;
}

/// The single entry point every upload site should call.
///
/// Behavior:
///   1. Try Firebase Storage with the given storagePath.
///   2. If that throws for ANY reason (billing not enabled, rules,
///      network, quota), log the failure and retry the SAME bytes on
///      Cloudinary using [cloudinaryFolder].
///   3. Return the URL of whichever provider succeeded.
///
/// Why not check "is Firebase Storage enabled" first: Firebase Storage
/// has no cheap "is billing on" probe — the first attempted upload IS
/// the probe. Attempting it once and catching the error is the cheapest
/// and most honest way to detect availability, and it keeps the code
/// identical when Storage genuinely works. The failed attempt costs one
/// short round-trip; the successful Cloudinary upload after that is
/// the actual request the user cares about.
class ImageUploadService {
  ImageUploadService._();

  /// Uploads [bytes] (works on every platform including web).
  ///
  /// [storagePath] is the intended Firebase Storage path; it doubles as
  /// the file name hint when we fall back to Cloudinary.
  /// [cloudinaryFolder] is optional — leave null if your preset already
  /// fixes a folder.
  static Future<ImageUploadResult> uploadBytes({
    required Uint8List bytes,
    required String storagePath, // e.g. 'profile_photos/uid.jpg'
    String? cloudinaryFolder,   // e.g. 'bloom/profile_photos'
    SettableMetadata? storageMetadata,
  }) async {
    // ── 1. Try Firebase Storage first — unchanged behavior for working setups.
    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(
        bytes,
        storageMetadata ??
            SettableMetadata(contentType: _guessContentType(storagePath)),
      );
      final url = await ref.getDownloadURL();
      debugPrint('ImageUploadService: uploaded to Firebase Storage ($storagePath)');
      return ImageUploadResult(
        url: url,
        provider: UploadProvider.firebaseStorage,
        firebasePath: storagePath,
      );
    } catch (storageError) {
      // Deliberately broad — the whole point is "any failure at all
      // triggers the fallback". Firebase Storage can throw a surprising
      // variety of exception types (FirebaseException, PlatformException,
      // a plain TimeoutException) depending on which layer actually
      // failed; matching on exception.code would miss most of them.
      debugPrint('ImageUploadService: Firebase Storage failed '
          '(${storageError.runtimeType}: $storageError). '
          'Falling back to Cloudinary.');
    }

    // ── 2. Fall back to Cloudinary with the same bytes.
    final fileName = _basenameOfPath(storagePath);
    try {
      final result = await CloudinaryService.uploadBytes(
        bytes,
        fileName: fileName,
        folder: cloudinaryFolder,
      );
      debugPrint('ImageUploadService: uploaded to Cloudinary '
          '(${result.url}, ${result.bytes} bytes)');
      return ImageUploadResult(
        url: result.url,
        provider: UploadProvider.cloudinary,
        cloudinaryPublicId: result.publicId,
      );
    } catch (cloudError) {
      // Both providers failed. Give the caller one clear error rather
      // than two chained stack traces.
      throw ImageUploadException(
        'Image upload failed on both Firebase Storage and Cloudinary. '
            'Please check your internet connection and try again.',
        cause: cloudError,
      );
    }
  }

  /// File-based convenience for the image picker path on mobile. On web,
  /// use uploadBytes — the picker there already gives bytes, and there
  /// is no real File on that platform.
  static Future<ImageUploadResult> uploadFile({
    required File file,
    required String storagePath,
    String? cloudinaryFolder,
    SettableMetadata? storageMetadata,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadBytes(
      bytes: bytes,
      storagePath: storagePath,
      cloudinaryFolder: cloudinaryFolder,
      storageMetadata: storageMetadata,
    );
  }

  static String _basenameOfPath(String path) {
    final slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  static String _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

/// Thrown when BOTH providers fail. The individual provider errors are
/// kept as a [cause] for debug logging, but the user-facing message
/// talks about the overall outcome.
class ImageUploadException implements Exception {
  final String message;
  final Object? cause;

  ImageUploadException(this.message, {this.cause});

  @override
  String toString() => message;
}