import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'inventory_data.dart';
import 'payment_service.dart';
import 'order_success_page.dart';
import 'google_maps_service.dart';

// --- Location Hierarchy Data ---
const Map<String, Map<String, Map<String, List<String>>>> locationHierarchy = {
  "National Capital Region (NCR)": {
    "Metro Manila": {
      "Quezon City": [
        "Bagong Pag-asa",
        "Diliman",
        "Socorro",
        "Katipunan",
        "Loyola Heights"
      ],
      "Manila": ["Malate", "Ermita", "Binondo", "Sampaloc", "Intramuros"],
      "Makati": ["Bel-Air", "Poblacion", "San Lorenzo", "Urdaneta"],
      "Taguig": ["Fort Bonifacio", "Pinagsama", "Western Bicutan"],
      "Pasig": ["San Antonio", "Kapitolyo", "Ugong", "Oranbo"]
    }
  },
  "Central Luzon (Region III)": {
    "Bulacan": {
      "Meycauayan": ["Lias", "Saluysoy", "Pandayan", "Banga", "Calvario"],
      "Malolos": ["Guinhawa", "Mojon", "Bulihan", "San Pablo", "Catmon"],
      "Marilao": ["Abangan Sur", "Loma de Gato", "Ibayo", "Lias"]
    },
    "Pampanga": {
      "Angeles": ["Balibago", "Malabanias", "Anunas", "Pulung Maragul"]
    }
  },
  "CALABARZON (Region IV-A)": {
    "Cavite": {
      "Bacoor": ["Ligas I", "Ligas II", "Mambog I", "Molino I", "Molino II"],
      "Imus": ["Anabu I", "Anabu II", "Bayan Luma", "Toclong"],
      "Tagaytay": ["Mendez Crossing", "Sungkai", "Silang Junction", "Iruhin"]
    },
    "Laguna": {
      "Santa Rosa": ["Balibago", "Don Jose", "Macabling", "Tagapo"],
      "Calamba": ["Parian", "Halang", "Real", "Barandal"]
    }
  },
  "CAR (Cordillera)": {
    "Benguet": {
      "Baguio": ["Camp 7", "Bakakeng", "Irisan", "Gibraltar", "Magsaysay"]
    }
  },
  "Central Visayas (Region VII)": {
    "Cebu": {
      "Cebu City": ["Lahug", "Banilad", "Mabolo", "Capitol Site", "Guadalupe"],
      "Mandaue": ["Bakilid", "Subangdaku", "Centro", "Cabancalan"]
    }
  }
};

const Map<String, String> postalCodes = {
  "Meycauayan": "3020",
  "Malolos": "3000",
  "Marilao": "3019",
  "Bacoor": "4102",
  "Imus": "4103",
  "Tagaytay": "4120",
  "Baguio": "2600",
  "Cebu City": "6000",
  "Mandaue": "6014",
  "Quezon City": "1100",
  "Manila": "1000",
  "Makati": "1200",
  "Taguig": "1630",
  "Pasig": "1600",
  "Angeles": "2009",
  "Santa Rosa": "4026",
  "Calamba": "4027"
};

const Map<String, Map<String, double>> cityCoordinates = {
  "Meycauayan": {"lat": 14.7410, "lng": 120.9634},
  "Malolos": {"lat": 14.8510, "lng": 120.8162},
  "Marilao": {"lat": 14.7584, "lng": 120.9575},
  "Bacoor": {"lat": 14.4613, "lng": 120.9622},
  "Imus": {"lat": 14.4294, "lng": 120.9367},
  "Tagaytay": {"lat": 14.1153, "lng": 120.9621},
  "Baguio": {"lat": 16.4164, "lng": 120.5930},
  "Cebu City": {"lat": 10.3157, "lng": 123.8854},
  "Mandaue": {"lat": 10.3446, "lng": 123.9390},
  "Quezon City": {"lat": 14.6760, "lng": 121.0437},
  "Manila": {"lat": 14.5995, "lng": 120.9842},
  "Makati": {"lat": 14.5547, "lng": 121.0244},
  "Taguig": {"lat": 14.5176, "lng": 121.0509},
  "Pasig": {"lat": 14.5764, "lng": 121.0851},
  "Angeles": {"lat": 15.1441, "lng": 120.5887},
  "Santa Rosa": {"lat": 14.3121, "lng": 121.0933},
  "Calamba": {"lat": 14.2128, "lng": 121.1649}
};

