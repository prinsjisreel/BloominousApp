import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class KiriService {
  final String apiKey;
  final String baseUrl = 'https://api.kiriengine.app/api/v1';

  KiriService(this.apiKey);

  /// Helper to recursively search a JSON tree for a .glb URL
  String? _findGlbUrl(dynamic json) {
    if (json is String) {
      if (json.startsWith('http') && json.contains('.glb')) {
        return json;
      }
    } else if (json is Map) {
      for (var value in json.values) {
        final found = _findGlbUrl(value);
        if (found != null) return found;
      }
    } else if (json is List) {
      for (var item in json) {
        final found = _findGlbUrl(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Helper to recursively search a JSON tree for any of the given id/token keys
  String? _findKey(dynamic json, List<String> targetKeys) {
    if (json is Map) {
      for (var tk in targetKeys) {
        if (json.containsKey(tk) && json[tk] != null) {
          return json[tk].toString();
        }
      }
      for (var value in json.values) {
        final found = _findKey(value, targetKeys);
        if (found != null) return found;
      }
    } else if (json is List) {
      for (var item in json) {
        final found = _findKey(item, targetKeys);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<String> generateModel(File imageFile,
      {Function(String)? onStatusUpdate}) async {
    onStatusUpdate?.call('Uploading image to Kiri server...');

    // 1. Upload File
    final uploadUri = Uri.parse('$baseUrl/upload-file');
    final request = http.MultipartRequest('POST', uploadUri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files
        .add(await http.MultipartFile.fromPath('file', imageFile.path));

    final uploadResponse = await request.send();
    final uploadResponseStr = await uploadResponse.stream.bytesToString();

    if (uploadResponse.statusCode != 200 && uploadResponse.statusCode != 201) {
      throw Exception(
          'Upload failed with status ${uploadResponse.statusCode}: $uploadResponseStr');
    }

    final dynamic uploadData = jsonDecode(uploadResponseStr);

    // Scan for file reference
    final String? fileToken =
        _findKey(uploadData, ['file_token', 'file_id', 'id', 'token', 'key']);
    if (fileToken == null) {
      throw Exception(
          'Could not find file reference inside Kiri upload response: $uploadResponseStr');
    }

    // 2. Create Reconstruction Task
    onStatusUpdate?.call('Queuing 3D generation task (Image to 3D)...');

    final taskUri = Uri.parse('$baseUrl/tasks');
    final taskResponse = await http.post(
      taskUri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'image_to_3d',
        'file_token': fileToken,
        'file_id': fileToken,
        'project_name': 'Flower Model - ${DateTime.now().toLocal()}',
      }),
    );

    final dynamic taskData = jsonDecode(taskResponse.body);
    if (taskResponse.statusCode != 200 && taskResponse.statusCode != 201) {
      throw Exception(
          'Task creation failed with status ${taskResponse.statusCode}: ${taskResponse.body}');
    }

    final String? taskId =
        _findKey(taskData, ['task_id', 'project_id', 'id', 'token']);
    if (taskId == null) {
      throw Exception(
          'Could not find task/project reference in Kiri response: ${taskResponse.body}');
    }

    // 3. Poll for GLB output
    String? glbUrl;
    int attempts = 0;

    // Max 10 minutes (120 attempts * 5s)
    while (glbUrl == null && attempts < 120) {
      await Future.delayed(const Duration(seconds: 5));
      attempts++;
      onStatusUpdate
          ?.call('Kiri is reconstructing 3D flower... (Attempt $attempts/120)');

      final queryUri = Uri.parse('$baseUrl/tasks/$taskId');
      final statusResponse = await http.get(
        queryUri,
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      final dynamic statusData = jsonDecode(statusResponse.body);

      // Look for glb in the response tree
      glbUrl = _findGlbUrl(statusData);

      final statusStr =
          _findKey(statusData, ['status', 'state', 'progress'])?.toLowerCase();
      if (statusStr == 'failed' || statusStr == 'error') {
        throw Exception(
            'Kiri Task reported failure status: ${statusResponse.body}');
      }
    }

    if (glbUrl == null) {
      throw Exception(
          'Reconstruction timed out. Kiri Engine is taking longer than expected.');
    }

    // Save history to Firebase Firestore
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('kiri_history').add({
      'task_id': taskId,
      'url': glbUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'name': 'Kiri Bloom Flower',
      'userId': user?.uid ?? 'guest',
    });

    return glbUrl;
  }
}
