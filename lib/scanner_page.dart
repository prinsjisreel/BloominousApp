import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'inventory_data.dart';
import 'gemini_service.dart';
import 'sound_helper.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  File? _image;
  bool _isAnalyzing = false;
  String? _analysisResult;
  final ImagePicker _picker = ImagePicker();

  // Parsed data
  int _freshnessScore = 0;
  String _status = 'Unknown';
  String _aiRecommendation = '';
  String _identifiedProduct = 'Unknown Flower';

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() {
        _image = File(photo.path);
        _analysisResult = null;
      });
      _analyzeFreshness();
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _image = File(image.path);
        _analysisResult = null;
      });
      _analyzeFreshness();
    }
  }

  Future<void> _analyzeFreshness() async {
    if (_image == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final imageBytes = await _image!.readAsBytes();
      final result = await GeminiService.analyzeFreshness(imageBytes);

      if (result.containsKey('error')) {
        setState(() {
          _analysisResult = "Error: ${result['error']}";
        });
        return;
      }

      setState(() {
        _identifiedProduct = result['product'];
        _freshnessScore = result['score'];
        _status = result['status'];
        _aiRecommendation = result['recommendation'];
        _analysisResult = result['description'];
      });

      SoundHelper.playBeep();

      // Automatically save to Firestore
      await _saveToFirestore();
    } catch (e) {
      setState(() {
        _analysisResult = "Error analyzing image: $e";
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _saveToFirestore() async {
    if (_freshnessScore == 0 && _identifiedProduct == 'Unknown Flower') return;

    try {
      final batchCode =
          "BATCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

      await InventoryData.saveFreshnessAnalysis(
        productName: _identifiedProduct,
        batchCode: batchCode,
        freshnessScore: _freshnessScore,
        status: _status,
        aiRecommendation: _aiRecommendation,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Analysis saved to dashboard!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("Error saving to Firestore: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'AI FRESHNESS SCANNER',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Preview Area
              Container(
                height: 350,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.05),
                  ),
                  image: _image != null
                      ? DecorationImage(
                          image: FileImage(_image!), fit: BoxFit.cover)
                      : null,
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 64,
                            color: isDark ? Colors.grey[700] : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Image Selected',
                            style: TextStyle(
                              color:
                                  isDark ? Colors.grey[600] : Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Take Photo',
                      onPressed: _isAnalyzing ? null : _takePhoto,
                      isPrimary: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      onPressed: _isAnalyzing ? null : _pickFromGallery,
                      isPrimary: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Results Area
              if (_isAnalyzing)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFFF4B400)),
                      SizedBox(height: 16),
                      Text(
                        'Analyzing Freshness...',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else if (_analysisResult != null)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFF4B400).withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: Color(0xFFF4B400), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'AI ANALYSIS',
                            style: TextStyle(
                              color: Color(0xFFF4B400),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _analysisResult!,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isPrimary
        ? (isDark ? Colors.white : const Color(0xFF121212))
        : (isDark ? Colors.grey[900]! : Colors.white);
    final Color textColor = isPrimary
        ? (isDark ? const Color(0xFF121212) : Colors.white)
        : (isDark ? Colors.white : const Color(0xFF121212));

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border:
            isPrimary ? null : Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