class DeliveryDetailsPage extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final double cartTotal;
  final String occasion;

  const DeliveryDetailsPage({
    super.key,
    required this.cartItems,
    required this.cartTotal,
    required this.occasion,
  });

  @override
  State<DeliveryDetailsPage> createState() => _DeliveryDetailsPageState();
}

class _DeliveryDetailsPageState extends State<DeliveryDetailsPage> {
  final addressController = TextEditingController();
  final recipientController = TextEditingController();
  final phoneController = TextEditingController();
  final notesController = TextEditingController();

  // Custom Location Fields
  String? selectedRegion;
  String? selectedProvince;
  String? selectedCity;
  String? selectedBarangay;
  final streetController = TextEditingController();
  final postalCodeController = TextEditingController();

  bool sendAsGift = false;
  bool isLoading = false;
  bool isCodRestricted = false;
  String restrictionReason = "";

  double subtotal = 0.0;
  double deliveryFee = 0.0;
  double distanceKm = 0.0;
  String nearestBranchName = "";
  bool isCalculatingFee = false;
  bool isUsingRealRoadDistance = false;

  // Constants for fee calculation
  static const double baseFee = 50.0;
  static const double feePerKm = 15.0; // ₱15 per km

  @override
  void initState() {
    super.initState();
    subtotal = widget.cartTotal;
    streetController.addListener(_updateFullAddress);
    postalCodeController.addListener(_updateFullAddress);
    _checkUserFraudStatus();
  }

  Future<void> _checkUserFraudStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final bool isRestricted = data['isRestricted'] ?? false;
          final bool isBanned = data['isBanned'] ?? false;
          final int score = (data['fraudScore'] ?? 0) as int;

          if (isBanned || score >= 90) {
            if (mounted) {
              setState(() {
                isCodRestricted = true;
                restrictionReason =
                    "Account flagged for severe fraud. Cash on Delivery is disabled.";
              });
            }
          } else if (isRestricted || (score >= 50 && score <= 86)) {
            if (mounted) {
              setState(() {
                isCodRestricted = true;
                restrictionReason =
                    "Cash-on-Delivery (COD) disabled due to account restriction (50-86% risk rating).";
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking fraud status: $e');
      }
    }
  }

  @override
  void dispose() {
    streetController.removeListener(_updateFullAddress);
    postalCodeController.removeListener(_updateFullAddress);
    streetController.dispose();
    postalCodeController.dispose();
    addressController.dispose();
    recipientController.dispose();
    phoneController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _updateFullAddress() {
    final street = streetController.text.trim();
    final barangay = selectedBarangay ?? '';
    final city = selectedCity ?? '';
    final province = selectedProvince ?? '';
    final region = selectedRegion ?? '';
    final postal = postalCodeController.text.trim();

    List<String> parts = [];
    if (street.isNotEmpty) parts.add(street);
    if (barangay.isNotEmpty) parts.add('Brgy. $barangay');
    if (city.isNotEmpty) parts.add(city);
    if (province.isNotEmpty) parts.add(province);
    if (region.isNotEmpty) parts.add(region);
    if (postal.isNotEmpty) parts.add(postal);

    addressController.text = parts.join(', ');
  }

  Future<void> _calculateDeliveryFee() async {
    setState(() => isCalculatingFee = true);
    try {
      double? destLat;
      double? destLng;

      // 1. Try GPS first
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 5),
          );
          destLat = position.latitude;
          destLng = position.longitude;
        }
      } catch (gpsError) {
        debugPrint(
            'GPS skipped/failed, falling back to selected city coordinate: $gpsError');
      }

