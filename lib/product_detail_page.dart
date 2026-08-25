import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';
import 'flora_chat_page.dart';

/// Shopee-style product detail page. Opened by tapping a product card on
/// the Shop Category screen. Cart/checkout logic itself stays owned by
/// ProductCatalogPage (single source of truth for `_cart`) -- this page
/// just calls back into it via the two required callbacks below, the same
/// way the quick-add button on the card already does.
class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, String> branchNames;
  final void Function(Map<String, dynamic> product) onAddToCart;
  final void Function(Map<String, dynamic> product) onBuyNow;

  const ProductDetailPage({
    super.key,
    required this.product,
    required this.branchNames,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  // Whether the current logged-in user is eligible to rate this product --
  // true only if they have a DELIVERED order containing it AND haven't
  // already rated it. Resolved once via a Future in initState since it
  // requires two async Firestore checks.
  late Future<bool> _canRateFuture;

  @override
  void initState() {
    super.initState();
    _canRateFuture = _checkRatingEligibility();
  }

  Future<bool> _checkRatingEligibility() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    final productId = widget.product['id'];
    if (productId == null) return false;

    final received = await InventoryData.hasUserReceivedProduct(
      userId: user.uid,
      productId: productId,
    );
    if (!received) return false;

    final alreadyRated = await InventoryData.hasUserAlreadyRated(
      productId: productId,
      userId: user.uid,
    );
    return !alreadyRated;
  }

  void _refreshEligibility() {
    setState(() {
      _canRateFuture = _checkRatingEligibility();
    });
  }

  void _openRatingDialog() {
    int selectedStars = 5;
    final reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Rate this product'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final starIndex = i + 1;
                      return IconButton(
                        icon: Icon(
                          starIndex <= selectedStars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFF59E0B),
                          size: 32,
                        ),
                        onPressed: () =>
                            setDialogState(() => selectedStars = starIndex),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reviewController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Share your experience (optional)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    Navigator.pop(dialogContext);
                    try {
                      await InventoryData.submitProductRating(
                        productId: widget.product['id'],
                        userId: user.uid,
                        userName: user.displayName?.isNotEmpty == true
                            ? user.displayName!
                            : 'Verified Buyer',
                        rating: selectedStars,
                        review: reviewController.text,
                      );
                      if (mounted) {
                        _refreshEligibility();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thanks for rating! 🌸'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to submit: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRecycled = product['name'] == 'Recycled Bouquet';
    final totalStock = product['total_stock'] ?? product['stock'] ?? 0;
    final inStock = totalStock > 0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            foregroundColor: isDark ? Colors.white : Colors.black,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    (product['image'] as String?)?.isNotEmpty == true
                        ? product['image']
                        : 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF3F4F6),
                      child: Icon(Icons.local_florist_outlined,
                          size: 64,
                          color: isDark ? Colors.grey[700] : Colors.grey[400]),
                    ),
                  ),
                  if (!inStock)
                    Container(color: Colors.black.withValues(alpha: 0.4)),
                  if (!inStock)
                    const Center(
                      child: Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isRecycled)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('RECYCLED',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ),
                  Text(
                    product['name'] ?? 'Flower',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isRecycled
                          ? Colors.green[800]
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      color: isRecycled
                          ? Colors.green[700]
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Live star rating summary, computed from real
                  // product_ratings docs -- never a fabricated number.
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: InventoryData.getProductRatingsStream(
                        product['id'] ?? ''),
                    builder: (context, snapshot) {
                      final ratings = snapshot.data ?? [];
                      if (ratings.isEmpty) {
                        return Text(
                          'No ratings yet -- be the first!',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600]),
                        );
                      }
                      final avg = ratings.fold<int>(
                          0, (sum, r) => sum + ((r['rating'] ?? 0) as int)) /
                          ratings.length;
                      return Row(
                        children: [
                          ...List.generate(5, (i) {
                            final filled = i < avg.round();
                            return Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: const Color(0xFFF59E0B),
                              size: 18,
                            );
                          }),
                          const SizedBox(width: 6),
                          Text(
                            '${avg.toStringAsFixed(1)} (${ratings.length} rating${ratings.length == 1 ? '' : 's'})',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700]),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  Text('Description',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 6),
                  Text(
                    (product['description'] as String?)?.isNotEmpty == true
                        ? product['description']
                        : 'A beautiful addition to any occasion.',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark ? Colors.grey[300] : Colors.grey[700]),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Availability -- this is where the branch/stock detail
                  // trimmed off the compact Shopee-style cards lives now,
                  // instead of being lost entirely.
                  Text('Availability',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 8),
                  if (product.containsKey('branches'))
                    ...((product['branches'] as List)
                        .where((b) => (b['stock'] ?? 0) > 0)
                        .map((b) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.storefront,
                                size: 16, color: Color(0xFF7B79F2)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.branchNames[b['branchId']] ?? 'Branch',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700]),
                              ),
                            ),
                            Text(
                              '${b['stock']} in stock',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (b['stock'] ?? 0) < 10
                                      ? Colors.orange[700]
                                      : Colors.green[600]),
                            ),
                          ],
                        ),
                      );
                    }))
                  else
                    Row(
                      children: [
                        const Icon(Icons.storefront,
                            size: 16, color: Color(0xFF7B79F2)),
                        const SizedBox(width: 8),
                        Text(
                          inStock
                              ? '${product['stock'] ?? 0} in stock'
                              : 'Currently unavailable',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: !inStock
                                ? Colors.red
                                : (isDark
                                ? Colors.grey[300]
                                : Colors.grey[700]),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Reviews list + the "Rate this product" CTA, gated by
                  // whether this specific user has actually received it.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reviews',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87)),
                      FutureBuilder<bool>(
                        future: _canRateFuture,
                        builder: (context, snapshot) {
                          if (snapshot.data != true) {
                            return const SizedBox.shrink();
                          }
                          return TextButton.icon(
                            onPressed: _openRatingDialog,
                            icon: const Icon(Icons.star_rounded,
                                size: 16, color: Color(0xFFF59E0B)),
                            label: const Text('Rate this product',
                                style: TextStyle(
                                    color: Color(0xFFF59E0B), fontSize: 12)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: InventoryData.getProductRatingsStream(
                        product['id'] ?? ''),
                    builder: (context, snapshot) {
                      final ratings = snapshot.data ?? [];
                      if (ratings.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Only customers who have received this product can leave a review.',
                            style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600]),
                          ),
                        );
                      }
                      return Column(
                        children: ratings.map((r) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      r['userName'] ?? 'Verified Buyer',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87),
                                    ),
                                    const SizedBox(width: 8),
                                    ...List.generate(5, (i) {
                                      return Icon(
                                        i < ((r['rating'] ?? 0) as int)
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: const Color(0xFFF59E0B),
                                        size: 12,
                                      );
                                    }),
                                  ],
                                ),
                                if ((r['review'] as String?)
                                    ?.isNotEmpty ==
                                    true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      r['review'],
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: isDark
                                              ? Colors.grey[300]
                                              : Colors.grey[700]),
                                    ),
                                  ),
                              ],
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
        ],
      ),

      // Bottom action bar: Ask Flora / Add to Cart / Buy Now -- matching
      // the 3-button pattern from the reference screenshot.
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ask Flora -- narrow icon+label column, muted style, matches
            // the leftmost "Chat Now" slot in the reference screenshot.
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => FloraChatPage(focusedProduct: product)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.support_agent,
                        color: Color(0xFFF59E0B), size: 22),
                    const SizedBox(height: 2),
                    Text('Ask Flora',
                        style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700])),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: inStock
                    ? () => widget.onAddToCart(product)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B79F2),
                  side: const BorderSide(color: Color(0xFF7B79F2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Add to Cart',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: inStock ? () => widget.onBuyNow(product) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  inStock ? 'Buy Now' : 'Out of Stock',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}