import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'inventory_data.dart';
import 'app_sidebar.dart';

class KiriGeneratorPage extends StatefulWidget {
  final String role;
  const KiriGeneratorPage({super.key, this.role = 'employee'});

  @override
  State<KiriGeneratorPage> createState() => _KiriGeneratorPageState();
}

class _KiriGeneratorPageState extends State<KiriGeneratorPage> {
  // ============================================================
  // ONE LINE TO EDIT ONCE YOUR BACKEND ENDPOINT EXISTS:
  // This should point to a PHP (or similar) endpoint you control —
  // e.g. "https://honeydew-duck-132160.hostingersite.com/generate_3d_model.php"
  // — the SAME hosting pattern as submit_order.php and restore_trust.php
  // elsewhere in this project. That endpoint is what actually holds the
  // Hyper3D secret key and calls Hyper3D's API server-side. The mobile
  // app never sees or stores the real key — it only ever talks to YOUR
  // backend, which is the entire point of not embedding a secret inside
  // a compiled app that anyone can decompile.
  static const String _generate3dEndpoint = 'PASTE_YOUR_BACKEND_ENDPOINT_URL_HERE';
  // ============================================================

  File? _image;
  bool _isGenerating = false;
  String _status = '';
  String? _resultUrl;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _resultUrl = null;
        _status = '';
      });
    }
  }

  // --- Sends the reference photo to YOUR backend, not to Hyper3D
  // directly. The backend is responsible for holding the real Hyper3D
  // API key and forwarding the request — this function only ever knows
  // about _generate3dEndpoint above, matching the same "client never
  // holds the secret" pattern as the rest of this app's fraud/payment
  // flows (PaymentService, OrderSubmissionService). ---
  Future<void> _generate() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reference flower photo first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_generate3dEndpoint == 'PASTE_YOUR_BACKEND_ENDPOINT_URL_HERE') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backend Not Configured'),
          content: const Text(
            'The 3D generation endpoint hasn\'t been set up yet. Once the backend Hyper3D integration is ready, its URL needs to be pasted into _generate3dEndpoint in kiri_generator_page.dart.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _status = 'Uploading reference photo...';
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_generate3dEndpoint));
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));

      setState(() => _status = 'Generating 3D model — this can take a minute...');
      final streamedResponse = await request.send().timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final glbUrl = data['url'] ?? data['modelUrl'] ?? data['glbUrl'];
      if (glbUrl == null || glbUrl.toString().isEmpty) {
        throw Exception('No model URL returned by the server.');
      }

      await InventoryData.saveTripoModel({
        'name': 'Hyper3D Generated Flower',
        'url': glbUrl,
        'type': 'hyper3d_image_to_3d',
        'userId': 'admin_uploader',
      });

      setState(() {
        _resultUrl = glbUrl.toString();
        _isGenerating = false;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _status = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('3D Realism Hub', style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'kiri')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'kiri'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3D Realism Hub',
                      style: GoogleFonts.cormorantGaramond(fontSize: isDesktop ? 32 : 24, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upload a reference flower photo and generate a realistic 3D model automatically.',
                      style: TextStyle(fontSize: 12, color: subTextColor),
                    ),
                    const SizedBox(height: 24),

                    // Instructions card — kept, recontextualized: no longer
                    // a "how to manually scan without an API" guide, just
                    // a short explanation of the new automated flow.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Take a clear, well-lit photo of a real flower against a plain background. Upload it below and tap Generate — the model is built automatically and appears in the preview area once ready.',
                              style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Upload section ---
                    Text('Flower Reference Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                    const SizedBox(height: 8),
                    _image != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(_image!, height: 200, width: double.infinity, fit: BoxFit.cover),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: () => setState(() {
                                  _image = null;
                                  _resultUrl = null;
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                        : GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_rounded, size: 44, color: Color(0xFFF59E0B)),
                            const SizedBox(height: 10),
                            Text('Tap to select a reference photo', style: TextStyle(color: subTextColor, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: (_isGenerating || _image == null) ? null : _generate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          disabledBackgroundColor: borderColor,
                        ),
                        icon: _isGenerating
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                          _isGenerating ? 'GENERATING...' : 'GENERATE 3D MODEL',
                          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                    ),

                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_status, textAlign: TextAlign.center, style: TextStyle(color: subTextColor, fontSize: 12)),
                    ],

                    const SizedBox(height: 28),

                    // --- 3D preview area — kept, restyled to match portal ---
                    Text('3D Model Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 280,
                        width: double.infinity,
                        color: isDark ? Colors.black : const Color(0xFFF1F1F1),
                        child: _resultUrl != null
                            ? ModelViewer(
                          key: ValueKey(_resultUrl),
                          src: _resultUrl!,
                          alt: 'Generated 3D flower model',
                          ar: true,
                          autoRotate: true,
                          cameraControls: true,
                          backgroundColor: Colors.transparent,
                        )
                            : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.view_in_ar_rounded, size: 44, color: subTextColor),
                              const SizedBox(height: 10),
                              Text('Your generated model will appear here', style: TextStyle(color: subTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_resultUrl != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                Text('Model generated successfully', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _resultUrl!,
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 11, decoration: TextDecoration.underline),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                    Divider(color: borderColor),
                    const SizedBox(height: 16),
                    Text('Generation History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                    const SizedBox(height: 12),

                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.tripoHistoryStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
                            child: Text('No generated models yet.', style: TextStyle(color: subTextColor)),
                          );
                        }

                        final list = snapshot.data!;
                        return Column(
                          children: list.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                              child: ListTile(
                                leading: const Icon(Icons.view_in_ar_outlined, color: Color(0xFFF59E0B)),
                                title: Text(item['name'] ?? 'Generated Model',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                                subtitle: Text((item['url'] ?? '').toString(),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
                                trailing: IconButton(
                                  icon: Icon(Icons.play_circle_outline, color: subTextColor, size: 20),
                                  tooltip: 'Preview this model',
                                  onPressed: () => setState(() => _resultUrl = item['url']),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}