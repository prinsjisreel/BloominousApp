import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'inventory_data.dart';
import 'payment_service.dart';
import 'order_success_page.dart';
import 'google_maps_service.dart';
import 'order_submission_service.dart';
import 'psgc_service.dart';

const Map<String, String> postalCodes = {
  "Meycauayan": "3020",
  "Malolos": "3000",
  "Marilao": "3019",
  "Bacoor City": "4102",
  "Imus City": "4103",
  "Tagaytay City": "4120",
  "Baguio City": "2600",
  "Cebu City": "6000",
  "Mandaue City": "6014",
  "Quezon City": "1100",
  "Manila": "1000",
  "Makati City": "1200",
  "Taguig City": "1630",
  "Pasig City": "1600",
  "Angeles City": "2009",
  "Santa Rosa City": "4026",
  "Calamba City": "4027"
};

const Map<String, Map<String, double>> cityCoordinates = {
  "Meycauayan": {"lat": 14.7410, "lng": 120.9634},
  "Malolos": {"lat": 14.8510, "lng": 120.8162},
  "Marilao": {"lat": 14.7584, "lng": 120.9575},
  "Bacoor City": {"lat": 14.4613, "lng": 120.9622},
  "Imus City": {"lat": 14.4294, "lng": 120.9367},
  "Tagaytay City": {"lat": 14.1153, "lng": 120.9621},
  "Baguio City": {"lat": 16.4164, "lng": 120.5930},
  "Cebu City": {"lat": 10.3157, "lng": 123.8854},
  "Mandaue City": {"lat": 10.3446, "lng": 123.9390},
  "Quezon City": {"lat": 14.6760, "lng": 121.0437},
  "Manila": {"lat": 14.5995, "lng": 120.9842},
  "Makati City": {"lat": 14.5547, "lng": 121.0244},
  "Taguig City": {"lat": 14.5176, "lng": 121.0509},
  "Pasig City": {"lat": 14.5764, "lng": 121.0851},
  "Angeles City": {"lat": 15.1441, "lng": 120.5887},
  "Santa Rosa City": {"lat": 14.3121, "lng": 121.0933},
  "Calamba City": {"lat": 14.2128, "lng": 121.1649}
};