      // 2. Fallback to city coordinates if GPS failed or wasn't allowed
      if (destLat == null &&
          selectedCity != null &&
          cityCoordinates.containsKey(selectedCity)) {
        destLat = cityCoordinates[selectedCity]!['lat'];
        destLng = cityCoordinates[selectedCity]!['lng'];
      }

      if (destLat == null || destLng == null) {
        throw 'Please select your delivery city first or grant GPS permission to determine delivery fee.';
      }

      // 3. Fetch all branches to find the nearest one
      final branchesList = await InventoryData.getBranchesStream().first;

      if (branchesList.isEmpty) {
        throw 'No branches found to calculate delivery';
      }

      double minDistance = double.infinity;
      String closestBranchId = "";
      String closestBranchName = "";
      double? branchLat;
      double? branchLng;

      for (var branch in branchesList) {
        double bLat = branch['latitude']?.toDouble() ?? 14.7573;
        double bLng = branch['longitude']?.toDouble() ?? 120.9439;

        double distance =
            Geolocator.distanceBetween(bLat, bLng, destLat, destLng);

        if (distance < minDistance) {
          minDistance = distance;
          closestBranchId = branch['id'] ?? "";
          closestBranchName = branch['name'] ?? "Main Branch";
          branchLat = bLat;
          branchLng = bLng;
        }
      }

      double finalDistanceKm = 0.0;
      bool usedRoutesApi = false;

      // Try Google Maps Routes API for precise Road Distance
      try {
        if (branchLat != null && branchLng != null) {
          final routeData = await GoogleMapsService.calculateRoute(
            originLat: branchLat,
            originLng: branchLng,
            destLat: destLat,
            destLng: destLng,
          );
          finalDistanceKm = routeData['distanceKm'];
          usedRoutesApi = true;
          debugPrint('Using Routes API: $finalDistanceKm km');
        }
      } catch (routesError) {
        debugPrint('Routes API skipped or failed: $routesError');
        double straightLineKm = minDistance / 1000;

        if (straightLineKm < 3) {
          finalDistanceKm = straightLineKm * 1.3;
        } else if (straightLineKm < 15) {
          finalDistanceKm = straightLineKm * 1.8;
        } else {
          finalDistanceKm = straightLineKm * 3.1;
        }
      }

