import 'dart:convert';
import 'dart:math';
import 'dart:typed_data'; // <-- ADDED for Uint8List
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';
import 'image_upload_service.dart'; // <-- ADDED IMPORT

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
            // FittedBox shrinks the title to fit instead of cutting it off
            // with "..." when the phone screen is narrow.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'REAL-TIME DELIVERY ROUTING',
                maxLines: 1,
                style: GoogleFonts.cormorantGaramond(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Text(
              'Driver: $_driverName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          // Short labels so both tabs fit on a small phone without being cut off.
          tabs: const [
            Tab(icon: Icon(Icons.alt_route), text: 'ACTIVE ROUTE'),
            Tab(icon: Icon(Icons.task_alt), text: 'DELIVERED / POD'),
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
          // Only orders an admin has released for dispatch appear on the
          // driver's route (see _isReadyForDriver). Pending / processing
          // orders and walk-in orders stay hidden until then.
          final activeOrders = allOrders.where(_isReadyForDriver).toList();

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

          // Newest delivery first (latest POD time / delivered time on top).
          deliveredOrders.sort((a, b) {
            final ta = _deliveredTime(a);
            final tb = _deliveredTime(b);
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1; // no time -> bottom
            if (tb == null) return -1;
            return tb.compareTo(ta); // bigger (newer) time first
          });

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
                    // Expanded = "take only the space the button leaves free",
                    // so the text can never push the button off the screen.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DISPATCH RUN SUMMARY',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 4),
                          Text('${activeOrders.length} Remaining Stops',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
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
                      Text(_isOptimizing ? 'SORTING...' : 'OPTIMIZE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              Flexible(
                child: Text(
                  'MULTI-STOP SEQUENCE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Colors.grey[600]),
                ),
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

  // One of three equal-width stats. Expanded gives each the same share of
  // the row; FittedBox shrinks the content if the phone is narrow, so
  // nothing can overflow.
  Widget _buildRouteMetric(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }

  Widget _buildStopCard(BuildContext context, Map<String, dynamic> order,
      int stopIndex, int totalStops, bool isDark) {
    final status = _normStatus(order);
    // Website orders and app orders name the same thing differently, so each
    // line tries every known spelling. (The web checkout saves 'address',
    // 'customer_name' and 'total_price'.)
    final address = (order['deliveryAddress'] ?? order['delivery_address'] ?? order['address'] ?? '')
        .toString()
        .trim()
        .isEmpty
        ? 'No address provided'
        : (order['deliveryAddress'] ?? order['delivery_address'] ?? order['address']).toString();
    final recipient = order['recipientName'] ??
        order['customerName'] ??
        order['customer_name'] ??
        'Customer';
    final phone = order['recipientPhone'] ?? order['phone'] ?? 'N/A';
    // num.tryParse also copes with a price that was saved as text.
    final total = num.tryParse((order['totalAmount'] ??
        order['totalPrice'] ??
        order['total_price'] ??
        order['total_amount'] ??
        0)
        .toString())
        ?.toDouble() ??
        0.0;
    final items = (order['items'] ?? order['flowers'] ?? []) as List<dynamic>;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'out_for_delivery':
        statusColor = Colors.indigo;
        statusLabel = 'IN TRANSIT';
        break;
      case 'in_transit':
      // Released by the shop, driver has not started yet.
        statusColor = Colors.orange;
        statusLabel = 'READY TO GO';
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
                // Wrap = "put the next chip on a new line if there's no room".
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                ),
                const SizedBox(width: 8),
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
        final time = _deliveredTime(order);
        final timestamp = time != null
            ? DateFormat('MMM dd, yyyy - h:mm a').format(time)
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

  // The only statuses that mean "the shop has released this order to the
  // driver". Admins set 'in transit' on the Orders page (web writes
  // 'in transit', the app writes 'IN TRANSIT'); once the driver taps
  // START DRIVE the order becomes 'out_for_delivery'.
  static const Set<String> _dispatchStatuses = {'in_transit', 'out_for_delivery'};

  /// Reads the moment an order was delivered, whatever type it was saved as
  /// (Firestore Timestamp, DateTime, milliseconds number or text).
  /// Returns null when there is no usable time.
  DateTime? _deliveredTime(Map<String, dynamic> o) {
    final raw = o['podTimestamp'] ?? o['deliveredAt'];
    if (raw == null) return null;
    try {
      if (raw is DateTime) return raw;
      if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
      if (raw is String) return DateTime.tryParse(raw);
      return (raw as dynamic).toDate() as DateTime; // Firestore Timestamp
    } catch (_) {
      return null;
    }
  }

  /// Lower-cases a status and turns spaces into underscores, so
  /// 'IN TRANSIT', 'in transit' and 'in_transit' are all the same word.
  String _normStatus(Map<String, dynamic> o) =>
      (o['status'] ?? '').toString().toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');

  /// True when this order belongs on the driver's active route.
  bool _isReadyForDriver(Map<String, dynamic> o) {
    final status = _normStatus(o);
    final deliveryStatus = (o['delivery_status'] ?? '').toString().toLowerCase();

    // Finished orders belong to the history tab, not the route.
    if (status == 'delivered' || deliveryStatus == 'delivered' || status == 'cancelled') {
      return false;
    }
    // Walk-in (POS) orders are handed over in the shop, never delivered.
    if ((o['type'] ?? 'WEB').toString().toUpperCase() == 'POS') return false;

    return _dispatchStatuses.contains(status);
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

  Widget _buildImageFromBase64OrUrl(String strData,
      {BoxFit fit = BoxFit.cover}) {
    try {
      if (strData.startsWith('data:image') || strData.contains(';base64,')) {
        final base64Str = strData.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: fit);
      } else if (strData.startsWith('http://') ||
          strData.startsWith('https://')) {
        return Image.network(strData,
            fit: fit,
            errorBuilder: (c, e, s) =>
            const Icon(Icons.broken_image, size: 40));
      } else {
        final bytes = base64Decode(strData);
        return Image.memory(bytes, fit: fit);
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
        order['customerName'] ??
        order['customer_name'])
        ?.toString() ??
        'N/A';
    final courier =
        (order['courierName'] ?? order['driverName'])?.toString() ?? 'N/A';
    final time = _deliveredTime(order);
    final timestamp = time != null
        ? DateFormat('MMM dd, yyyy - h:mm a').format(time)
        : 'N/A';

    const amber = Color(0xFFF59E0B);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFDF7);
        final textColor = isDark ? Colors.white : const Color(0xFF1F2937);
        final muted = isDark ? Colors.white60 : Colors.black54;
        final screen = MediaQuery.of(dialogContext).size;

        return Dialog(
          backgroundColor: bg,
          // Keeps a comfortable margin from the screen edges on any phone.
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: amber.withOpacity(0.6), width: 1.5),
          ),
          // The dialog can never be taller than 85% of the screen or wider
          // than 480px (tablets), and its content scrolls if it still does
          // not fit (small phones, landscape).
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screen.height * 0.85,
              maxWidth: 480,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, color: amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('PROOF OF DELIVERY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cormorantGaramond(
                                fontWeight: FontWeight.bold,
                                fontSize: 19,
                                letterSpacing: 1.1,
                                color: textColor)),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: muted),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (photo != null && photo.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        // Photo takes at most 45% of the screen height and
                        // is shown WHOLE (contain), never cropped. Pinch to zoom.
                        constraints:
                        BoxConstraints(maxHeight: screen.height * 0.45),
                        width: double.infinity,
                        color: Colors.black,
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: _buildImageFromBase64OrUrl(photo,
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _podInfoRow(Icons.person_outline, 'Received by', recipient,
                      textColor, muted),
                  _podInfoRow(Icons.local_shipping_outlined, 'Delivered by',
                      courier, textColor, muted),
                  _podInfoRow(Icons.schedule, 'Delivered on', timestamp,
                      textColor, muted),
                  if (notes != null && notes.isNotEmpty)
                    _podInfoRow(Icons.notes, 'Notes', notes, textColor, muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // One "icon  label / value" line. Expanded + soft wrapping means long
  // names or notes wrap onto the next line instead of overflowing.
  Widget _podInfoRow(IconData icon, String label, String value,
      Color textColor, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: muted)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Stateful Bottom Sheet for Capturing Proof Photo & Notes
//
// Rules for the rider (enforced by this screen):
//  * Photo can ONLY come from the live camera (no gallery).
//  * "Received By" is the customer's name from the order - read-only.
//  * "Delivered By" is the logged-in rider's own name - read-only.
//  * The rider can only type optional delivery notes.
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
  // Brand colours (same amber as the app theme in main.dart).
  static const Color _amber = Color(0xFFF59E0B);

  Uint8List? _imageBytes; // the captured photo, kept in memory until upload
  bool _isSubmitting = false;
  final _notesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Locked values - plain Strings (not TextEditingControllers) because
  // nothing on screen is allowed to change them.
  late final String _recipientName;
  late final String _courierName;

  @override
  void initState() {
    super.initState();
    // The website saves 'customer_name', the app saves 'customerName' /
    // 'recipientName', so we try every spelling and take the first one
    // that actually has text in it.
    String pick(List<String> keys, String fallback) {
      for (final k in keys) {
        final v = (widget.order[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return fallback;
    }

    _recipientName = pick(
        ['recipientName', 'customerName', 'customer_name'], 'Customer');
    // Always the signed-in rider - never a value typed by hand.
    _courierName = widget.driverName;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // Opens the phone camera. ImageSource.camera is hard-coded on purpose:
  // there is no way to pick an old photo from the gallery.
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1024,
        imageQuality: 75,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        if (mounted) setState(() => _imageBytes = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open camera: $e')));
      }
    }
  }

  Future<void> _submitDelivery() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
        Text('📸 Please take a Proof of Delivery photo before completing!'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await ImageUploadService.uploadBytes(
        bytes: _imageBytes!,
        storagePath:
        'pos_proof/${widget.order['branchId'] ?? 'main'}/${widget.order['id']}.jpg',
        cloudinaryFolder: 'bloom/delivery_proof',
      );

      await InventoryData.updateDeliveryStatus(
        widget.order['id'],
        'delivered',
        deliveryNotes: _notesController.text.trim(),
        proofOfDeliveryPhoto: result.url,
        deliveredLat: widget.currentPos?.latitude,
        deliveredLng: widget.currentPos?.longitude,
        driverName: _courierName, // locked: the signed-in rider
        recipientName: _recipientName, // locked: the order's customer
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🎉 Order marked as DELIVERED with Proof of Delivery!'),
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

  // ---------- small reusable UI pieces ----------

  Widget _sectionLabel(String text, Color textColor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text,
        style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.6,
            color: textColor)),
  );

  // A "looks like an input but cannot be edited" row with a lock icon.
  Widget _lockedField({
    required String value,
    required IconData icon,
    required Color fill,
    required Color border,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
          ),
          Icon(Icons.lock_outline, size: 16, color: textColor.withOpacity(0.4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Same palette family as the rest of the app (amber + warm light /
    // near-black dark).
    final sheetBg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFDF7);
    final fieldFill =
    isDark ? const Color(0xFF262626) : const Color(0xFFF5F1E6);
    final borderCol = isDark ? Colors.white12 : Colors.black12;
    final textColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    final media = MediaQuery.of(context);

    return ConstrainedBox(
      // Never taller than 92% of the screen, so the top never gets cut off.
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _amber.withOpacity(0.6), width: 2)),
        ),
        // SafeArea keeps the button above the phone's navigation bar;
        // viewInsets lifts the sheet when the keyboard opens.
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, media.viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: mutedColor.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),

                // header
                Row(
                  children: [
                    const Icon(Icons.verified, color: _amber, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('PROOF OF DELIVERY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cormorantGaramond(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              letterSpacing: 1.2,
                              color: textColor)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: mutedColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 1. PHOTO (camera only)
                _sectionLabel('1. DELIVERY PHOTO (REQUIRED)', mutedColor),
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _imageBytes != null ? Colors.green : _amber.withOpacity(0.5),
                      width: _imageBytes != null ? 2 : 1.2,
                    ),
                  ),
                  child: _imageBytes != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_imageBytes!, fit: BoxFit.cover),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              tooltip: 'Retake photo',
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white, size: 20),
                              // Retake opens the camera straight away.
                              onPressed: _isSubmitting ? null : _takePhoto,
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
                          size: 44, color: _amber.withOpacity(0.8)),
                      const SizedBox(height: 10),
                      Text('Take a photo of the delivered bouquet',
                          style: TextStyle(color: mutedColor, fontSize: 12)),
                      const SizedBox(height: 14),
                      // The ONLY way to add a photo.
                      ElevatedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('OPEN CAMERA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _amber,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. RECIPIENT (locked)
                _sectionLabel('2. RECEIVED BY (CUSTOMER)', mutedColor),
                _lockedField(
                  value: _recipientName,
                  icon: Icons.person_outline,
                  fill: fieldFill,
                  border: borderCol,
                  textColor: textColor,
                ),
                const SizedBox(height: 14),

                // 3. RIDER (locked)
                _sectionLabel('3. DELIVERED BY (RIDER)', mutedColor),
                _lockedField(
                  value: _courierName,
                  icon: Icons.local_shipping_outlined,
                  fill: fieldFill,
                  border: borderCol,
                  textColor: textColor,
                ),
                const SizedBox(height: 14),

                // 4. NOTES (the only editable text)
                _sectionLabel('4. DELIVERY NOTES (OPTIONAL)', mutedColor),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  style: TextStyle(color: textColor, fontSize: 14),
                  cursorColor: _amber,
                  decoration: InputDecoration(
                    hintText: 'e.g. Handed directly to recipient at main entrance',
                    hintStyle: TextStyle(color: mutedColor, fontSize: 13),
                    filled: true,
                    fillColor: fieldFill,
                    contentPadding: const EdgeInsets.all(14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: borderCol),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _amber, width: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // SUBMIT
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitDelivery,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: _amber.withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.black))
                    // FittedBox shrinks the label instead of clipping it.
                        : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 8),
                          Text('CONFIRM & COMPLETE DELIVERY',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: 0.6)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}