class AddressSuggestion {
  final String displayName;
  final double lat;
  final double lng;
  const AddressSuggestion({required this.displayName, required this.lat, required this.lng});
}

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

  final OrderSubmissionService _orderSubmissionService = OrderSubmissionService();

  final streetController = TextEditingController();
  final postalCodeController = TextEditingController();

  List<PsgcItem> _regions = [];
  List<PsgcItem> _provinces = [];
  List<PsgcItem> _cities = [];
  List<PsgcItem> _barangays = [];

  bool _isMetroManilaSelected = false;
  bool _isLoadingRegions = false;
  bool _isLoadingProvinces = false;
  bool _isLoadingCities = false;
  bool _isLoadingBarangays = false;

  String? selectedRegionCode;
  String? selectedRegionName;
  String? selectedProvinceCode;
  String? selectedProvinceName;
  String? selectedCityCode;
  String? selectedCityName;
  String? selectedBarangayName;

  bool sendAsGift = false;
  bool isLoading = false;
  bool isCodRestricted = false;
  String restrictionReason = "";

  String selectedPaymentMethod = 'gcash';

  double subtotal = 0.0;
  double deliveryFee = 0.0;
  double distanceKm = 0.0;
  String nearestBranchName = "";
  bool isCalculatingFee = false;
  bool isUsingRealRoadDistance = false;
  bool isAutoFillingAddress = false;

  double? _customerLat;
  double? _customerLng;
  double? _branchLat;
  double? _branchLng;

  double? _recipientLat;
  double? _recipientLng;

  List<AddressSuggestion> _streetSuggestions = [];
  bool _isSearchingStreet = false;
  Timer? _streetSearchDebounce;

  static const double feePerKm = 1.0;

  static const Map<String, String> _nominatimHeaders = {
    'User-Agent': 'BloominousApp/1.0 (contact: support@bloominous.example)',
  };

  @override
  void initState() {
    super.initState();
    subtotal = widget.cartTotal;
    streetController.addListener(_onStreetTextChanged);
    postalCodeController.addListener(_updateFullAddress);
    _checkUserFraudStatus();
    _loadRegions();
  }

  @override
  void dispose() {
    _streetSearchDebounce?.cancel();
    streetController.removeListener(_onStreetTextChanged);
    postalCodeController.removeListener(_updateFullAddress);
    streetController.dispose();
    postalCodeController.dispose();
    addressController.dispose();
    recipientController.dispose();
    phoneController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() => _isLoadingRegions = true);
    try {
      final regions = await PsgcService.getRegions();
      if (mounted) setState(() => _regions = regions);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load regions: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRegions = false);
    }
  }

  Future<void> _onRegionSelected(PsgcItem region) async {
    setState(() {
      selectedRegionCode = region.code;
      selectedRegionName = region.name;
      selectedProvinceCode = null;
      selectedProvinceName = null;
      selectedCityCode = null;
      selectedCityName = null;
      selectedBarangayName = null;
      _provinces = [];
      _cities = [];
      _barangays = [];
      _isMetroManilaSelected = false;
      _isLoadingProvinces = true;
      _updateFullAddress();
    });

    try {
      final result = await PsgcService.getProvincesOrCities(region.code);
      if (!mounted) return;
      setState(() {
        _isMetroManilaSelected = result.isMetroManila;
        if (result.isMetroManila) {
          _cities = result.items;
          selectedProvinceName = 'Metro Manila';
        } else {
          _provinces = result.items;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load provinces: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingProvinces = false);
    }
  }

  Future<void> _onProvinceSelected(PsgcItem province) async {
    setState(() {
      selectedProvinceCode = province.code;
      selectedProvinceName = province.name;
      selectedCityCode = null;
      selectedCityName = null;
      selectedBarangayName = null;
      _cities = [];
      _barangays = [];
      _isLoadingCities = true;
      _updateFullAddress();
    });

    try {
      final cities = await PsgcService.getCities(province.code);
      if (mounted) setState(() => _cities = cities);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load cities: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingCities = false);
    }
  }

  Future<void> _onCitySelected(PsgcItem city) async {
    setState(() {
      selectedCityCode = city.code;
      selectedCityName = city.name;
      selectedBarangayName = null;
      _barangays = [];
      _isLoadingBarangays = true;

      if (postalCodes.containsKey(city.name)) {
        postalCodeController.text = postalCodes[city.name]!;
      } else {
        postalCodeController.clear();
      }
      _updateFullAddress();
    });

    if (!sendAsGift) _calculateDeliveryFeeFromGps();

    try {
      final barangays = await PsgcService.getBarangays(city.code);
      if (mounted) setState(() => _barangays = barangays);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load barangays: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingBarangays = false);
    }
  }

  Future<void> _checkUserFraudStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final bool isRestricted = data['isRestricted'] ?? false;
          final bool isBanned = (data['status'] ?? '') == 'blocked';
          final int score = (data['fraudScore'] ?? 0) as int;

          bool restrictCod = false;
          String reason = "";

          if (isBanned || score >= 90) {
            restrictCod = true;
            reason = "Account flagged for severe fraud. Cash on Delivery is disabled.";
          } else if (isRestricted || (score >= 50 && score <= 86)) {
            restrictCod = true;
            reason = "Cash-on-Delivery (COD) disabled due to account restriction (50-86% risk rating).";
          }

          if (mounted && restrictCod) {
            setState(() {
              isCodRestricted = true;
              restrictionReason = reason;
              if (selectedPaymentMethod == 'cod') {
                selectedPaymentMethod = 'gcash';
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error checking fraud status: $e');
      }
    }
  }

  void _updateFullAddress() {
    final street = streetController.text.trim();
    final barangay = selectedBarangayName ?? '';
    final city = selectedCityName ?? '';
    final province = selectedProvinceName ?? '';
    final region = selectedRegionName ?? '';
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

  Future<void> _handleGetCurrentLocation() async {
    setState(() => isAutoFillingAddress = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission was denied. Please enable it in your device settings.';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      setState(() {
        _customerLat = position.latitude;
        _customerLng = position.longitude;
      });

      if (sendAsGift) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Your location has been recorded for verification. Please search and select the RECIPIENT\'s address below.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final address = await _reverseGeocode(position.latitude, position.longitude);
      if (address != null) {
        await _applyReverseGeocodedAddress(address);
      }

      await _calculateDeliveryFeeFromGps();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not determine location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isAutoFillingAddress = false);
    }
  }

  Future<Map<String, dynamic>?> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&addressdetails=1');
      final res = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Reverse geocode failed: $e');
      return null;
    }
  }

  Future<void> _applyReverseGeocodedAddress(Map<String, dynamic> geocoded) async {
    final addr = geocoded['address'] as Map<String, dynamic>? ?? {};

    final road = addr['road'] as String?;
    final houseNumber = addr['house_number'] as String?;
    final postcode = addr['postcode'] as String?;
    final cityGuess = (addr['city'] ?? addr['town'] ?? addr['municipality']) as String?;
    final provinceGuess = addr['state'] as String?;

    setState(() {
      if (road != null) {
        streetController.text = houseNumber != null ? '$houseNumber $road' : road;
      }
      if (postcode != null && postcode.isNotEmpty) {
        postalCodeController.text = postcode;
      }
    });

    if (provinceGuess == null && cityGuess == null) {
      _updateFullAddress();
      return;
    }

    for (final region in _regions) {
      final regionMatches = provinceGuess != null &&
          region.name.toLowerCase().contains('metro manila') &&
          (cityGuess?.toLowerCase().contains('manila') ?? false);
      if (regionMatches ||
          (provinceGuess != null &&
              region.name.toLowerCase().contains(provinceGuess.toLowerCase()))) {
        await _onRegionSelected(region);
        break;
      }
    }

    if (cityGuess != null && _cities.isNotEmpty) {
      PsgcItem? matchedCity;
      for (final city in _cities) {
        final normalizedCityName = city.name.toLowerCase().replaceAll(' city', '');
        if (normalizedCityName.contains(cityGuess.toLowerCase()) ||
            cityGuess.toLowerCase().contains(normalizedCityName)) {
          matchedCity = city;
          break;
        }
      }
      if (matchedCity != null) {
        await _onCitySelected(matchedCity);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Detected your general area — please confirm City and Barangay manually.')),
        );
      }
    }

    _updateFullAddress();
  }

  void _onStreetTextChanged() {
    _updateFullAddress();
    _streetSearchDebounce?.cancel();
    final query = streetController.text.trim();
    if (query.length < 4) {
      setState(() => _streetSuggestions = []);
      return;
    }
    _streetSearchDebounce = Timer(const Duration(milliseconds: 600), () {
      _searchStreetSuggestions(query);
    });
  }

  Future<void> _searchStreetSuggestions(String query) async {
    setState(() => _isSearchingStreet = true);
    try {
      final cityContext = selectedCityName != null ? ', $selectedCityName' : '';
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=0&limit=5&countrycodes=ph&q=${Uri.encodeComponent('$query$cityContext, Philippines')}');
      final res = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted) return;

      final data = jsonDecode(res.body) as List;
      setState(() {
        _streetSuggestions = data
            .map((e) => AddressSuggestion(
          displayName: e['display_name'] as String,
          lat: double.parse(e['lat'] as String),
          lng: double.parse(e['lon'] as String),
        ))
            .toList();
      });
    } catch (e) {
      debugPrint('Address search failed: $e');
    } finally {
      if (mounted) setState(() => _isSearchingStreet = false);
    }
  }

  Future<void> _onStreetSuggestionSelected(AddressSuggestion suggestion) async {
    setState(() {
      streetController.text = suggestion.displayName.split(',').first;
      _streetSuggestions = [];
    });
    _updateFullAddress();

    if (sendAsGift) {
      setState(() {
        _recipientLat = suggestion.lat;
        _recipientLng = suggestion.lng;
      });
      await _calculateDeliveryFeeForDestination(suggestion.lat, suggestion.lng);
    }
  }

  Future<void> _calculateDeliveryFeeFromGps() async {
    setState(() => isCalculatingFee = true);
    try {
      double? destLat = _customerLat;
      double? destLng = _customerLng;

      if (destLat == null || destLng == null) {
        if (selectedCityName != null && cityCoordinates.containsKey(selectedCityName)) {
          destLat = cityCoordinates[selectedCityName]!['lat'];
          destLng = cityCoordinates[selectedCityName]!['lng'];
        }
      }

      if (destLat == null || destLng == null) {
        throw 'Please tap "Get Current Location" or select your city to determine delivery fee.';
      }

      await _calculateDeliveryFeeForDestination(destLat, destLng, isSenderLocation: true);
    } catch (e) {
      debugPrint('Error calculating fee: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not determine location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isCalculatingFee = false);
    }
  }

  Future<void> _calculateDeliveryFeeForDestination(double destLat, double destLng,
      {bool isSenderLocation = false}) async {
    setState(() => isCalculatingFee = true);
    try {
      final branchesList = await InventoryData.getBranchesStream().first;
      if (branchesList.isEmpty) throw 'No branches found to calculate delivery';

      double minDistance = double.infinity;
      String closestBranchId = "";
      String closestBranchName = "";
      double? branchLat;
      double? branchLng;

      for (var branch in branchesList) {
        double bLat = branch['latitude']?.toDouble() ?? 14.7573;
        double bLng = branch['longitude']?.toDouble() ?? 120.9439;
        double distance = Geolocator.distanceBetween(bLat, bLng, destLat, destLng);
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
        }
      } catch (routesError) {
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
        _branchLat = branchLat;
        _branchLng = branchLng;
        if (isSenderLocation) {
          _customerLat = destLat;
          _customerLng = destLng;
        } else {
          _recipientLat = destLat;
          _recipientLng = destLng;
        }
        deliveryFee = distanceKm * feePerKm;
        InventoryData.selectedBranchId = closestBranchId;
      });
    } finally {
      if (mounted) setState(() => isCalculatingFee = false);
    }
  }

  double get total => subtotal + deliveryFee;

  String _formatFee(double amount) {
    if (amount == 0) return '0';
    return amount.toStringAsFixed(2);
  }

  Future<void> _processCheckout(String method) async {
    _updateFullAddress();
    if (recipientController.text.isEmpty ||
        addressController.text.isEmpty ||
        phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in all recipient, contact and location choices.')),
      );
      return;
    }

    if (sendAsGift && (_recipientLat == null || _recipientLng == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please search and select the recipient\'s exact delivery address using the suggestions below the street field.')),
      );
      return;
    }

    if (method == 'cod') {
      if (sendAsGift) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cash on Delivery isn\'t available for gift orders. Please choose GCash or Maya.')),
        );
        return;
      }
      if (isCodRestricted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(restrictionReason.isNotEmpty
                ? restrictionReason
                : 'Cash-on-Delivery is disabled for your account due to fraud risk rating.'),
          ),
        );
        return;
      }
    }

    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      final branchId = InventoryData.selectedBranchId ?? 'main_branch';

      if (method == 'gcash' || method == 'maya') {
        final checkoutUrl = await PaymentService.createCheckoutSession(
          amount: total,
          description: '${widget.occasion} - Flower Delivery',
          customerEmail: user?.email ?? 'customer@example.com',
          customerName: user?.displayName ?? recipientController.text,
          restrictToPaymentMethod: method == 'maya' ? 'paymaya' : 'gcash',
        );

        await _orderSubmissionService.submitOrder(
          name: recipientController.text,
          phone: phoneController.text,
          address: addressController.text,
          items: widget.cartItems,
          subtotal: subtotal,
          shippingFee: deliveryFee,
          paymentMethod: method,
          branchId: branchId,
          email: user?.email,
          isGift: sendAsGift,
          customerLat: _customerLat,
          customerLng: _customerLng,
        );

        final url = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch payment portal';
        }
      } else {
        final result = await _orderSubmissionService.submitOrder(
          name: recipientController.text,
          phone: phoneController.text,
          address: addressController.text,
          items: widget.cartItems,
          subtotal: subtotal,
          shippingFee: deliveryFee,
          paymentMethod: 'cod',
          branchId: branchId,
          email: user?.email,
          isGift: sendAsGift,
          customerLat: _customerLat,
          customerLng: _customerLng,
        );

        debugPrint('Order placed: ${result.invoiceId} (${result.orderId})');

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderSuccessPage()),
          );
        }
      }
    } on OrderSubmissionException catch (e) {
      String message = e.message;
      if (e.code == 'RESTRICTED') {
        message =
        '$message\n\nPhone verification is required to lift this restriction — this flow isn\'t available in the app yet. Please contact support.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            _sectionCard(
              context,
              title: 'Recipient Information',
              children: [
                _polishedField(
                  context: context,
                  controller: recipientController,
                  label: 'Recipient Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 14),
                _polishedField(
                  context: context,
                  controller: phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_android_outlined,
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),

            const SizedBox(height: 20),

            _sectionCard(
              context,
              title: 'Gift Checkout',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Send this order as a gift",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    sendAsGift
                        ? "You'll need to search and confirm the recipient's exact address below. Cash on Delivery is unavailable for gifts."
                        : "Recipient contact details will be kept secure.",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  value: sendAsGift,
                  activeColor: const Color(0xFFF4B400),
                  onChanged: (val) {
                    setState(() {
                      sendAsGift = val;
                      _recipientLat = null;
                      _recipientLng = null;
                      distanceKm = 0;
                      deliveryFee = 0;
                      nearestBranchName = '';
                      if (val && selectedPaymentMethod == 'cod') {
                        selectedPaymentMethod = 'gcash';
                      }
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            _sectionCard(
              context,
              title: 'Delivery Location',
              children: [
                _psgcDropdown<PsgcItem>(
                  context: context,
                  label: 'Select Region',
                  icon: Icons.map_outlined,
                  value: selectedRegionCode,
                  items: _regions,
                  isLoading: _isLoadingRegions,
                  onChanged: (item) => item != null ? _onRegionSelected(item) : null,
                ),
                const SizedBox(height: 14),
                if (!_isMetroManilaSelected) ...[
                  _psgcDropdown<PsgcItem>(
                    context: context,
                    label: 'Select Province',
                    icon: Icons.explore_outlined,
                    value: selectedProvinceCode,
                    items: _provinces,
                    isLoading: _isLoadingProvinces,
                    enabled: selectedRegionCode != null,
                    onChanged: (item) => item != null ? _onProvinceSelected(item) : null,
                  ),
                  const SizedBox(height: 14),
                ],
                _psgcDropdown<PsgcItem>(
                  context: context,
                  label: 'Select City/Municipality',
                  icon: Icons.location_city_outlined,
                  value: selectedCityCode,
                  items: _cities,
                  isLoading: _isLoadingCities,
                  enabled: _cities.isNotEmpty,
                  onChanged: (item) => item != null ? _onCitySelected(item) : null,
                ),
                const SizedBox(height: 14),
                _psgcDropdown<PsgcItem>(
                  context: context,
                  label: 'Select Barangay',
                  icon: Icons.home_work_outlined,
                  value: selectedBarangayName,
                  items: _barangays,
                  isLoading: _isLoadingBarangays,
                  enabled: selectedCityCode != null,
                  useNameAsValue: true,
                  onChanged: (item) {
                    if (item == null) return;
                    setState(() {
                      selectedBarangayName = item.name;
                      _updateFullAddress();
                    });
                  },
                ),
                const SizedBox(height: 14),
                _polishedField(
                  context: context,
                  controller: postalCodeController,
                  label: 'Postal Code',
                  icon: Icons.local_post_office_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                _polishedField(
                  context: context,
                  controller: streetController,
                  label: sendAsGift
                      ? 'Search recipient\'s Street / Building / House No.'
                      : 'Street Name, Building, House No.',
                  icon: Icons.edit_road_outlined,
                  maxLines: 2,
                  suffixIcon: _isSearchingStreet
                      ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                      : null,
                ),
                if (_streetSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF262626) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: _streetSuggestions
                          .map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_outlined,
                            color: Color(0xFFF4B400), size: 20),
                        title: Text(s.displayName,
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white : Colors.black87),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => _onStreetSuggestionSelected(s),
                      ))
                          .toList(),
                    ),
                  ),
                if (sendAsGift && _recipientLat != null)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recipient address confirmed for delivery.',
                            style: TextStyle(fontSize: 11, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            _buildLocationMap(context),
            const SizedBox(height: 12),

            if (nearestBranchName.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(isDark ? 0.12 : 0.05),
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
                          Text('Nearest Branch: $nearestBranchName',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87)),
                          Text(
                            isUsingRealRoadDistance
                                ? 'Google Maps Road Distance: ${distanceKm.toStringAsFixed(1)} KM'
                                : 'Est. Road Distance: ${distanceKm.toStringAsFixed(1)} KM',
                            style: TextStyle(
                              color: isUsingRealRoadDistance
                                  ? Colors.green[isDark ? 300 : 700]
                                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              fontSize: 12,
                              fontWeight: isUsingRealRoadDistance ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            if (!sendAsGift)
              TextButton.icon(
                onPressed: isCalculatingFee || isAutoFillingAddress
                    ? null
                    : _handleGetCurrentLocation,
                icon: (isCalculatingFee || isAutoFillingAddress)
                    ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: const Text('Get Current Location'),
              ),

            const SizedBox(height: 12),

            _sectionCard(
              context,
              title: 'Order Notes',
              children: [
                _polishedField(
                  context: context,
                  controller: notesController,
                  label: 'Specific instructions (Optional)',
                  icon: Icons.notes,
                  maxLines: 3,
                ),
              ],
            ),

            const SizedBox(height: 20),

            _sectionCard(
              context,
              title: 'Payment Method',
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPaymentMethod,
                  dropdownColor: isDark ? const Color(0xFF262626) : Colors.white,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  decoration: _fieldDecoration(context, 'Select Payment Method', Icons.payment_outlined),
                  items: [
                    const DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                    const DropdownMenuItem(value: 'maya', child: Text('Maya')),
                    DropdownMenuItem(
                      value: 'cod',
                      enabled: !isCodRestricted && !sendAsGift,
                      child: Text(
                        sendAsGift
                            ? 'Cash on Delivery (unavailable for gifts)'
                            : isCodRestricted
                            ? 'Cash on Delivery (Restricted)'
                            : 'Cash on Delivery',
                        style: TextStyle(
                          color: (isCodRestricted || sendAsGift) ? Colors.grey : null,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    if (val == 'cod' && (isCodRestricted || sendAsGift)) return;
                    setState(() => selectedPaymentMethod = val);
                  },
                ),
                if (isCodRestricted && !sendAsGift)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      restrictionReason,
                      style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 24),
            _buildOrderSummary(context),
            const SizedBox(height: 28),

            if (isLoading)
              const Center(child: CircularProgressIndicator(color: Color(0xFFF4B400)))
            else
              SizedBox(
                height: 58,
                child: ElevatedButton(
                  onPressed: () => _processCheckout(selectedPaymentMethod),
                  style: _actionButtonStyle(const Color(0xFFF4B400)),
                  child: const Text('PLACE ORDER',
                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms, curve: Curves.easeOut)
          .slideX(begin: -0.15, end: 0, duration: 400.ms, curve: Curves.easeOut),
    );
  }

  Widget _sectionCard(BuildContext context, {required String title, required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.3,
                fontSize: 11,
                color: isDark ? Colors.grey[400] : Colors.grey),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _polishedField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: _fieldDecoration(context, label, icon).copyWith(suffixIcon: suffixIcon),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFFF4B400), size: 20),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF4B400), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
    );
  }

  Widget _psgcDropdown<T extends PsgcItem>({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String? value,
    required List<T> items,
    required bool isLoading,
    required void Function(T?) onChanged,
    bool enabled = true,
    bool useNameAsValue = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF262626) : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: _fieldDecoration(context, label, icon).copyWith(
        suffixIcon: isLoading
            ? const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        )
            : null,
      ),
      items: items
          .map((item) => DropdownMenuItem<String>(
        value: useNameAsValue ? item.name : item.code,
        child: Text(item.name, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: (enabled && !isLoading)
          ? (selectedValue) {
        final match = items.firstWhere(
              (item) => (useNameAsValue ? item.name : item.code) == selectedValue,
        );
        onChanged(match as T);
      }
          : null,
    );
  }

  Widget _buildLocationMap(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final destLat = sendAsGift ? _recipientLat : _customerLat;
    final destLng = sendAsGift ? _recipientLng : _customerLng;
    final hasCoordinates = destLat != null && destLng != null && _branchLat != null && _branchLng != null;

    if (!hasCoordinates) {
      return Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 36, color: const Color(0xFFF4B400).withOpacity(0.6)),
            const SizedBox(height: 8),
            Text(
              sendAsGift
                  ? 'Search and select the recipient\'s address to see the route'
                  : 'Your delivery route will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final destinationPoint = LatLng(destLat, destLng);
    final branchPoint = LatLng(_branchLat!, _branchLng!);
    final bounds = LatLngBounds.fromPoints([destinationPoint, branchPoint]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
                interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bloominous.app',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(points: [destinationPoint, branchPoint], color: const Color(0xFFF4B400), strokeWidth: 3),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: destinationPoint,
                      width: 40,
                      height: 40,
                      child: _mapPin(
                          sendAsGift ? Icons.card_giftcard_rounded : Icons.person_pin_circle_rounded,
                          const Color(0xFF121212)),
                    ),
                    Marker(
                      point: branchPoint,
                      width: 40,
                      height: 40,
                      child: _mapPin(Icons.storefront_rounded, const Color(0xFFF4B400)),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 6,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
                child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 8, color: Colors.black54)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPin(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(6),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildOrderSummary(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          _summaryRow(context, 'Subtotal', subtotal.toStringAsFixed(2)),
          _summaryRow(
            context,
            distanceKm > 0 ? 'Delivery Fee (${distanceKm.toStringAsFixed(1)}km × ₱1)' : 'Delivery Fee',
            _formatFee(deliveryFee),
          ),
          Divider(height: 24, color: isDark ? Colors.white.withOpacity(0.1) : null),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
              Text('₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String formattedAmount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey)),
          Text('₱$formattedAmount', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  ButtonStyle _actionButtonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    );
  }
}