import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';

class DeliveryDashboard extends StatefulWidget {
  const DeliveryDashboard({super.key});

  @override
  State<DeliveryDashboard> createState() => _DeliveryDashboardState();
}

class _DeliveryDashboardState extends State<DeliveryDashboard>
    with SingleTickerProviderStateMixin {
  String? _assignedBranchId;
  String _driverName = 'Driver';
  Position? _currentPosition;
  bool _isLocating = false;
  bool _isOptimizing = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDriverInfo();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDriverInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userData = await InventoryData.getUserData(user.uid);
      if (mounted) {
        setState(() {
          _assignedBranchId = userData?['branchId'];
          _driverName = userData?['name'] ??
              user.email?.split('@')[0] ??
              'Courier Driver';
        });
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLocating = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // Multi-stop route optimization by nearest-neighbor distance
  Future<void> _optimizeRoute(List<Map<String, dynamic>> activeOrders) async {
    if (activeOrders.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('At least 2 active stops are required to optimize route.')));
      return;
    }

    setState(() => _isOptimizing = true);

    try {
      // Driver starting coordinate (or default Metro Manila/Meycauayan center if GPS disabled)
      double startLat = _currentPosition?.latitude ?? 14.7410;
      double startLng = _currentPosition?.longitude ?? 120.9634;

      List<Map<String, dynamic>> unvisited = List.from(activeOrders);
      List<Map<String, dynamic>> sortedRoute = [];

      double currLat = startLat;
      double currLng = startLng;

      while (unvisited.isNotEmpty) {
        int nearestIdx = 0;
        double minDistance = double.infinity;

        for (int i = 0; i < unvisited.length; i++) {
          final order = unvisited[i];
          final lat =
              (order['deliveryLat'] ?? order['lat'] ?? 14.7410) as double;
          final lng =
              (order['deliveryLng'] ?? order['lng'] ?? 120.9634) as double;

          double d = _calculateHaversine(currLat, currLng, lat, lng);
          if (d < minDistance) {
            minDistance = d;
            nearestIdx = i;
          }
        }

        final nextStop = unvisited.removeAt(nearestIdx);
        sortedRoute.add(nextStop);

        currLat =
            (nextStop['deliveryLat'] ?? nextStop['lat'] ?? 14.7410) as double;
        currLng =
            (nextStop['deliveryLng'] ?? nextStop['lng'] ?? 120.9634) as double;
      }

      await InventoryData.updateDeliverySequence(sortedRoute);

      if (mounted) {
        setState(() => _isOptimizing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '✨ Route optimized! Arranged ${sortedRoute.length} stops by shortest driving distance.'),
          backgroundColor: Colors.green[700],
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOptimizing = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error optimizing route: $e')));
      }
    }
  }

  double _calculateHaversine(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  void _launchNavigation(String address) async {
    final query = Uri.encodeComponent(address);
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch maps app.')));
      }
    }
  }

  void _callCustomer(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not place phone call.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REAL-TIME DELIVERY ROUTING',
              style: GoogleFonts.cormorantGaramond(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'Driver: $_driverName',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(_isLocating ? Icons.gps_fixed : Icons.my_location,
                color: Colors.amber),
            tooltip: 'Update GPS Location',
            onPressed: _fetchCurrentLocation,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.alt_route), text: 'ACTIVE MULTI-STOP ROUTE'),
            Tab(icon: Icon(Icons.task_alt), text: 'DELIVERED & POD HISTORY'),
          ],
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: InventoryData.deliveryOrdersStream(branchId: _assignedBranchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          final allOrders = snapshot.data ?? [];
          final activeOrders = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() != 'delivered' &&
                  (o['delivery_status'] ?? '').toString().toLowerCase() !=
                      'delivered' &&
                  (o['status'] ?? '').toString().toLowerCase() != 'cancelled')
              .toList();

          // Sort active orders by stopSequence if present
          activeOrders.sort((a, b) {
            final seqA = a['stopSequence'] ?? 999;
            final seqB = b['stopSequence'] ?? 999;
            return seqA.compareTo(seqB);
          });

          final deliveredOrders = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() == 'delivered' ||
                  (o['delivery_status'] ?? '').toString().toLowerCase() ==
                      'delivered')
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildActiveRouteTab(context, activeOrders, isDark),
              _buildPODHistoryTab(context, deliveredOrders, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveRouteTab(BuildContext context,
      List<Map<String, dynamic>> activeOrders, bool isDark) {
    if (activeOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No pending deliveries on your route!',
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            const Text('All dispatch stops are completed.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final outForDeliveryCount = activeOrders
        .where((o) =>
            (o['status'] ?? '').toString().toLowerCase() == 'out_for_delivery')
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route Summary Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFF0F172A), const Color(0xFF1E293B)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DISPATCH RUN SUMMARY',
                            style: GoogleFonts.inter(
                                color: Colors.amber,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text('${activeOrders.length} Remaining Stops',
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _isOptimizing
                          ? null
                          : () => _optimizeRoute(activeOrders),
                      icon: _isOptimizing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label:
                          Text(_isOptimizing ? 'SORTING...' : 'OPTIMIZE ROUTE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildRouteMetric('In Transit', '$outForDeliveryCount',
                        Icons.directions_car, Colors.lightBlue),
                    _buildRouteMetric(
                        'Current GPS',
                        _currentPosition != null ? 'Acquired' : 'Searching...',
                        Icons.location_on,
                        Colors.greenAccent),
                    _buildRouteMetric('Sequence', 'Shortest Route',
                        Icons.swap_calls, Colors.amberAccent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MULTI-STOP SEQUENCE',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.grey[600]),
              ),
              Text(
                'Stop 1 to ${activeOrders.length}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeOrders.length,
            itemBuilder: (context, index) {
              final order = activeOrders[index];
              return _buildStopCard(
                  context, order, index + 1, activeOrders.length, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteMetric(
      String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildStopCard(BuildContext context, Map<String, dynamic> order,
      int stopIndex, int totalStops, bool isDark) {
    final status = (order['status'] ?? 'pending').toString().toLowerCase();
    final address = order['deliveryAddress'] ?? 'No address provided';
    final recipient =
        order['recipientName'] ?? order['customerName'] ?? 'Customer';
    final phone = order['recipientPhone'] ?? order['phone'] ?? 'N/A';
    final total =
        (order['totalAmount'] ?? order['totalPrice'] ?? 0.0).toDouble();
    final items = (order['items'] ?? order['flowers'] ?? []) as List<dynamic>;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'out_for_delivery':
        statusColor = Colors.indigo;
        statusLabel = 'IN TRANSIT';
        break;
      case 'processing':
      case 'confirmed':
        statusColor = Colors.orange;
        statusLabel = 'READY FOR PICKUP';
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = status.replaceAll('_', ' ').toUpperCase();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: status == 'out_for_delivery'
                ? Colors.indigo
                : Colors.transparent,
            width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stop header banner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'STOP #$stopIndex of $totalStops',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Recipient & Contact
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          recipient,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (phone != 'N/A')
                  IconButton(
                    icon:
                        const Icon(Icons.phone_forwarded, color: Colors.green),
                    tooltip: 'Call Recipient',
                    onPressed: () => _callCustomer(phone),
                  ),
              ],
            ),
            if (phone != 'N/A')
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text('Tel: $phone',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            const SizedBox(height: 8),

            // Address & Navigation Link
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(address,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _launchNavigation(address),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.navigation,
                                  size: 14, color: Colors.blue),
                              SizedBox(width: 4),
                              Text('Open GPS Navigation',
                                  style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Order Items
            if (items.isNotEmpty) ...[
              Text(
                'Items (${items.length}): ' +
                    items
                        .map((i) =>
                            '${i['name'] ?? 'Item'} x${i['qty'] ?? i['quantity'] ?? 1}')
                        .join(', '),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],

            // Actions
            Row(
              children: [
                if (status != 'out_for_delivery')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _updateStatus(order['id'], 'out_for_delivery'),
                      icon: const Icon(Icons.directions_car, size: 16),
                      label: const Text('START DRIVE'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (status != 'out_for_delivery') const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showPODModal(context, order),
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('MARK DELIVERED & PROOF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPODHistoryTab(BuildContext context,
      List<Map<String, dynamic>> deliveredOrders, bool isDark) {
    if (deliveredOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No delivered proof records yet.',
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deliveredOrders.length,
      itemBuilder: (context, index) {
        final order = deliveredOrders[index];
        final recipient = order['podRecipient'] ??
            order['recipientName'] ??
            order['customerName'] ??
            'Customer';
        final courier = order['courierName'] ?? order['driverName'] ?? 'Driver';
        final address = order['deliveryAddress'] ?? 'No address';
        final photo =
            (order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl']) as String?;
        final notes = order['deliveryNotes'] as String?;
        final rawTime = order['podTimestamp'] ?? order['deliveredAt'];
        final timestamp = rawTime != null
            ? DateFormat('MMM dd, yyyy - h:mm a')
                .format((rawTime as dynamic).toDate())
            : 'Recently Delivered';

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        SizedBox(width: 6),
                        Text('DELIVERED',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                    Text(timestamp,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(recipient,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(address,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 12),
                if (photo != null && photo.isNotEmpty) ...[
                  const Text('Proof of Delivery Photo:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showFullPhotoDialog(context, order),
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildImageFromBase64OrUrl(photo),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20)),
                                child: const Row(
                                  children: [
                                    Icon(Icons.zoom_in,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('View Photo',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Delivery Note: $notes',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateStatus(String orderId, String status) async {
    try {
      await InventoryData.updateDeliveryStatus(orderId, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Order status updated to ${status.replaceAll('_', ' ')}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // --- PROOF OF DELIVERY (POD) PHOTO CAPTURE MODAL ---
  void _showPODModal(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PODCaptureSheet(
        order: order,
        driverName: _driverName,
        currentPos: _currentPosition,
      ),
    );
  }

  Widget _buildImageFromBase64OrUrl(String strData) {
    try {
      if (strData.startsWith('data:image') || strData.contains(';base64,')) {
        final base64Str = strData.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover);
      } else if (strData.startsWith('http://') ||
          strData.startsWith('https://')) {
        return Image.network(strData,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.broken_image, size: 40));
      } else {
        final bytes = base64Decode(strData);
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    } catch (e) {
      return Container(
        color: Colors.grey[800],
        child: const Center(
            child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }
  }

  void _showFullPhotoDialog(BuildContext context, Map<String, dynamic> order) {
    final photo =
        (order['proofOfDeliveryPhoto'] ?? order['podPhotoUrl']) as String?;
    final notes = order['deliveryNotes'] as String?;
    final recipient = (order['podRecipient'] ??
            order['recipientName'] ??
            order['customerName']) as String? ??
        'N/A';
    final courier =
        (order['courierName'] ?? order['driverName']) as String? ?? 'N/A';
    final rawTime = order['podTimestamp'] ?? order['deliveredAt'];
    final timestamp = rawTime != null
        ? DateFormat('MMMM dd, yyyy - h:mm:ss a')
            .format((rawTime as dynamic).toDate())
        : 'N/A';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Proof of Delivery (POD)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              if (photo != null && photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 350),
                    width: double.infinity,
                    color: Colors.black,
                    child: _buildImageFromBase64OrUrl(photo),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Received By: $recipient',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              Text('Courier / Driver: $courier',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('Timestamp: $timestamp',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (notes != null && notes.isNotEmpty)
                Text('Notes: $notes',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }
}

// Stateful Bottom Sheet for Capturing Proof Photo & Notes
class _PODCaptureSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final String driverName;
  final Position? currentPos;

  const _PODCaptureSheet({
    required this.order,
    required this.driverName,
    this.currentPos,
  });

  @override
  State<_PODCaptureSheet> createState() => _PODCaptureSheetState();
}

class _PODCaptureSheetState extends State<_PODCaptureSheet> {
  String? _base64Photo;
  bool _isSubmitting = false;
  final _notesController = TextEditingController();
  late TextEditingController _recipientController;
  late TextEditingController _courierController;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _recipientController = TextEditingController(
      text: widget.order['podRecipient'] ??
          widget.order['recipientName'] ??
          widget.order['customerName'] ??
          '',
    );
    _courierController = TextEditingController(
      text: widget.order['courierName'] ?? widget.driverName,
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _courierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 75,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _base64Photo = base64Str;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not capture image: $e')));
      }
    }
  }

  Future<void> _submitDelivery() async {
    if (_base64Photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            '📸 Please capture or select a Proof of Delivery photo before completing!'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await InventoryData.updateDeliveryStatus(
        widget.order['id'],
        'delivered',
        deliveryNotes: _notesController.text.trim(),
        proofOfDeliveryPhoto: _base64Photo,
        deliveredLat: widget.currentPos?.latitude,
        deliveredLng: widget.currentPos?.longitude,
        driverName: _courierController.text.trim().isNotEmpty
            ? _courierController.text.trim()
            : widget.driverName,
        recipientName: _recipientController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              '🎉 Order marked as DELIVERED with Proof of Delivery photo!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to submit POD: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'PROOF OF DELIVERY (POD)',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text('Customer: ${widget.order['recipientName'] ?? "Customer"}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),

            // Photo Capture Preview Area
            Text('1. Delivery Photo Proof (Required)*',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),

            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.black38 : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _base64Photo != null
                      ? Colors.green
                      : Colors.grey.shade400,
                  width: _base64Photo != null ? 2 : 1,
                ),
              ),
              child: _base64Photo != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            base64Decode(_base64Photo!.split(',').last),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.refresh,
                                    color: Colors.white, size: 20),
                                onPressed: () =>
                                    setState(() => _base64Photo = null),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Row(
                                children: [
                                  Icon(Icons.check,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Photo Attached',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        const Text('Capture photo of delivered bouquet',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: const Text('CAMERA'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text('GALLERY'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // Recipient & Courier inputs
            Text('2. Received By (Recipient Name)*',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _recipientController,
              decoration: InputDecoration(
                hintText: 'e.g. Maria Santos',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),

            Text('3. Courier / Delivered By',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _courierController,
              decoration: InputDecoration(
                hintText: 'e.g. Super Admin / Driver Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),

            // Driver Notes
            Text('4. Delivery Notes / Remarks (Optional)',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'e.g. Handed directly to recipient at main entrance',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitDelivery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline),
                          SizedBox(width: 8),
                          Text('CONFIRM & COMPLETE DELIVERY'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
