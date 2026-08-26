import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'delivery_details_page.dart';
import 'auth_page.dart';
import 'ai_assistant_page.dart';
import 'flora_chat_page.dart';
import 'product_detail_page.dart';

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage>
    with SingleTickerProviderStateMixin {
  String _selectedCategory = 'All';
  String _selectedBranchId = 'all';
  final Map<String, int> _cart = {};
  final Map<String, Map<String, dynamic>> _cartItemDetails = {};
  final Map<String, String> _branchNames = {};
  final Map<String, Map<String, dynamic>> _branchDetails = {};
  Position? _currentPosition;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final AnimationController _pageFadeController;
  late final Animation<double> _pageFadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadBranchDetails();
    _getCurrentLocation();

    _pageFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pageFadeAnimation = CurvedAnimation(
      parent: _pageFadeController,
      curve: Curves.easeOut,
    );
    _pageFadeController.forward();
  }

  @override
  void dispose() {
    _pageFadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBranchDetails() async {
    InventoryData.getBranchesStream().listen((branches) {
      if (mounted) {
        setState(() {
          for (var b in branches) {
            _branchNames[b['id']] = b['name'] ?? 'Branch';
            _branchDetails[b['id']] = b;
          }
          final realIds = branches.map((b) => b['id']).toSet();
          if (branches.isNotEmpty &&
              !realIds.contains(InventoryData.selectedBranchId)) {
            InventoryData.selectedBranchId = branches.first['id'];
          }
        });
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _detectNearestBranch() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location services are turned off. Please enable them to detect your nearest branch.'),
            backgroundColor: Color(0xFFDC3545),
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission denied. We need it to find your nearest branch.'),
              backgroundColor: Color(0xFFDC3545),
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permission is permanently denied. Enable it in your phone\'s app settings.'),
            backgroundColor: Color(0xFFDC3545),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final branches = await InventoryData.getBranches();

      if (branches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No branches are currently set up to detect.')),
          );
        }
        return;
      }

      String? nearestId;
      double minDistance = double.infinity;

      for (var b in branches) {
        double lat = b['latitude'] ?? 0.0;
        double lng = b['longitude'] ?? 0.0;

        double distance = Geolocator.distanceBetween(
            position.latitude, position.longitude, lat, lng);

        if (distance < minDistance) {
          minDistance = distance;
          nearestId = b['id'];
        }
      }

      if (nearestId != null) {
        setState(() {
          InventoryData.selectedBranchId = nearestId!;
          _selectedBranchId = nearestId;
        });

        final branchName = _branchNames[nearestId] ?? 'your nearest branch';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Now viewing $branchName'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error detecting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not detect your location: $e')),
        );
      }
    }
  }

  void _requireLogin(VoidCallback onSuccess) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      onSuccess();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please log in first to add items to your cart.'),
        backgroundColor: Color(0xFFF59E0B),
        duration: Duration(seconds: 3),
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AuthPage(
          returnAfterLogin: true,
          onLoginSuccess: onSuccess,
        ),
      ),
    );
  }

  void _addToCart(Map<String, dynamic> product) {
    _requireLogin(() {
      setState(() {
        String id = product['id'];
        _cart[id] = (_cart[id] ?? 0) + 1;
        _cartItemDetails[id] = product;
      });
      // No snackbar here anymore — the persistent mini-cart bar at the
      // bottom of the screen already shows "N items in cart / View Cart"
      // the instant _cartItemCount goes above 0, so a snackbar saying
      // the same thing a moment later was pure duplication.
    });
  }

  void _buyNow(Map<String, dynamic> product) {
    _requireLogin(() {
      final price = (product['price'] ?? 0).toDouble();
      final cartItems = [
        {
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'qty': 1,
          'image': product['image'],
          if (product.containsKey('branchId')) 'branchId': product['branchId'],
        }
      ];

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeliveryDetailsPage(
            cartItems: cartItems,
            cartTotal: price,
            occasion: 'Standard Order',
          ),
        ),
      );
    });
  }

  void _changeQuantity(String id, int delta) {
    setState(() {
      final current = _cart[id] ?? 0;
      final next = current + delta;
      if (next <= 0) {
        _cart.remove(id);
        _cartItemDetails.remove(id);
      } else {
        _cart[id] = next;
      }
    });
  }

  void _removeFromCart(String id) {
    setState(() {
      _cart.remove(id);
      _cartItemDetails.remove(id);
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _cartItemDetails.clear();
    });
  }

  double get _cartTotal {
    double total = 0;
    _cart.forEach((id, qty) {
      total += (_cartItemDetails[id]?['price'] ?? 0) * qty;
    });
    return total;
  }

  int get _cartItemCount {
    return _cart.values.fold(0, (sum, qty) => sum + qty);
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;
                final ids = _cart.keys.toList();

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[700] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Cart',
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            if (ids.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  _clearCart();
                                  setModalState(() {});
                                },
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ids.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 64,
                                  color: isDark
                                      ? Colors.grey[700]
                                      : Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                'Your cart is empty',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add some flowers to get started 🌸',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                            : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: ids.length,
                          separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final id = ids[index];
                            final details = _cartItemDetails[id]!;
                            final qty = _cart[id] ?? 0;
                            final price =
                            (details['price'] ?? 0).toDouble();

                            return Padding(
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                    BorderRadius.circular(10),
                                    child: Image.network(
                                      details['image'] ?? '',
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                            width: 60,
                                            height: 60,
                                            color: isDark
                                                ? const Color(0xFF2A2A2A)
                                                : Colors.grey[200],
                                            child: const Icon(
                                                Icons.local_florist,
                                                color: Colors.grey),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          details['name'] ?? 'Item',
                                          maxLines: 1,
                                          overflow:
                                          TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₱${price.toStringAsFixed(2)} each',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: isDark
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          borderRadius:
                                          BorderRadius.circular(20),
                                          onTap: () {
                                            _changeQuantity(id, -1);
                                            setModalState(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(Icons.remove,
                                                size: 16),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 22,
                                          child: Text(
                                            '$qty',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontWeight:
                                              FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius:
                                          BorderRadius.circular(20),
                                          onTap: () {
                                            _changeQuantity(id, 1);
                                            setModalState(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child:
                                            Icon(Icons.add, size: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 20,
                                        color: Colors.red[300]),
                                    onPressed: () {
                                      _removeFromCart(id);
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (ids.isNotEmpty)
                        Container(
                          padding: EdgeInsets.fromLTRB(20, 16, 20,
                              MediaQuery.of(context).padding.bottom + 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF262626)
                                : const Color(0xFFF9FAFB),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total ($_cartItemCount item${_cartItemCount == 1 ? '' : 's'})',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '₱${_cartTotal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color:
                                      isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    _initiateCheckout();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    'PROCEED TO CHECKOUT',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _initiateCheckout() {
    _requireLogin(() {
      List<Map<String, dynamic>> cartItems = [];
      _cart.forEach((id, qty) {
        final details = _cartItemDetails[id]!;
        cartItems.add({
          'id': id,
          'name': details['name'],
          'price': details['price'],
          'qty': qty,
          'image': details['image'],
          if (details.containsKey('branchId'))
            'branchId': details['branchId'],
        });
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeliveryDetailsPage(
            cartItems: cartItems,
            cartTotal: _cartTotal,
            occasion: 'Standard Order',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'FLOWER CATALOG',
          style: GoogleFonts.cormorantGaramond(
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B)),
            tooltip: 'AI Stylist & Matchmaker',
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AIAssistantPage()));
            },
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'View Cart',
                onPressed: _openCartSheet,
              ),
              if (_cartItemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$_cartItemCount',
                        style:
                        const TextStyle(color: Colors.white, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _pageFadeAnimation,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: InventoryData.getBranchesStream(),
                      builder: (context, snapshot) {
                        final branches = snapshot.data ?? [];
                        final realIds = branches.map((b) => b['id']).toSet();
                        String effectiveValue = (_selectedBranchId == 'all' ||
                            realIds.contains(_selectedBranchId))
                            ? _selectedBranchId
                            : 'all';

                        return Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: effectiveValue,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(16),
                              padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                              icon: const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Icon(Icons.keyboard_arrow_down_rounded,
                                    size: 20),
                              ),
                              selectedItemBuilder: (context) {
                                final items = [
                                  'all',
                                  ...branches.map((b) => b['id'] as String)
                                ];
                                return items.map((id) {
                                  final label = id == 'all'
                                      ? 'All Branches'
                                      : (_branchNames[id] ?? 'Branch');
                                  return Padding(
                                    padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.storefront,
                                            size: 16,
                                            color: Color(0xFF7B79F2)),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            label,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList();
                              },
                              items: [
                                const DropdownMenuItem(
                                    value: 'all', child: Text('All Branches')),
                                ...branches.map((b) => DropdownMenuItem(
                                  value: b['id'],
                                  child: Text(b['name'] ?? 'Branch'),
                                )),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedBranchId = val);
                                  InventoryData.selectedBranchId = val == 'all'
                                      ? (branches.isNotEmpty
                                      ? branches.first['id']
                                      : InventoryData.selectedBranchId)
                                      : val;
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B79F2).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.my_location_rounded,
                          color: Color(0xFF7B79F2), size: 20),
                      tooltip: 'Detect nearest branch',
                      onPressed: _detectNearestBranch,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search flowers, gifts, chocolates...',
                  hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[500] : Colors.grey[500]),
                  prefixIcon: Icon(Icons.search,
                      size: 20, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                  filled: true,
                  fillColor:
                  isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            SizedBox(
              height: 96,
              child: StreamBuilder<List<String>>(
                stream: InventoryData.globalCategoriesStream(),
                builder: (context, snapshot) {
                  List<String> categories = ['All'];
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    final uniqueCats = snapshot.data!.toSet().toList();
                    uniqueCats.sort();
                    categories.addAll(uniqueCats);
                  } else if (snapshot.hasError) {
                    debugPrint('Category stream error: ${snapshot.error}');
                  }

                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final selected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 62,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFF59E0B)
                                        : (isDark
                                        ? const Color(0xFF262626)
                                        : const Color(0xFFF5F5F5)),
                                    shape: BoxShape.circle,
                                    border: selected
                                        ? Border.all(
                                        color: const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.4),
                                        width: 3)
                                        : null,
                                  ),
                                  child: Icon(
                                    _iconForCategory(cat),
                                    color: selected
                                        ? Colors.white
                                        : (isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[700]),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: selected
                                        ? const Color(0xFFF59E0B)
                                        : (isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                key: ValueKey('$_selectedBranchId-$_selectedCategory'),
                stream: InventoryData.inventoryStream(
                  branchId: _selectedBranchId,
                  category: _selectedCategory,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    debugPrint('Inventory Error: ${snapshot.error}');
                    return Center(
                        child: Text('Error loading catalog: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No products found 🌸'));
                  }

                  final rawProducts = snapshot.data!;
                  List<Map<String, dynamic>> products = [];

                  if (_selectedBranchId == 'all') {
                    Map<String, Map<String, dynamic>> grouped = {};
                    Map<String, int> bestImageStock = {};

                    for (var p in rawProducts) {
                      String name = p['name'] ?? 'Unnamed';
                      final pStock = (p['stock'] ?? 0) as int;
                      if (!grouped.containsKey(name)) {
                        grouped[name] = {
                          ...p,
                          'branches': <Map<String, dynamic>>[
                            {'branchId': p['branchId'], 'stock': p['stock']}
                          ],
                          'total_stock': pStock,
                        };
                        bestImageStock[name] = pStock;
                      } else {
                        grouped[name]!['branches'].add(
                            {'branchId': p['branchId'], 'stock': p['stock']});
                        grouped[name]!['total_stock'] =
                            (grouped[name]!['total_stock'] ?? 0) + pStock;
                        if (pStock > (bestImageStock[name] ?? 0)) {
                          bestImageStock[name] = pStock;
                          grouped[name]!['image'] =
                              p['image'] ?? grouped[name]!['image'];
                        }
                      }
                    }
                    products = grouped.values.toList();
                  } else {
                    products = rawProducts;
                  }

                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    products = products
                        .where((p) => (p['name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(q))
                        .toList();
                  }

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48,
                              color: isDark ? Colors.grey[700] : Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'No matches for "$_searchQuery"',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + 76 + (_cartItemCount > 0 ? 80 : 0),
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.6,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) => _FadeSlideIn(
                      delay: Duration(
                          milliseconds: (index * 40).clamp(0, 400)),
                      child: _buildProductCard(products[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _cartItemCount > 0
          ? Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: InkWell(
          onTap: _openCartSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                  blurRadius: 14,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shopping_bag_outlined,
                      color: Color(0xFFF59E0B), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_cartItemCount item${_cartItemCount == 1 ? '' : 's'} in cart',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '₱${_cartTotal.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'View Cart',
                  style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Color(0xFFF59E0B), size: 20),
              ],
            ),
          ),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        // Reduced from 72 — just enough clearance to clear the cart bar's
        // own height without leaving a visible gap floating above it.
        padding: EdgeInsets.only(
          bottom: _cartItemCount > 0
              ? 58 + MediaQuery.of(context).padding.bottom
              : 0,
        ),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FloraChatPage()),
            );
          },
          backgroundColor: const Color(0xFFF59E0B),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.support_agent),
          label: const Text('Ask Flora',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _openARView(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ModelViewer(
                  src: 'assets/models/Rose.glb',
                  alt: product['name'],
                  ar: true,
                  autoRotate: true,
                  cameraControls: true,
                  backgroundColor: const Color(0xFFF5F5F5),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5)
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Text(
                    product['name'] ?? 'Flower',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRecycled = product['name'] == 'Recycled Bouquet';
    final totalStock = product['total_stock'] ?? product['stock'] ?? 0;
    final inStock = totalStock > 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              product: product,
              branchNames: _branchNames,
              onAddToCart: _addToCart,
              onBuyNow: _buyNow,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: isRecycled
              ? Border.all(color: Colors.green[200]!, width: 1.5)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(
                    colorFilter: inStock
                        ? const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply)
                        : ColorFilter.mode(
                        Colors.grey.withValues(alpha: 0.6),
                        BlendMode.saturation),
                    child: Image.network(
                      (product['image'] as String?)?.isNotEmpty == true
                          ? product['image']
                          : 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF3F4F6),
                        child: Icon(Icons.local_florist_outlined,
                            size: 32,
                            color: isDark ? Colors.grey[700] : Colors.grey[400]),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFF3F4F6),
                        );
                      },
                    ),
                  ),
                  if (!inStock)
                    Container(color: Colors.black.withValues(alpha: 0.35)),
                  if (!inStock)
                    const Center(
                      child: Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5),
                      ),
                    ),
                  if (isRecycled)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RECYCLED',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  if (product['has3D'] == true)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _openARView(product),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.view_in_ar,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: inStock
                          ? const Color(0xFF7B79F2)
                          : Colors.grey[400],
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: inStock ? () => _addToCart(product) : null,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.add_shopping_cart_rounded,
                              color: Colors.white, size: 17),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? 'Flower',
                    style: GoogleFonts.cormorantGaramond(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isRecycled
                          ? Colors.green[800]
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isRecycled
                          ? Colors.green[700]
                          : const Color(0xFFF59E0B),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_selectedBranchId == 'all' &&
                      product.containsKey('branches'))
                    Text(
                      'Available at ${(product['branches'] as List).where((b) => (b['stock'] ?? 0) > 0).length} branch(es)',
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.grey[500] : Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (_selectedBranchId != 'all')
                    Text(
                      inStock
                          ? '${product['stock'] ?? 0} in stock'
                          : 'Currently unavailable',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: !inStock
                            ? Colors.red
                            : ((product['stock'] ?? 0) < 10
                            ? Colors.orange[700]
                            : Colors.green[600]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeSlideIn({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

IconData _iconForCategory(String category) {
  switch (category) {
    case 'All':
      return Icons.grid_view_rounded;
    case 'Flowers':
      return Icons.local_florist_rounded;
    case 'Bouquets':
      return Icons.local_florist_outlined;
    case 'Chocolates':
      return Icons.cake_rounded;
    case 'Stuffed Toys':
      return Icons.toys_rounded;
    case 'Wines':
      return Icons.wine_bar_rounded;
    case 'Gifts':
      return Icons.card_giftcard_rounded;
    case 'Balloons':
      return Icons.celebration_rounded;
    default:
      return Icons.sell_rounded;
  }
}