import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'delivery_details_page.dart';
import 'auth_page.dart';
import 'ai_assistant_page.dart';

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  String _selectedCategory = 'All';
  String _selectedBranchId =
      'all'; // Default to all branches to show content immediately
  final Map<String, int> _cart = {}; // productId -> quantity
  final Map<String, Map<String, dynamic>> _cartItemDetails = {};
  final Map<String, String> _branchNames = {}; // branchId -> name
  final Map<String, Map<String, dynamic>> _branchDetails =
      {}; // branchId -> full doc
  bool _showCheckoutOverlay = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadBranchDetails();
    _getCurrentLocation();
  }

  Future<void> _loadBranchDetails() async {
    InventoryData.getBranchesStream().listen((branches) {
      if (mounted) {
        setState(() {
          for (var b in branches) {
            _branchNames[b['id']] = b['name'] ?? 'Branch';
            _branchDetails[b['id']] = b;
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
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Fetch all branches
      final branches = await InventoryData.getBranches();

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
        });
      }
    } catch (e) {
      debugPrint('Error detecting location: $e');
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      String id = product['id'];
      _cart[id] = (_cart[id] ?? 0) + 1;
      _cartItemDetails[id] = product;
      _showCheckoutOverlay = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} added to cart'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'VIEW CART',
          onPressed: _showCart,
        ),
      ),
    );
  }

  void _showCart() {
    setState(() => _showCheckoutOverlay = true);
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

  void _initiateCheckout() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _showCheckoutOverlay = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in first to proceed with your checkout.'),
          backgroundColor: Color(0xFFF59E0B),
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AuthPage(
            returnAfterLogin: true,
            onLoginSuccess: () {
              _initiateCheckout();
            },
          ),
        ),
      );
      return;
    }

    List<Map<String, dynamic>> cartItems = [];
    _cart.forEach((id, qty) {
      final details = _cartItemDetails[id]!;
      cartItems.add({
        'id': id,
        'name': details['name'],
        'price': details['price'],
        'qty': qty,
        'image': details['image'],
        if (details.containsKey('branchId')) 'branchId': details['branchId'],
      });
    });

    setState(() => _showCheckoutOverlay = false);

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
                onPressed: _showCart,
              ),
              if (_cartItemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
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
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Branch Selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: InventoryData.getBranchesStream(),
              builder: (context, snapshot) {
                final branches = snapshot.data ?? [];

                // Ensure current selection is valid
                String effectiveValue = _selectedBranchId;
                if (effectiveValue != 'all' &&
                    !branches.any((b) => b['id'] == effectiveValue)) {
                  // If we have branches, maybe default to the first one instead of 'main_branch' if it's missing
                  if (branches.isNotEmpty && effectiveValue == 'main_branch') {
                    // Stay on main_branch if it's likely just loading
                  }
                }

                return DropdownButtonFormField<String>(
                  value: effectiveValue,
                  decoration: InputDecoration(
                    labelText: 'Viewing Branch',
                    prefixIcon: const Icon(Icons.storefront, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
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
                      InventoryData.selectedBranchId =
                          val == 'all' ? 'main_branch' : val;
                    }
                  },
                );
              },
            ),
          ),

          // Detection Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.location_on_outlined, size: 16),
                label: const Text('DETECT NEAREST BRANCH',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B79F2),
                  side: const BorderSide(color: Color(0xFF7B79F2)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _detectNearestBranch,
              ),
            ),
          ),

          // Category Selector
          SizedBox(
            height: 60,
            child: StreamBuilder<List<String>>(
              stream: InventoryData.globalCategoriesStream(),
              builder: (context, snapshot) {
                List<String> categories = ['All'];
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  // Deduplicate just in case
                  final uniqueCats = snapshot.data!.toSet().toList();
                  uniqueCats.sort();
                  categories.addAll(uniqueCats);
                } else if (snapshot.hasError) {
                  debugPrint('Category stream error: ${snapshot.error}');
                }

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedCategory = cat);
                        },
                        selectedColor: const Color(0xFFF59E0B),
                        labelStyle: TextStyle(
                          color: _selectedCategory == cat
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Product Grid
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
                  // Group by Name
                  Map<String, Map<String, dynamic>> grouped = {};
                  for (var p in rawProducts) {
                    String name = p['name'] ?? 'Unnamed';
                    if (!grouped.containsKey(name)) {
                      grouped[name] = {
                        ...p,
                        'branches': <Map<String, dynamic>>[
                          {'branchId': p['branchId'], 'stock': p['stock']}
                        ],
                        'total_stock': p['stock'] ?? 0,
                      };
                    } else {
                      grouped[name]!['branches'].add(
                          {'branchId': p['branchId'], 'stock': p['stock']});
                      grouped[name]!['total_stock'] =
                          (grouped[name]!['total_stock'] ?? 0) +
                              (p['stock'] ?? 0);
                      // Prefer image from branch with most stock or just use the first one
                      if ((p['stock'] ?? 0) > (grouped[name]!['stock'] ?? 0)) {
                        grouped[name]!['image'] =
                            p['image'] ?? grouped[name]!['image'];
                      }
                    }
                  }
                  products = grouped.values.toList();
                } else {
                  products = rawProducts;
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio:
                        0.55, // Increased vertical space for branch list
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) =>
                      _buildProductCard(products[index]),
                );
              },
            ),
          ),
        ],
      ),
      bottomSheet: _showCheckoutOverlay && _cartItemCount > 0
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_cartItemCount Items Selected',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '₱${_cartTotal.toStringAsFixed(2)}',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _initiateCheckout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('PROCEED TO CHECKOUT',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _showCheckoutOverlay = false),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
                  src:
                      'assets/models/Rose.glb', // Mapping everything to Rose for now as a demo
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
                      backgroundColor: Colors.white.withOpacity(0.8)),
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
                        Colors.black.withOpacity(0.5)
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

    return Card(
      elevation: isRecycled ? 2 : 0,
      shadowColor: isRecycled ? Colors.green.withOpacity(0.3) : Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRecycled
              ? Colors.green[200]!
              : (isDark ? Colors.white12 : Colors.black12),
          width: isRecycled ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Image.network(
                  product['image'] ??
                      'https://images.unsplash.com/photo-1526047932273-341f2a7631f9',
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
                if (isRecycled)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'RECYCLED',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                if (product['has3D'] == true)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _openARView(product),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.view_in_ar,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product['name'] ?? 'Flower',
                        style: GoogleFonts.cormorantGaramond(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isRecycled ? Colors.green[800] : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isRecycled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'ECO-SALVAGED',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 6,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (isRecycled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      'This bouquet is composed of salvaged flowers (Mixed varieties). Limited offer: Only good for two days.',
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontStyle: FontStyle.italic,
                        color: Colors.green[700],
                        height: 1.2,
                      ),
                    ),
                  ),
                Text(
                  '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isRecycled
                        ? Colors.green[700]
                        : const Color(0xFFF59E0B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if (_selectedBranchId == 'all' &&
                    product.containsKey('branches'))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AVAILABLE AT:',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 0.5),
                      ),
                      ...(product['branches'] as List).map((b) {
                        final bName = _branchNames[b['branchId']] ?? 'Branch';
                        final stock = b['stock'] ?? 0;
                        if (stock <= 0) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  bName,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$stock left',
                                style: TextStyle(
                                    fontSize: 9,
                                    color:
                                        stock < 10 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      if (_currentPosition != null)
                        Builder(
                          builder: (context) {
                            // Find nearest branch among available
                            double minDistance = double.infinity;
                            for (var b in (product['branches'] as List)) {
                              final details = _branchDetails[b['branchId']];
                              if (details != null && (b['stock'] ?? 0) > 0) {
                                double d = Geolocator.distanceBetween(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                        details['latitude']?.toDouble() ?? 0.0,
                                        details['longitude']?.toDouble() ??
                                            0.0) /
                                    1000;
                                // Apply road adjustment factor (1.8x for Philippine roads)
                                d = d * 1.8;
                                if (d < minDistance) minDistance = d;
                              }
                            }
                            if (minDistance == double.infinity)
                              return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Nearest: ~${minDistance.toStringAsFixed(1)} km',
                                style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.pink[300],
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                    ],
                  )
                else if (_selectedBranchId != 'all')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Branch: ${_branchNames[product['branchId']] ?? 'Main Branch'}',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.blueGrey),
                      ),
                      Text(
                        'Stock: ${product['stock'] ?? 0} units',
                        style: TextStyle(
                            fontSize: 10,
                            color: (product['stock'] ?? 0) < 10
                                ? Colors.red
                                : Colors.grey[600],
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        (product['total_stock'] ?? product['stock'] ?? 0) > 0
                            ? () => _addToCart(product)
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B79F2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      (product['total_stock'] ?? product['stock'] ?? 0) > 0
                          ? 'ADD TO CART'
                          : 'OUT OF STOCK',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
