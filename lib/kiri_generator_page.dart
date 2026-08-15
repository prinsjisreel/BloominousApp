import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'kiri_service.dart';
import 'inventory_data.dart';

class KiriGeneratorPage extends StatefulWidget {
  const KiriGeneratorPage({super.key});

  @override
  State<KiriGeneratorPage> createState() => _KiriGeneratorPageState();
}

class _KiriGeneratorPageState extends State<KiriGeneratorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // API Tab State
  File? _image;
  bool _isGenerating = false;
  String _status = '';
  String? _resultUrl;
  final TextEditingController _apiKeyController = TextEditingController(
      text:
          'kiri_R20FEsh6d9JAMTznxYICltXe5d3sioHNA6bq' // Live API Key provided by user
      );

  // Guide Tab & Testing State
  final TextEditingController _testGlbController = TextEditingController(
      text:
          'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/MaterialsVariantsShoe/glTF-Binary/MaterialsVariantsShoe.glb');
  String? _currentTestModelUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiKeyController.dispose();
    _testGlbController.dispose();
    super.dispose();
  }

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

  Future<void> _generate() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select or capture a flower photo first.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final key = _apiKeyController.text.trim();
    if (key.isEmpty || key.contains('placeholder')) {
      // Direct warning about missing actual Kiri Key
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update KIRI Key Required'),
          content: const Text(
            'KIRI Engine API requires your personal API secret key from kiriengine.app/api/keys.\n\n'
            'Please paste your actual API key first to start generating.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            )
          ],
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _status = 'Connecting to Kiri service...';
    });

    try {
      final service = KiriService(key);
      final url = await service.generateModel(
        _image!,
        onStatusUpdate: (s) => setState(() => _status = s),
      );

      // Save Kiri metadata inside Firestore collection path
      await InventoryData.saveTripoModel({
        'name': 'Kiri Photogrammetry Flower',
        'url': url,
        'type': 'kiri_image_to_3d',
        'userId': 'admin_uploader',
      });

      setState(() {
        _resultUrl = url;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _status = 'Error: $e';
      });
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KIRI Generation Result'),
          content: Text(
            'The API call returned: $e\n\n'
            'To achieve 100% perfect, studio-grade photoreal models for your thesis advisory, we highly recommend using Kiri\'s free mobile app (Plan A tab) to take 3D scans of actual flowers.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor:
          const Color(0xFF0F0E13), // Deep charcoal black space theme
      appBar: AppBar(
        title: Text('3D REALISM HUB',
            style: GoogleFonts.orbitron(
                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.pinkAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.pinkAccent,
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome), text: 'API GENERATOR'),
            Tab(
                icon: Icon(Icons.photo_camera_back_rounded),
                text: 'PLAN A (REAL PHOTO SCAN)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Kiri REST Api Generator
          _buildApiTab(theme),

          // TAB 2: Plan A Guide & Live 3D Preview Sandbox
          _buildGuideTab(theme),
        ],
      ),
    );
  }

  Widget _buildApiTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Advice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.pinkAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pinkAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.pinkAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create fast 3D models using the Kiri Engine developers program. Ideal for instant drafts.',
                    style: TextStyle(color: Colors.grey[350], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Key Configuration
          Text(
            'KIRI Engine API Secret Key',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1B1A22),
              hintText: 'Enter kiri_sk_...',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.key, color: Colors.pinkAccent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Upload Box
          Text(
            'Flower Reference Image',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _image != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Image.file(_image!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover),
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black54),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _image = null),
                      )
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1A22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.grey[800]!, style: BorderStyle.solid),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded,
                            size: 48, color: Colors.pinkAccent),
                        const SizedBox(height: 10),
                        Text(
                          'Tap to pick reference flower photo',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: (_isGenerating || _image == null) ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              disabledBackgroundColor: Colors.grey[800],
            ),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _isGenerating ? 'GENERATING...' : 'GENERATE 3D VIA KIRI API',
              style: GoogleFonts.orbitron(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),

          if (_isGenerating || _status.isNotEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: Colors.pinkAccent, strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
          ],

          if (_resultUrl != null) ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Successfully Generated Model!',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _resultUrl!,
                    style: const TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 12,
                        decoration: TextDecoration.underline),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[700]!),
                    ),
                    icon: const Icon(Icons.view_in_ar, size: 18),
                    label: const Text('TEST MODEL ON SANDBOX'),
                    onPressed: () {
                      _testGlbController.text = _resultUrl!;
                      _tabController.animateTo(1);
                      setState(() {
                        _currentTestModelUrl = _resultUrl;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 36),
          const Divider(color: Color(0xFF23222A)),
          const SizedBox(height: 16),
          Text(
            '3D Model Generation History',
            style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.tripoHistoryStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.pinkAccent));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14131B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('No generated models in history yet.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                final list = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      tileColor: const Color(0xFF15141D),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      title: Text(item['name'] ?? 'Kiri Scan Model',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text(item['url'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.blueAccent, fontSize: 11)),
                      leading: const Icon(Icons.forest_outlined,
                          color: Colors.pinkAccent),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy,
                            color: Colors.grey, size: 18),
                        onPressed: () {
                          // Copy url
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Model link copied!'),
                                duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Adviser Quote Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C192E), Color(0xFF191224)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bookmark_added,
                        color: Colors.pinkAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'ADVISER\'S KEY RECOMMENDATION',
                      style: GoogleFonts.orbitron(
                          color: Colors.pinkAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '"Sabi ng adviser, picturan raw yung real flower ng 6 sides (top, bottom, and cross angles) '
                  'para makuha yung precise visual realism. Gusto niya: What You See Is What You Get para sa customers gagamit." ',
                  style: TextStyle(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                      fontSize: 13.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Steps of Plan A
          Text(
            'HOW TO CAPTURE REAL-WORLD FLOWERS (FREE & PRO)',
            style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          _buildStepRow('1', 'SCAN IN REAL LIFE',
              'Use free photogrammetry apps on your mobile phone: Polycam, Kiri Engine, or Luma AI to scan a physical flower. Take close-up photos from 6 distinct directional dimensions (top, bottom, & 4 sides) to capture the absolute realism your adviser expects.'),
          _buildStepRow('2', 'EXPORT AS GLB',
              'Export the finalized 3D mesh model completely free as a standard .glb (glTF Binary) file from your mobile app. This format contains embedded PBR textures which preserve exact highlights.'),
          _buildStepRow('3', 'HOST GLB FREE',
              'Upload your exported .glb file to any free host. You can upload them to your GitHub project repository, Firebase storage directory, or cheap file sharing servers to get a direct public URL link.'),
          _buildStepRow('4', 'LINK IN INVENTORY',
              'Paste that .glb URL into BloomyPro\'s Admin Inventory panel for any custom flower. Instantly, the genuine flower will display on the custom bouquet builder!'),

          const SizedBox(height: 30),
          const Divider(color: Color(0xFF23222A)),
          const SizedBox(height: 16),

          // Live 3D Sandbox Title
          Text(
            'LIVE GLB MODEL VIEW SANDBOX',
            style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste any .glb link to preview the realism of your photogrammetry model before adding it to products.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testGlbController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1B1A22),
                    hintText: 'https://example.com/flower.glb',
                    hintStyle:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _currentTestModelUrl = _testGlbController.text.trim();
                  });
                },
                child: const Text('LOAD 3D',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 280,
              color: Colors.black,
              child: _currentTestModelUrl != null &&
                      _currentTestModelUrl!.isNotEmpty
                  ? ModelViewer(
                      key: ValueKey(_currentTestModelUrl),
                      src: _currentTestModelUrl!,
                      alt: 'Photogrammetry Test Model',
                      ar: true,
                      autoRotate: true,
                      cameraControls: true,
                      backgroundColor: Colors.transparent,
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.view_in_ar_rounded,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            'Model Previews will display here.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
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

  Widget _buildStepRow(String number, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.pinkAccent,
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.orbitron(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                      color: Colors.grey[400], fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