      setState(() {
        nearestBranchName = closestBranchName;
        distanceKm = finalDistanceKm;
        isUsingRealRoadDistance = usedRoutesApi;

        // Formula: Base Fee + (Km * FeePerKm)
        deliveryFee = baseFee + (distanceKm * feePerKm);

        InventoryData.selectedBranchId = closestBranchId;
      });
    } catch (e) {
      debugPrint('Error calculating fee: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not determine location: $e')),
      );
      setState(() {
        deliveryFee = 120.0; // Fallback fee
        nearestBranchName = "Default Branch";
      });
    } finally {
      setState(() => isCalculatingFee = false);
    }
  }

  double get total => subtotal + deliveryFee;

  Future<void> _processCheckout(String method) async {
    _updateFullAddress();
    if (recipientController.text.isEmpty ||
        addressController.text.isEmpty ||
        phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please fill in all recipient, contact and location choices.')),
      );
      return;
    }

    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      // Simulate real-time security telemetry: if gift checked, flag fraud validation
      if (sendAsGift && user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'fraudScore': 85,
            'isFraud': true,
            'censoredName':
                recipientController.text.replaceAll(RegExp(r'.'), '*'),
          }, SetOptions(merge: true));
          debugPrint(
              "Real-time telemetry: gift order detected, updated customer safety metrics on active node.");
        } catch (e) {
          debugPrint("Failed to set security telemetry: $e");
        }
      }

      final Map<String, dynamic> orderPayload = {
        'userId': user?.uid,
        'recipientName': recipientController.text,
        'deliveryAddress': addressController.text,
        'recipientPhone': phoneController.text,
        'notes': notesController.text,
        'items': widget.cartItems,
        'totalAmount': total,
        'deliveryFee': deliveryFee,
        'occasion': widget.occasion,
        'is_gift': sendAsGift,
        'isGift': sendAsGift,
        'type': 'MOBILE',
        'orderType': 'MOBILE_CATALOG',
      };

      if (method == 'cod' && isCodRestricted) {
        throw restrictionReason.isNotEmpty
            ? restrictionReason
            : 'Cash-on-Delivery is disabled for your account due to fraud risk rating.';
      }

      if (method == 'paymongo') {
        final checkoutUrl = await PaymentService.createCheckoutSession(
          amount: total,
          description: '${widget.occasion} - Flower Delivery',
          customerEmail: user?.email ?? 'customer@example.com',
          customerName: user?.displayName ?? recipientController.text,
        );

        orderPayload['paymentMethod'] = 'paymongo';
        orderPayload['paymentStatus'] = 'awaiting_payment';
        orderPayload['status'] = 'Processing';
        orderPayload['checkoutUrl'] = checkoutUrl;

        await InventoryData.placeOrder(orderPayload);

        final url = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch payment portal';
        }
      } else {
        // COD
        orderPayload['paymentMethod'] = 'cod';
        orderPayload['paymentStatus'] = 'unpaid';
        orderPayload['status'] = 'Order Placed';

        await InventoryData.placeOrder(orderPayload);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderSuccessPage()),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get lists for nested location selectors
    List<String> regions = locationHierarchy.keys.toList();
    List<String> provinces = selectedRegion != null
        ? locationHierarchy[selectedRegion]!.keys.toList()
        : [];
    List<String> cities = selectedProvince != null
        ? locationHierarchy[selectedRegion]![selectedProvince]!.keys.toList()
        : [];
    List<String> barangays = selectedCity != null
        ? locationHierarchy[selectedRegion]![selectedProvince]![selectedCity]!
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'DELIVERY DETAILS',
          style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader('Recipient Information'),
            const SizedBox(height: 16),
            TextField(
              controller: recipientController,
              decoration:
                  _inputDecoration('Recipient Name', Icons.person_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: _inputDecoration(
                  'Phone Number', Icons.phone_android_outlined),
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 24),
            _buildSectionHeader('Delivery Location (Hierarchical)'),
            const SizedBox(height: 16),

            // Region Selector
            DropdownButtonFormField<String>(
              value: selectedRegion,
              decoration: _inputDecoration('Select Region', Icons.map_outlined),
              items: regions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedRegion = val;
                  selectedProvince = null;
                  selectedCity = null;
                  selectedBarangay = null;
                  _updateFullAddress();
                });
              },
            ),
            const SizedBox(height: 12),

            // Province Selector
            DropdownButtonFormField<String>(
              value: selectedProvince,
              decoration:
                  _inputDecoration('Select Province', Icons.explore_outlined),
              items: provinces
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: selectedRegion == null
                  ? null
                  : (val) {
                      setState(() {
                        selectedProvince = val;
                        selectedCity = null;
                        selectedBarangay = null;
                        _updateFullAddress();
                      });
                    },
            ),
            const SizedBox(height: 12),

            // City/Municipality Selector
            DropdownButtonFormField<String>(
              value: selectedCity,
              decoration: _inputDecoration(
                  'Select City/Municipality', Icons.location_city_outlined),
              items: cities
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: selectedProvince == null
                  ? null
                  : (val) {
                      setState(() {
                        selectedCity = val;
                        selectedBarangay = null;

                        // Auto-fill postal code
                        if (val != null && postalCodes.containsKey(val)) {
                          postalCodeController.text = postalCodes[val]!;
                        } else {
                          postalCodeController.clear();
                        }

                        _updateFullAddress();

                        // Auto recalculate delivery fee based on city coords
                        _calculateDeliveryFee();
                      });
                    },
            ),
            const SizedBox(height: 12),

            // Barangay Selector
            DropdownButtonFormField<String>(
              value: selectedBarangay,
              decoration:
                  _inputDecoration('Select Barangay', Icons.home_work_outlined),
              items: barangays
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: selectedCity == null
                  ? null
                  : (val) {
                      setState(() {
                        selectedBarangay = val;
                        _updateFullAddress();
                      });
                    },
            ),
            const SizedBox(height: 12),

            // Postal Code Field
            TextField(
              controller: postalCodeController,
              decoration: _inputDecoration(
                  'Postal Code', Icons.local_post_office_outlined),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            // Street / Detailed Address Field (Manual Typing)
            TextField(
              controller: streetController,
              decoration: _inputDecoration(
                  'Street Name, Building, House No.', Icons.edit_road_outlined),
              maxLines: 2,
            ),

            const SizedBox(height: 16),
            // Full Assembled Address Card View
            if (addressController.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFF4B400).withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DELIVERY SUMMARY LABEL',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      addressController.text,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            if (nearestBranchName.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nearest Branch: $nearestBranchName',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            isUsingRealRoadDistance
                                ? 'Google Maps Road Distance: ${distanceKm.toStringAsFixed(1)} KM'
                                : 'Est. Road Distance: ${distanceKm.toStringAsFixed(1)} KM',
                            style: TextStyle(
                                color: isUsingRealRoadDistance
                                    ? Colors.green[700]
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: isUsingRealRoadDistance
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: isCalculatingFee ? null : _calculateDeliveryFee,
              icon: isCalculatingFee
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(distanceKm > 0
                  ? 'Recalculate Fee'
                  : 'Get Current Location for Delivery Fee'),
            ),

            const SizedBox(height: 24),
            _buildSectionHeader('Gift Checkout Details'),
            const SizedBox(height: 8),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: SwitchListTile(
                title: const Text(
                  "Send this order as a gift",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: const Text(
                  "Recipient contact details will be kept secure. Custom security checks will be triggered.",
                  style: TextStyle(fontSize: 11),
                ),
                value: sendAsGift,
                activeColor: const Color(0xFFF4B400),
                onChanged: (val) {
                  setState(() {
                    sendAsGift = val;
                  });
                },
              ),
            ),

            const SizedBox(height: 24),
            _buildSectionHeader('Order Notes'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: _inputDecoration(
                  'Specific instructions (Optional)', Icons.notes),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            _buildOrderSummary(),
            const SizedBox(height: 32),
            if (isLoading)
              const Center(
                  child: CircularProgressIndicator(color: Color(0xFFF4B400)))
            else ...[
              ElevatedButton(
                onPressed: () => _processCheckout('paymongo'),
                style: _actionButtonStyle(Colors.blue[700]!),
                child: const Text('PAY WITH GCASH / MAYA'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed:
                    isCodRestricted ? null : () => _processCheckout('cod'),
                style: _outlinedButtonStyle(),
                child: Text(isCodRestricted
                    ? 'COD RESTRICTED (RISK LEVEL 50-86%)'
                    : 'CASH ON DELIVERY'),
              ),
              if (isCodRestricted)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    restrictionReason,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF121212), size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.withOpacity(0.03),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          fontSize: 11,
          color: Colors.grey),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _summaryRow('Subtotal', subtotal),
          _summaryRow(
              distanceKm > 0
                  ? 'Delivery Fee (${distanceKm.toStringAsFixed(1)}km)'
                  : 'Delivery Fee',
              deliveryFee),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text('₱${amount.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  ButtonStyle _actionButtonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }

  ButtonStyle _outlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: Colors.black12),
    );
  }
}
