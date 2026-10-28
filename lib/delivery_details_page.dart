import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'inventory_data.dart';
import 'payment_service.dart';
import 'payment_checkout_page.dart';
import 'order_success_page.dart';
import 'google_maps_service.dart';
import 'order_submission_service.dart';
import 'psgc_service.dart';
import 'delivery_schedule.dart';
import 'delivery_schedule_section.dart';
import 'saved_address_service.dart';
import 'saved_addresses_sheet.dart';

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

  String selectedPaymentMethod = 'gcash';

  double subtotal = 0.0;
  double deliveryFee = 0.0;
  double distanceKm = 0.0;
  String nearestBranchName = "";
  // True when NO branch's delivery radius covers the chosen address.
  bool _outsideDeliveryArea = false;
  String _outsideAreaMessage = '';
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

  // --- Delivery date & time (same rules as web checkout.php) ---
  // false = "As soon as possible" (the default, and what older orders meant).
  bool _scheduleEnabled = false;
  DateTime? _scheduleDate;
  DeliverySlot? _scheduleSlot;

  // --- Address book (customers/{uid}/addresses, shared with the website) ---
  List<SavedAddress> _savedAddresses = [];
  String? _activeSavedAddressId; // the saved address currently shown in the form
  String? _editingAddressId; // set while the customer is editing a saved address
  bool _saveAddressForLater = false; // "Save this address for next time" tick box
  bool _isSavingAddress = false;
  bool _isApplyingSavedAddress = false;
  // While we fill the street box from code (not by typing), the street
  // search must stay quiet, or a suggestion list would pop open by itself.
  bool _suppressStreetSearch = false;

  // --- Account-restriction / phone-trust-restore state ---
  // FRAUD ACTIVITY MODEL: there is no fraud score anymore. The server
  // (submit_order.php) records fraud activities for admins to review and
  // only blocks an order in three situations, all mirrored here:
  //   - isRestricted == true -> phone verification required (any payment method)
  //   - status == 'blocked'  -> no orders at all
  //   - banned device match  -> server restricts the account on the spot
  //     (this listener then sees isRestricted flip to true live)
  StreamSubscription<DocumentSnapshot>? _fraudStatusSub;
  bool _isAccountRestricted = false;
  bool _isAccountBlocked = false;
  String? _restrictedUntilText;
  bool _otpVerifiedThisSession = false;
  bool _isVerifyingPhone = false;
  String? _phoneVerificationId;
  int _resendCooldown = 0;
  Timer? _resendTimer;
  final TextEditingController _otpInputController = TextEditingController();
  // -------------------------------------------------------

  static const double feePerKm = 1.0;

  static const Map<String, String> _nominatimHeaders = {
    'User-Agent': 'BloominousApp/1.0 (contact: support@bloominous.example)',
  };

  static const String _restoreTrustEndpoint =
      'https://honeydew-duck-132160.hostingersite.com/restore_trust.php';

  // check_phone_risk.php requires only a Firebase ID token — same
  // platform-agnostic shape as record_email_risk.php — so this is
  // reused as-is from web, no separate mobile endpoint needed.
  static const String _phoneRiskEndpoint =
      'https://honeydew-duck-132160.hostingersite.com/check_phone_risk.php';

  @override
  void initState() {
    super.initState();
    subtotal = widget.cartTotal;
    streetController.addListener(_onStreetTextChanged);
    postalCodeController.addListener(_updateFullAddress);
    _checkUserFraudStatus();
    // Regions must be loaded BEFORE a saved address can be applied (the
    // address is matched against the region list), so the address book loads
    // right after them.
    _loadRegions().whenComplete(_loadAddressBook);
  }

  @override
  void dispose() {
    _fraudStatusSub?.cancel();
    _resendTimer?.cancel();
    _otpInputController.dispose();
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

  // recalcFee: true for a normal dropdown tap. The "Get Current Location"
  // flow passes false because it recalculates the fee once, itself, after
  // all four levels are filled.
  Future<void> _onCitySelected(PsgcItem city, {bool recalcFee = true}) async {
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

    if (!sendAsGift && recalcFee) _calculateDeliveryFeeFromGps();

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

  // Watches THIS customer's own document live, so the checkout reacts the
  // moment an admin restricts/blocks the account (from web or the app's
  // Fraud Activity Log) or the server auto-restricts it after a
  // banned-device match. Only the fields submit_order.php actually
  // enforces are read here: isRestricted, restrictedUntil, status.
  void _checkUserFraudStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _fraudStatusSub = FirebaseFirestore.instance
        .collection('customers')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      // "== true" instead of "?? false": a missing OR non-boolean value
      // safely counts as "not restricted" instead of crashing.
      final bool isRestricted = data['isRestricted'] == true;
      final bool isBlocked = data['status'] == 'blocked';
      final restrictedUntil = data['restrictedUntil'];

      String? untilText;
      if (isRestricted && restrictedUntil is Timestamp) {
        final remaining = restrictedUntil.toDate().difference(DateTime.now());
        if (remaining.inDays >= 1) {
          untilText = 'for the next ${remaining.inDays} day${remaining.inDays == 1 ? '' : 's'}';
        } else if (remaining.inMinutes > 0) {
          untilText = 'for less than a day';
        }
      }

      setState(() {
        _isAccountRestricted = isRestricted;
        _isAccountBlocked = isBlocked;
        _restrictedUntilText = untilText;
        if (!isRestricted) _otpVerifiedThisSession = false;
      });
    }, onError: (e) => debugPrint('Account status listener error: $e'));
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
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'We got your GPS position but could not look up the address. Please choose it manually.')),
        );
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
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&addressdetails=1&zoom=18&accept-language=en');
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

  // ---------------------------------------------------------------------
  // GET CURRENT LOCATION -> fill Region, Province, City/Municipality, Barangay
  // ---------------------------------------------------------------------
  // Nominatim (OpenStreetMap) answers with PLAIN TEXT names ("Central Luzon",
  // "Bulacan", "Meycauayan", "Banga"). The dropdowns, however, are filled from
  // the PSGC government directory, whose names look different ("Region III
  // (Central Luzon)", "City of Meycauayan"). So the job here is to TRANSLATE
  // each text name into the matching PSGC item, one level at a time:
  //   Region -> Province -> City/Municipality -> Barangay
  // and to select each one exactly as if the customer had tapped it.

  /// Makes two spellings comparable: lowercase, no accents/punctuation, and
  /// without filler words like "City of", "Municipality of", "Barangay".
  String _normPlace(String? raw) {
    if (raw == null) return '';
    var t = raw.toLowerCase().replaceAll('ñ', 'n');
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    t = t.replaceAll(
        RegExp(r'\b(city of|municipality of|province of|city|municipality|barangay|brgy|bgy)\b'),
        ' ');
    t = t.replaceAll(RegExp(r'\bsta\b'), 'santa').replaceAll(RegExp(r'\bsto\b'), 'santo');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Finds the PSGC item that best matches any of the given text names.
  /// Pass 1 = exact match (after cleaning). Pass 2 = one name contains the
  /// other, and the closest in length wins (so "San Jose" beats
  /// "San Jose del Monte" when both could fit).
  PsgcItem? _matchItem(List<PsgcItem> items, Iterable<String?> candidates) {
    final cands = candidates.map(_normPlace).where((c) => c.isNotEmpty).toList();
    if (cands.isEmpty || items.isEmpty) return null;

    for (final c in cands) {
      for (final item in items) {
        if (_normPlace(item.name) == c) return item;
      }
    }

    PsgcItem? best;
    int bestGap = 1 << 30;
    for (final c in cands) {
      if (c.length < 3) continue;
      for (final item in items) {
        final n = _normPlace(item.name);
        if (n.length < 3) continue;
        if (n.contains(c) || c.contains(n)) {
          final gap = (n.length - c.length).abs();
          if (gap < bestGap) {
            bestGap = gap;
            best = item;
          }
        }
      }
    }
    return best;
  }

  /// Region match. "Metro Manila" is the one name PSGC spells differently
  /// ("National Capital Region (NCR)"), so it is matched by its known code.
  PsgcItem? _matchRegion(List<String?> texts) {
    for (final t in texts) {
      final n = _normPlace(t);
      if (n.contains('metro manila') || n.contains('national capital') || n == 'ncr') {
        for (final r in _regions) {
          if (r.code == PsgcService.metroManilaRegionCode) return r;
        }
      }
    }
    return _matchItem(_regions, texts);
  }

  /// Backup plan when the text has no usable region name: ask PSGC for every
  /// region's provinces (in parallel) and see which region owns this province.
  Future<PsgcItem?> _findRegionByProvince(List<String?> provinceTexts) async {
    if (provinceTexts.every((p) => _normPlace(p).isEmpty)) return null;

    final candidates =
    _regions.where((r) => r.code != PsgcService.metroManilaRegionCode).toList();
    final lists = await Future.wait(candidates.map((r) async {
      try {
        final res = await PsgcService.getProvincesOrCities(r.code);
        return res.items;
      } catch (_) {
        return <PsgcItem>[];
      }
    }));

    for (int i = 0; i < candidates.length; i++) {
      if (_matchItem(lists[i], provinceTexts) != null) return candidates[i];
    }
    return null;
  }

  /// Backup plan #2: maybe the person is in Metro Manila (which has no
  /// province level, so there is no province text to match).
  Future<PsgcItem?> _findNcrByCity(List<String?> cityTexts) async {
    try {
      final res = await PsgcService.getProvincesOrCities(PsgcService.metroManilaRegionCode);
      if (_matchItem(res.items, cityTexts) == null) return null;
      for (final r in _regions) {
        if (r.code == PsgcService.metroManilaRegionCode) return r;
      }
    } catch (_) {}
    return null;
  }

  /// Backup plan for the province level: look inside each province of the
  /// chosen region for the city name.
  Future<PsgcItem?> _findProvinceByCity(List<String?> cityTexts) async {
    if (cityTexts.every((c) => _normPlace(c).isEmpty)) return null;

    final provinces = List<PsgcItem>.from(_provinces);
    final lists = await Future.wait(provinces.map((p) async {
      try {
        return await PsgcService.getCities(p.code);
      } catch (_) {
        return <PsgcItem>[];
      }
    }));

    for (int i = 0; i < provinces.length; i++) {
      if (_matchItem(lists[i], cityTexts) != null) return provinces[i];
    }
    return null;
  }

  Future<void> _applyReverseGeocodedAddress(Map<String, dynamic> geocoded) async {
    final addr = (geocoded['address'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    // Reads one field from Nominatim's answer; empty text counts as missing.
    String? pick(String key) {
      final v = addr[key];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
    }

    final road = pick('road');
    final houseNumber = pick('house_number');
    final postcode = pick('postcode');

    // OpenStreetMap is inconsistent about WHICH field holds which level in the
    // Philippines, so each level gets a list of possible fields to try.
    final regionTexts = [pick('region'), pick('state')];
    final provinceTexts = [pick('province'), pick('county'), pick('state_district'), pick('state')];
    final cityTexts = [pick('city'), pick('town'), pick('municipality')];
    final barangayTexts = [
      pick('suburb'),
      pick('village'),
      pick('neighbourhood'),
      pick('quarter'),
      pick('city_district'),
      pick('hamlet'),
    ];

    // Street line
    if (road != null) {
      streetController.text = houseNumber != null ? '$houseNumber $road' : road;
    }

    // ---- 1. REGION ----
    if (_regions.isEmpty) await _loadRegions();
    if (!mounted) return;

    PsgcItem? region = _matchRegion(regionTexts);
    region ??= await _findRegionByProvince(provinceTexts);
    region ??= await _findNcrByCity(cityTexts);
    if (!mounted) return;

    if (region == null) {
      _updateFullAddress();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location found, but we could not match your region. Please choose Region, Province, City and Barangay manually.')),
      );
      return;
    }

    // Selecting the region also loads its provinces (or, for Metro Manila,
    // its cities). `await` = wait until that list has arrived.
    await _onRegionSelected(region);
    if (!mounted) return;

    // ---- 2. PROVINCE ----  (Metro Manila has no province level)
    PsgcItem? province;
    PsgcItem? city;

    if (_isMetroManilaSelected) {
      city = _matchItem(_cities, cityTexts);
    } else {
      province = _matchItem(_provinces, provinceTexts);
      province ??= await _findProvinceByCity(cityTexts);
      if (!mounted) return;

      if (province != null) {
        await _onProvinceSelected(province);
        if (!mounted) return;
        // ---- 3. CITY / MUNICIPALITY ----
        city = _matchItem(_cities, cityTexts);
      }
    }

    // ---- 3. CITY / MUNICIPALITY + 4. BARANGAY ----
    PsgcItem? barangay;
    if (city != null) {
      // recalcFee:false -> the caller (_handleGetCurrentLocation) already
      // recalculates the fee once after this finishes. Avoids a duplicate
      // Google Routes request.
      await _onCitySelected(city, recalcFee: false);
      if (!mounted) return;
      barangay = _matchItem(_barangays, barangayTexts);
    }

    setState(() {
      if (barangay != null) selectedBarangayName = barangay.name;
      // Set the postal code LAST: _onCitySelected clears it for cities that
      // are not in our small postalCodes table, which would erase the one
      // from the GPS result.
      if (postcode != null) postalCodeController.text = postcode;
      _updateFullAddress();
    });

    // ---- Tell the customer what happened ----
    if (!mounted) return;
    final missing = <String>[];
    if (!_isMetroManilaSelected && province == null) missing.add('Province');
    if (city == null) missing.add('City/Municipality');
    if (barangay == null) missing.add('Barangay');

    final found = <String>[
      if (barangay != null) 'Brgy. ${barangay.name}',
      if (city != null) city.name,
      if (province != null) province.name,
      region.name,
    ].join(', ');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(missing.isEmpty
            ? 'Location detected: $found'
            : 'Detected: $found. Please choose ${missing.join(' and ')} manually.'),
      ),
    );
  }

  void _onStreetTextChanged() {
    _updateFullAddress();
    if (_suppressStreetSearch) return;
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

      // Only branches whose delivery radius covers this address can take the
      // order. `minDistance` is the nearest branch that CAN deliver here.
      double minDistance = double.infinity;
      String closestBranchId = "";
      String closestBranchName = "";
      double? branchLat;
      double? branchLng;

      // The nearest branch overall (even if it can't deliver here). Only used
      // to explain WHY the address is out of range.
      double nearestAnyMeters = double.infinity;
      String nearestAnyName = "";
      double? nearestAnyRadiusKm;

      for (var branch in branchesList) {
        double bLat = branch['latitude']?.toDouble() ?? 14.7573;
        double bLng = branch['longitude']?.toDouble() ?? 120.9439;
        double distance = Geolocator.distanceBetween(bLat, bLng, destLat, destLng);

        // No radius saved (an older branch) = no limit, as before.
        final radiusKm = (branch['deliveryRadiusKm'] as num?)?.toDouble();
        final hasLimit = radiusKm != null && radiusKm > 0;

        if (distance < nearestAnyMeters) {
          nearestAnyMeters = distance;
          nearestAnyName = branch['name'] ?? "Main Branch";
          nearestAnyRadiusKm = hasLimit ? radiusKm : null;
        }

        final canDeliverHere = radiusKm == null || radiusKm <= 0 || distance / 1000 <= radiusKm;
        if (!canDeliverHere) continue;

        if (distance < minDistance) {
          minDistance = distance;
          closestBranchId = branch['id'] ?? "";
          closestBranchName = branch['name'] ?? "Main Branch";
          branchLat = bLat;
          branchLng = bLng;
        }
      }

      // No branch covers this address: stop here. No fee, no branch picked,
      // and _processCheckout refuses to place the order.
      if (closestBranchId.isEmpty) {
        if (!mounted) return;
        // Copied into `final` locals so Dart can safely null-check them
        // inside the setState callback below.
        final double? shownRadiusKm = nearestAnyRadiusKm;
        final String shownBranchName = nearestAnyName;
        final double shownMeters = nearestAnyMeters;
        setState(() {
          _outsideDeliveryArea = true;
          _outsideAreaMessage = shownRadiusKm != null
              ? '$shownBranchName delivers within ${shownRadiusKm.toStringAsFixed(shownRadiusKm % 1 == 0 ? 0 : 1)} km, '
                  'and this address is about ${(shownMeters / 1000).toStringAsFixed(1)} km away.'
              : 'We could not find a branch that delivers to this address.';
          nearestBranchName = '';
          distanceKm = 0;
          deliveryFee = 0;
          _branchLat = null;
          _branchLng = null;
          if (isSenderLocation) {
            _customerLat = destLat;
            _customerLng = destLng;
          } else {
            _recipientLat = destLat;
            _recipientLng = destLng;
          }
        });
        return;
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
        _outsideDeliveryArea = false;
        _outsideAreaMessage = '';
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

  // ---------------------------------------------------------------------
  // DELIVERY DATE & TIME
  // ---------------------------------------------------------------------

  /// What the customer has picked right now, as an object the rules and the
  /// order service both understand.
  DeliverySchedule _currentSchedule() => _scheduleEnabled
      ? DeliverySchedule.scheduled(date: _scheduleDate, slot: _scheduleSlot)
      : const DeliverySchedule.asap();

  void _onScheduleModeChanged(bool scheduled) {
    setState(() {
      _scheduleEnabled = scheduled;
      // First time they pick "Pick date & time": jump to the first day that
      // still has a bookable window, so the time chips show up immediately.
      if (scheduled && _scheduleDate == null) {
        _scheduleDate = DeliveryScheduleRules.earliestSelectableDate();
        _scheduleSlot = null;
      }
    });
  }

  Future<void> _pickScheduleDate() async {
    final first = DeliveryScheduleRules.earliestSelectableDate();
    if (first == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No delivery windows are open right now. Please choose "As soon as possible".')),
      );
      return;
    }
    final last = DeliveryScheduleRules.lastSelectableDate();

    // showDatePicker crashes if the starting date is not allowed, so make sure it is.
    var initial = _scheduleDate ?? first;
    if (initial.isBefore(first) || !DeliveryScheduleRules.isDateSelectable(initial)) {
      initial = first;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      helpText: 'DELIVERY DATE',
      // Days where every window is already too soon stay greyed out.
      selectableDayPredicate: (day) =>
          DeliveryScheduleRules.isDateSelectable(DeliveryScheduleRules.dateOnly(day)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      final newDate = DeliveryScheduleRules.dateOnly(picked);
      // A window picked for the old day may not exist on the new one: drop it.
      if (_scheduleSlot != null && !DeliveryScheduleRules.isSlotAvailable(newDate, _scheduleSlot!)) {
        _scheduleSlot = null;
      }
      _scheduleDate = newDate;
    });
  }

  // ---------------------------------------------------------------------
  // ADDRESS BOOK (saved addresses)
  // ---------------------------------------------------------------------

  /// Loads the customer's saved addresses once the region list is ready and,
  /// if the form is still empty, fills it with the default address.
  Future<void> _loadAddressBook() async {
    try {
      final list = await SavedAddressService.fetchAll();
      if (!mounted) return;
      setState(() {
        _savedAddresses = list;
        // A customer with no saved address yet gets the "save it" box ticked.
        if (list.isEmpty) _saveAddressForLater = true;
      });
      if (list.isEmpty) return;

      // Never overwrite something the customer already started typing.
      if (selectedRegionCode != null || streetController.text.trim().isNotEmpty) return;

      final defaultAddress = list.firstWhere((a) => a.isDefault, orElse: () => list.first);
      await _applySavedAddress(defaultAddress);
    } catch (e) {
      debugPrint('Could not load the address book: $e');
    }
  }

  Future<void> _refreshSavedAddresses() async {
    try {
      final list = await SavedAddressService.fetchAll();
      if (!mounted) return;
      setState(() {
        _savedAddresses = list;
        // If the address on screen was deleted, forget the link to it.
        if (!list.any((a) => a.id == _activeSavedAddressId)) _activeSavedAddressId = null;
        if (!list.any((a) => a.id == _editingAddressId)) _editingAddressId = null;
      });
    } catch (e) {
      debugPrint('Could not refresh saved addresses: $e');
    }
  }

  Future<void> _openAddressBook() async {
    final result = await showSavedAddressesSheet(context, selectedId: _activeSavedAddressId);
    // The sheet can delete / re-default addresses, so re-read the list afterwards.
    await _refreshSavedAddresses();
    if (result == null || !mounted) return;

    switch (result.action) {
      case SavedAddressAction.use:
        setState(() => _editingAddressId = null);
        await _applySavedAddress(result.address!);
        break;
      case SavedAddressAction.edit:
        await _applySavedAddress(result.address!);
        if (!mounted) return;
        setState(() => _editingAddressId = result.address!.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Change what you need, then tap "Update saved address".')),
        );
        break;
      case SavedAddressAction.addNew:
        _resetAddressForm();
        break;
    }
  }

  PsgcItem? _findByCode(List<PsgcItem> items, String? code) {
    if (code == null) return null;
    for (final item in items) {
      if (item.code == code) return item;
    }
    return null;
  }

  /// Fills the whole checkout form from one saved address — exactly as if the
  /// customer had typed it: recipient, phone, then Region -> Province ->
  /// City -> Barangay (each choice loads the next list), street, postal code,
  /// and finally the delivery fee from the saved map point.
  Future<void> _applySavedAddress(SavedAddress a) async {
    setState(() => _isApplyingSavedAddress = true);
    try {
      if (_regions.isEmpty) await _loadRegions();
      if (!mounted) return;

      recipientController.text = a.fullName;
      phoneController.text = a.phone;

      // The street box has a listener that searches for suggestions; silence
      // it while we set the text from code.
      _suppressStreetSearch = true;
      streetController.text = a.street;
      _suppressStreetSearch = false;
      setState(() => _streetSuggestions = []);

      // ---- Region ---- (PSGC code first; the saved name is the backup)
      final region = _findByCode(_regions, a.regionCode) ?? _matchRegion([a.regionName]);
      if (region == null) {
        _updateFullAddress();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('We could not match the saved region. Please choose Region, Province, City and Barangay again.')),
        );
        return;
      }
      await _onRegionSelected(region);
      if (!mounted) return;

      // ---- Province (Metro Manila has none) and City ----
      PsgcItem? province;
      PsgcItem? city;
      if (_isMetroManilaSelected) {
        city = _findByCode(_cities, a.cityCode) ?? _matchItem(_cities, [a.cityName]);
      } else {
        province = _findByCode(_provinces, a.provinceCode) ??
            _matchItem(_provinces, [a.provinceName]) ??
            await _findProvinceByCity([a.cityName]);
        if (!mounted) return;
        if (province != null) {
          await _onProvinceSelected(province);
          if (!mounted) return;
          city = _findByCode(_cities, a.cityCode) ?? _matchItem(_cities, [a.cityName]);
        }
      }

      // ---- Barangay ----
      PsgcItem? barangay;
      if (city != null) {
        // recalcFee:false -> the fee is calculated ONCE below, from the saved map point.
        await _onCitySelected(city, recalcFee: false);
        if (!mounted) return;
        barangay = _matchItem(_barangays, [a.barangay]);
      }

      setState(() {
        // The dropdown crashes if its value is not in its list, so only set a barangay we matched.
        selectedBarangayName = barangay?.name;
        // Postal code goes in LAST: _onCitySelected overwrites it for cities outside our small table.
        postalCodeController.text = a.postalCode;
        _activeSavedAddressId = a.id;
        _updateFullAddress();
      });

      // ---- Delivery fee ----
      // Reuse the saved map point. Without one, the city's rough centre is used (not for gifts).
      if (a.destLat != null && a.destLng != null) {
        if (sendAsGift) {
          setState(() {
            _recipientLat = a.destLat;
            _recipientLng = a.destLng;
          });
          await _calculateDeliveryFeeForDestination(a.destLat!, a.destLng!);
        } else {
          await _calculateDeliveryFeeForDestination(a.destLat!, a.destLng!, isSenderLocation: true);
        }
      } else if (!sendAsGift) {
        setState(() {
          _customerLat = null;
          _customerLng = null;
        });
        await _calculateDeliveryFeeFromGps();
      }

      if (!mounted) return;
      final missing = <String>[];
      if (!_isMetroManilaSelected && province == null) missing.add('Province');
      if (city == null) missing.add('City/Municipality');
      if (barangay == null) missing.add('Barangay');
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Address loaded, but please choose ${missing.join(' and ')} again.')),
        );
      }
    } catch (e) {
      debugPrint('Applying saved address failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load that address: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingSavedAddress = false);
    }
  }

  /// "Add New Address": empties the location part of the form (recipient name
  /// and phone stay, they are quick to change) and forgets the fee and route.
  void _resetAddressForm() {
    _suppressStreetSearch = true;
    streetController.clear();
    _suppressStreetSearch = false;
    postalCodeController.clear();
    setState(() {
      selectedRegionCode = null;
      selectedRegionName = null;
      selectedProvinceCode = null;
      selectedProvinceName = null;
      selectedCityCode = null;
      selectedCityName = null;
      selectedBarangayName = null;
      _provinces = [];
      _cities = [];
      _barangays = [];
      _isMetroManilaSelected = false;
      _streetSuggestions = [];
      _customerLat = null;
      _customerLng = null;
      _recipientLat = null;
      _recipientLng = null;
      _branchLat = null;
      _branchLng = null;
      distanceKm = 0;
      deliveryFee = 0;
      nearestBranchName = '';
      _outsideDeliveryArea = false;
      _outsideAreaMessage = '';
      _activeSavedAddressId = null;
      _editingAddressId = null;
      _saveAddressForLater = _savedAddresses.length < SavedAddressService.maxAddresses;
      _updateFullAddress();
    });
  }

  String _capText(String s, int max) => s.length > max ? s.substring(0, max) : s;

  /// Reads the form into a SavedAddress, or explains what is missing.
  /// (A Dart "record" returns two things at once: the address OR the error.)
  ({SavedAddress? address, String? error}) _buildAddressFromForm({String id = '', bool isDefault = false}) {
    _updateFullAddress();

    final name = recipientController.text.trim();
    final phone = normalizePhPhone(phoneController.text);
    final street = streetController.text.trim();
    final fullAddress = addressController.text.trim();

    if (name.isEmpty) return (address: null, error: 'Enter the recipient name first.');
    if (phone.length < 7 || phone.length > 20) {
      return (address: null, error: 'Enter a valid phone number first.');
    }
    if (selectedRegionCode == null || selectedCityCode == null || selectedBarangayName == null) {
      return (address: null, error: 'Choose Region, City/Municipality and Barangay first.');
    }
    if (!_isMetroManilaSelected && selectedProvinceCode == null) {
      return (address: null, error: 'Choose a Province first.');
    }
    if (street.isEmpty) {
      return (address: null, error: 'Enter the street / building / house number first.');
    }
    if (fullAddress.length < 10) {
      return (address: null, error: 'The address is too short to save.');
    }

    // Same map point the delivery fee used (recipient's for gifts, customer's otherwise).
    final lat = sendAsGift ? _recipientLat : _customerLat;
    final lng = sendAsGift ? _recipientLng : _customerLng;

    return (
    address: SavedAddress(
      id: id,
      fullName: _capText(name, 100),
      phone: phone,
      address: _capText(fullAddress, 400),
      regionCode: selectedRegionCode,
      regionName: _capText(selectedRegionName ?? '', 100),
      provinceCode: _isMetroManilaSelected ? null : selectedProvinceCode,
      provinceName: _capText(selectedProvinceName ?? '', 100),
      cityCode: selectedCityCode,
      cityName: _capText(selectedCityName ?? '', 100),
      barangay: _capText(selectedBarangayName!, 100),
      street: _capText(street, 200),
      postalCode: _capText(postalCodeController.text.trim(), 10),
      destLat: lat,
      destLng: lng,
      isDefault: isDefault,
    ),
    error: null,
    );
  }

  /// "Update saved address" button (only visible while editing one).
  Future<void> _updateEditedAddress() async {
    final editingId = _editingAddressId;
    if (editingId == null) return;

    final wasDefault = _savedAddresses.any((a) => a.id == editingId && a.isDefault);
    final built = _buildAddressFromForm(id: editingId, isDefault: wasDefault);
    if (built.address == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(built.error!)));
      return;
    }

    setState(() => _isSavingAddress = true);
    try {
      final id = await SavedAddressService.save(built.address!);
      await _refreshSavedAddresses();
      if (!mounted) return;
      setState(() {
        _editingAddressId = null;
        _activeSavedAddressId = id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved address updated.'), backgroundColor: Colors.green),
      );
    } on SavedAddressException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the address: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingAddress = false);
    }
  }

  /// Runs right after an order is accepted: if the customer ticked "Save this
  /// address", store it. It NEVER blocks or fails the order — the order is
  /// already placed, so any problem here is only logged.
  Future<void> _autoSaveAddressAfterOrder() async {
    if (!_saveAddressForLater || _editingAddressId != null) return;
    try {
      final built = _buildAddressFromForm();
      final candidate = built.address;
      if (candidate == null) return;

      // Same address + same phone already saved? Nothing to do.
      if (_savedAddresses.any((s) => s.sameAs(candidate.address, candidate.phone))) return;
      if (_savedAddresses.length >= SavedAddressService.maxAddresses) return;

      final id = await SavedAddressService.save(candidate);
      await _refreshSavedAddresses();
      if (mounted) setState(() => _activeSavedAddressId = id);
    } catch (e) {
      debugPrint('Auto-save of the address failed (order is unaffected): $e');
    }
  }

  double get total => subtotal + deliveryFee;

  String _formatFee(double amount) {
    if (amount == 0) return '0';
    return amount.toStringAsFixed(2);
  }

  void _handlePlaceOrderTapped() {
    // Blocked accounts can't order at all (the server answers BLOCKED).
    // Stopping here saves a pointless round trip and explains why.
    if (_isAccountBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This account can no longer place orders. Please contact the shop if you think this is a mistake.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

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

    // Check the delivery date/time BEFORE the phone-verification sheet, so a
    // customer never verifies their phone only to be stopped by a bad time.
    final scheduleError = DeliveryScheduleRules.validate(_currentSchedule());
    if (scheduleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(scheduleError)));
      return;
    }

    if (_isAccountRestricted && !_otpVerifiedThisSession) {
      _showPhoneVerificationSheet();
      return;
    }

    _processCheckout(selectedPaymentMethod);
  }

  /// UX-tier pre-check (see check_phone_risk.php) — stops an obviously
  /// disposable/VOIP number before spending an SMS credit and gives
  /// instant feedback. NOT the real enforcement boundary; submit_order.php
  /// runs its own unbypassable version of this same check regardless of
  /// what happens here. Fails OPEN on any error, same policy as web's
  /// checkout.php.
  Future<bool> _checkPhoneRiskPreCheck(String normalizedPhone) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;
      final idToken = await user.getIdToken();

      final response = await http
          .post(
        Uri.parse(_phoneRiskEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'phone': normalizedPhone}),
      )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return true;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) return true;

      if (data['block'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['reason'] as String? ??
                  'This phone number can\'t be used for verification.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Phone risk pre-check failed, proceeding anyway: $e');
      return true;
    }
  }

  Future<void> _startPhoneVerification(String rawPhone) async {
    setState(() => _isVerifyingPhone = true);
    String phoneNumber = rawPhone.trim();
    if (!phoneNumber.startsWith('+')) {
      if (phoneNumber.startsWith('09')) {
        phoneNumber = '+63${phoneNumber.substring(2)}';
      } else if (phoneNumber.startsWith('9')) {
        phoneNumber = '+63$phoneNumber';
      } else {
        phoneNumber = '+63$phoneNumber';
      }
    }

    // Cheapest, fastest check first — same ordering principle used
    // throughout this project's fraud pipeline (rate limit before
    // anything paid, etc.).
    final allowed = await _checkPhoneRiskPreCheck(phoneNumber);
    if (!allowed) {
      setState(() => _isVerifyingPhone = false);
      return;
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _linkPhoneCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isVerifyingPhone = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Verification failed: ${e.message}')),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _phoneVerificationId = verificationId;
            _isVerifyingPhone = false;
          });
          _startResendCooldown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _phoneVerificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isVerifyingPhone = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send verification code: $e')),
        );
      }
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    setState(() => _isVerifyingPhone = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'No active session. Please sign in again.';

      try {
        await user.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'provider-already-linked') rethrow;
      }

      final freshToken = await user.getIdToken(true);

      final response = await http.post(
        Uri.parse(_restoreTrustEndpoint),
        headers: {'Authorization': 'Bearer $freshToken'},
      );

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (result['success'] != true) {
        throw result['message'] ?? 'Could not restore trust. Please try again.';
      }

      setState(() {
        _otpVerifiedThisSession = true;
        _isVerifyingPhone = false;
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identity verified! Placing your order...'),
            backgroundColor: Colors.green,
          ),
        );
        _processCheckout(selectedPaymentMethod);
      }
    } catch (e) {
      setState(() => _isVerifyingPhone = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e')),
        );
      }
    }
  }

  void _showPhoneVerificationSheet() {
    _otpInputController.clear();
    _phoneVerificationId = null;
    _resendCooldown = 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[700] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Text('Identity Verification',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 8),
                    Text(
                      _phoneVerificationId == null
                          ? 'Verify your phone number to place orders on this account again.'
                          : 'Enter the 6-digit code sent to your phone.',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    if (_phoneVerificationId == null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_android, color: Color(0xFFF4B400), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('We will send a code to ${phoneController.text}',
                                  style: TextStyle(
                                      fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isVerifyingPhone
                              ? null
                              : () async {
                            await _startPhoneVerification(phoneController.text);
                            setModalState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF4B400),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isVerifyingPhone
                              ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('SEND CODE', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: _otpInputController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26,
                            letterSpacing: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '000000',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isVerifyingPhone
                              ? null
                              : () {
                            if (_otpInputController.text.length != 6) return;
                            final credential = PhoneAuthProvider.credential(
                              verificationId: _phoneVerificationId!,
                              smsCode: _otpInputController.text.trim(),
                            );
                            _linkPhoneCredential(credential);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF4B400),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isVerifyingPhone
                              ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('VERIFY', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: (_resendCooldown > 0 || _isVerifyingPhone)
                              ? null
                              : () async {
                            await _startPhoneVerification(phoneController.text);
                            setModalState(() {});
                          },
                          child: Text(_resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend Code'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

    // The address is outside every branch's delivery radius.
    if (_outsideDeliveryArea) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sorry, we don\'t deliver to this address. $_outsideAreaMessage'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (method == 'cod' && sendAsGift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cash on Delivery isn\'t available for gift orders. Please choose GCash or Maya.')),
      );
      return;
    }

    // Time may have passed since the customer picked a window (or since they
    // verified their phone), so check it again right before sending.
    final scheduleError = DeliveryScheduleRules.validate(_currentSchedule());
    if (scheduleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(scheduleError)));
      return;
    }

    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      final branchId = InventoryData.selectedBranchId ?? 'main_branch';

      // STEP 1 — the server decides first, for EVERY payment method.
      // submit_order.php runs the blocked/restricted gate, the
      // banned-device check, and records fraud activities. If it refuses
      // (RESTRICTED / BLOCKED / EMAIL_UNREACHABLE), it throws an
      // OrderSubmissionException and we never reach the payment step,
      // so no PayMongo session is ever created for a refused order.
      final result = await _orderSubmissionService.submitOrder(
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
        otpVerified: _otpVerifiedThisSession,
        notes: notesController.text,
        deliverySchedule: _currentSchedule(),
      );

      debugPrint('Order placed: ${result.invoiceId} (${result.orderId})');

      // The order exists now, so it is safe to remember the address for next time.
      await _autoSaveAddressAfterOrder();

      if (method == 'gcash' || method == 'maya') {
        // STEP 2 (e-wallet only) — the order exists now, so open payment.
        // If this part fails, the order is already saved as pending, so
        // the message tells the customer their invoice number instead of
        // implying nothing happened.
        String checkoutUrl;
        try {
          // Same server endpoint as the web checkout: the amount comes from
          // the order in Firestore, and the server's rate limits apply.
          checkoutUrl = await PaymentService.startOrderPayment(
            orderId: result.orderId,
            paymentMethod: method,
          );
        } on PaymentSessionException catch (e) {
          throw 'Your order ${result.invoiceId} was received, but the payment page could not be opened: ${e.message}';
        } catch (e) {
          throw 'Your order ${result.invoiceId} was received, but the payment page could not be opened. Please contact the shop to complete payment.';
        }

        // Open the payment INSIDE the app (WebView) instead of the phone's
        // browser. It pops with how the customer left the page.
        if (!mounted) return;
        final payResult = await Navigator.push<PaymentCheckoutResult>(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentCheckoutPage(
              checkoutUrl: checkoutUrl,
              title: method == 'gcash' ? 'Pay with GCash' : 'Pay with Maya',
            ),
          ),
        );

        // A WebView only knows which page it ended on, not whether money
        // moved. The server marks the order Paid in Firestore, so ask it.
        final paid = await _isOrderPaid(result.orderId);
        if (!mounted) return;

        if (paid || payResult == PaymentCheckoutResult.success) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderSuccessPage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Order ${result.invoiceId} is saved but not paid yet. '
                'You can find it under My Orders > To Pay.',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } else {
        // COD: nothing left to do but show success.
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderSuccessPage()),
          );
        }
      }
    } on OrderSubmissionException catch (e) {
      // Server refusals. The Firestore listener will ALSO pick up any
      // account change (e.g. isRestricted flipping to true after a
      // banned-device match), but these setStates make the screen react
      // immediately instead of waiting for the listener.
      if (e.code == 'RESTRICTED') {
        setState(() {
          _isAccountRestricted = true;
          _otpVerifiedThisSession = false;
        });
      } else if (e.code == 'BLOCKED') {
        setState(() => _isAccountBlocked = true);
      } else if (e.code == 'INVALID_SCHEDULE') {
        // The server rejected the chosen window (e.g. it slipped inside the
        // 3-hour lead): clear it so the customer must pick a valid one again.
        setState(() => _scheduleSlot = null);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Reads the order back from Firestore and says whether it is marked Paid.
  /// Rules allow the owner to read their own order. Any failure = "not paid
  /// as far as we can tell" (never a crash).
  Future<bool> _isOrderPaid(String orderId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      final data = doc.data();
      if (data == null) return false;
      final status = (data['paymentStatus'] ?? data['payment_status'] ?? '').toString();
      return status.toLowerCase() == 'paid';
    } catch (e) {
      debugPrint('DeliveryDetails: paid-check failed: $e');
      return false;
    }
  }

  Widget _buildAccountStatusBanner(bool isDark) {
    // Blocked wins over restricted: a blocked account can't be fixed by
    // phone verification, so showing the OTP message would mislead.
    if (_isAccountBlocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.withOpacity(0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.block, color: Colors.redAccent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Blocked',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isDark ? Colors.red[200] : Colors.red[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This account can no longer place orders. If you believe this is a mistake, please contact the shop.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.red[100] : Colors.red[800]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final untilPart = _restrictedUntilText != null ? ' $_restrictedUntilText' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _otpVerifiedThisSession ? 'Identity Verified' : 'Account Temporarily Restricted',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isDark ? Colors.amber[200] : Colors.amber[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _otpVerifiedThisSession
                      ? 'You\'ve verified your identity for this order. You can now place it normally.'
                      : 'This account is restricted$untilPart following a review of recent account activity. A verification code sent to your phone is required to place an order.',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.amber[100] : Colors.amber[800]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
      // SafeArea(bottom) keeps the last button above the phone's gesture/nav bar.
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isAccountBlocked || _isAccountRestricted) ...[
              _buildAccountStatusBanner(isDark),
              const SizedBox(height: 16),
            ],
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
                      _outsideDeliveryArea = false;
                      _outsideAreaMessage = '';
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
              title: 'Saved Addresses',
              children: [
                OutlinedButton.icon(
                  onPressed: _isApplyingSavedAddress ? null : _openAddressBook,
                  icon: _isApplyingSavedAddress
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bookmarks_outlined, size: 18),
                  label: Text(_savedAddresses.isEmpty
                      ? 'My Address (none saved yet)'
                      : 'My Address (${_savedAddresses.length} saved)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF4B400),
                    side: const BorderSide(color: Color(0xFFF4B400)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                if (_editingAddressId != null) ...[
                  Text(
                    'You are editing a saved address. Change the details below, then update it.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSavingAddress ? null : _updateEditedAddress,
                          style: _actionButtonStyle(const Color(0xFFF4B400)),
                          child: _isSavingAddress
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('UPDATE SAVED ADDRESS',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _isSavingAddress ? null : () => setState(() => _editingAddressId = null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ] else
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFFF4B400),
                    value: _saveAddressForLater &&
                        _savedAddresses.length < SavedAddressService.maxAddresses,
                    onChanged: _savedAddresses.length >= SavedAddressService.maxAddresses
                        ? null
                        : (val) => setState(() => _saveAddressForLater = val ?? false),
                    title: Text(
                      'Save this address for next time',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      _savedAddresses.length >= SavedAddressService.maxAddresses
                          ? 'Your address book is full (${SavedAddressService.maxAddresses}). Delete one to save another.'
                          : 'Saved to your account only, and shared with the website. Saved after your order is placed.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
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
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
                          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2)),
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
                        leading: const Icon(Icons.location_on_outlined, color: Color(0xFFF4B400), size: 20),
                        title: Text(s.displayName,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
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

            if (_outsideDeliveryArea)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_off, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Outside our delivery area',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87)),
                          const SizedBox(height: 2),
                          Text(_outsideAreaMessage,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[300] : Colors.grey[700])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (nearestBranchName.isNotEmpty && !_outsideDeliveryArea)
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
                onPressed: isCalculatingFee || isAutoFillingAddress ? null : _handleGetCurrentLocation,
                icon: (isCalculatingFee || isAutoFillingAddress)
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
              title: 'Delivery Date & Time',
              children: [
                DeliveryScheduleSection(
                  isScheduled: _scheduleEnabled,
                  date: _scheduleDate,
                  slot: _scheduleSlot,
                  onModeChanged: _onScheduleModeChanged,
                  onPickDate: _pickScheduleDate,
                  onSlotSelected: (slot) => setState(() => _scheduleSlot = slot),
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
                      // COD is disabled ONLY for gift orders — same rule as
                      // web and submit_order.php. Account restrictions apply
                      // to every payment method equally (phone OTP), so they
                      // don't change which methods are listed here.
                      enabled: !sendAsGift,
                      child: Text(
                        sendAsGift ? 'Cash on Delivery (unavailable for gifts)' : 'Cash on Delivery',
                        style: TextStyle(color: sendAsGift ? Colors.grey : null),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    if (val == 'cod' && sendAsGift) return;
                    setState(() => selectedPaymentMethod = val);
                  },
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
                  // null = disabled: a blocked account can't order.
                  onPressed: _isAccountBlocked ? null : _handlePlaceOrderTapped,
                  style: _actionButtonStyle(const Color(0xFFF4B400)),
                  child: Text(
                    _isAccountBlocked ? 'ORDERING UNAVAILABLE' : 'PLACE ORDER',
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                ),
              ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms, curve: Curves.easeOut)
          .slideX(begin: -0.15, end: 0, duration: 400.ms, curve: Curves.easeOut),
      ),
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
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12)),
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
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15)),
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
                  fontSize: 12, color: isDark ? Colors.grey[500] : Colors.grey[500], fontWeight: FontWeight.w600),
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
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
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
          // What the customer chose on the Delivery Date & Time card.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Delivery', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey)),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    _currentSchedule().summary,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 24, color: isDark ? Colors.white.withOpacity(0.1) : null),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
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