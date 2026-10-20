import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'inventory_data.dart';

class OrderTrackingPage extends StatefulWidget {
  final String customerId;
  /// Which tab to open: 0 = To Pay, 1 = To Ship, 2 = To Deliver, 3 = To Rate.
  /// This is also the left-to-right order of the tab bar. Default 0 = To Pay.
  final int initialTabIndex;

  const OrderTrackingPage({
    super.key,
    required this.customerId,
    this.initialTabIndex = 0,
  });

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

enum OrderBucket { toPay, toShip, toDeliver, toRate }

/// THE one place that decides which tab an order belongs in. The profile
/// page's badge counts and the tabs below both call this, so they can never
/// disagree.
///
///   pending                      -> To Pay   (nothing has started yet)
///   pending but already PAID     -> To Ship  (online payment went through)
///   processing / paid / other    -> To Ship  (the shop is preparing it)
///   shipped / out for delivery /
///   in transit                   -> To Deliver
///   delivered / completed        -> To Rate
///   cancelled                    -> none (null = shown nowhere)
OrderBucket? orderBucketFor(Map<String, dynamic> order) {
  // 'IN TRANSIT', 'in transit' and 'in_transit' all become 'in_transit'.
  final status = (order['status'] ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_');
  final paymentStatus =
  (order['paymentStatus'] ?? order['payment_status'] ?? '').toString().toLowerCase();

  if (status == 'cancelled') return null;
  if (status == 'delivered' || status == 'completed') return OrderBucket.toRate;
  if (status == 'shipped' || status == 'out_for_delivery' || status == 'in_transit') {
    return OrderBucket.toDeliver;
  }

  if (status == 'pending' || status.isEmpty) {
    // A paid order has nothing left to pay, so it goes straight to To Ship.
    return paymentStatus == 'paid' ? OrderBucket.toShip : OrderBucket.toPay;
  }

  // processing, paid, confirmed, ... = the shop is working on it.
  return OrderBucket.toShip;
}

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      // clamp keeps a bad number from crashing the screen.
      initialIndex: widget.initialTabIndex.clamp(0, 3).toInt(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  OrderBucket? _bucketFor(Map<String, dynamic> order) => orderBucketFor(order);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MY ORDERS',
            style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFFF4B400),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFF4B400),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'To Pay'),
            Tab(text: 'To Ship'),
            Tab(text: 'To Deliver'),
            Tab(text: 'To Rate'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('user_id', isEqualTo: widget.customerId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFF4B400)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load orders: ${snapshot.error}'));
          }

          final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? []);
          docs.sort((a, b) {
            final aTime = (a.data() as Map)['createdAt'];
            final bTime = (b.data() as Map)['createdAt'];
            if (aTime is! Timestamp || bTime is! Timestamp) return 0;
            return bTime.compareTo(aTime);
          });

          final Map<OrderBucket, List<QueryDocumentSnapshot>> buckets = {
            OrderBucket.toPay: [],
            OrderBucket.toShip: [],
            OrderBucket.toDeliver: [],
            OrderBucket.toRate: [],
          };

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final bucket = _bucketFor(data);
            if (bucket != null) buckets[bucket]!.add(doc);
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Same order as the tab bar above: To Pay, To Ship, To Deliver, To Rate.
              _OrderList(docs: buckets[OrderBucket.toPay]!, bucket: OrderBucket.toPay),
              _OrderList(docs: buckets[OrderBucket.toShip]!, bucket: OrderBucket.toShip),
              _OrderList(
                  docs: buckets[OrderBucket.toDeliver]!, bucket: OrderBucket.toDeliver),
              _ToRateList(
                docs: buckets[OrderBucket.toRate]!,
                customerId: widget.customerId,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final OrderBucket bucket;

  const _OrderList({required this.docs, required this.bucket});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return _EmptyState(bucket: bucket);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) => _OrderCard(
        data: docs[index].data() as Map<String, dynamic>,
        // doc.id is the real Firestore id the cancel button needs.
        orderId: docs[index].id,
        // Only orders still waiting to be paid or shipped can be cancelled.
        allowCancel: bucket == OrderBucket.toShip || bucket == OrderBucket.toPay,
      ),
    );
  }
}

/// "To Rate" tab. NOT grouped by order: every delivered product that still
/// needs a rating gets its own card, even when several were bought together.
///
/// It listens (live) to this customer's ratings in `product_ratings`, so the
/// moment a rating is saved that product's card disappears by itself.
class _ToRateList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs; // delivered orders, newest first
  final String customerId;

  const _ToRateList({required this.docs, required this.customerId});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const _EmptyState(bucket: OrderBucket.toRate);

    return StreamBuilder<QuerySnapshot>(
      // ONE query for all of this customer's ratings (cheaper than one query
      // per product, and it needs no special index).
      stream: FirebaseFirestore.instance
          .collection('product_ratings')
          .where('userId', isEqualTo: customerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFF4B400)));
        }

        // Which (order, product) pairs are already rated?
        //  - new ratings carry an orderId  -> key "orderId_productId"
        //  - older ratings have no orderId -> remembered by productId only
        // If the read ever fails we simply treat everything as "not rated yet"
        // so the customer can still see their items (fails toward showing).
        final ratedKeys = <String>{};
        final legacyRatedProducts = <String>{};
        for (final d in snapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
          final m = d.data() as Map<String, dynamic>;
          final pid = (m['productId'] ?? '').toString();
          final oid = (m['orderId'] ?? '').toString();
          if (oid.isEmpty) {
            legacyRatedProducts.add(pid);
          } else {
            ratedKeys.add('${oid}_$pid');
          }
        }

        // Flatten: order -> its items -> one entry per unrated item.
        final entries = <_RateEntry>[];
        for (final doc in docs) {
          final order = doc.data() as Map<String, dynamic>;
          final items = (order['items'] as List?) ?? [];
          for (final raw in items) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final productId = (item['id'] ?? item['productId'])?.toString();
            if (productId == null || productId.isEmpty) continue;
            if (ratedKeys.contains('${doc.id}_$productId')) continue;
            if (legacyRatedProducts.contains(productId)) continue;
            entries.add(_RateEntry(
                orderId: doc.id, order: order, item: item, productId: productId));
          }
        }

        if (entries.isEmpty) return const _EmptyState(bucket: OrderBucket.toRate);

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _RateItemCard(entry: entries[index], customerId: customerId),
        );
      },
    );
  }
}

/// One product from one delivered order, waiting for a rating.
class _RateEntry {
  final String orderId;
  final Map<String, dynamic> order;
  final Map<String, dynamic> item;
  final String productId;

  const _RateEntry({
    required this.orderId,
    required this.order,
    required this.item,
    required this.productId,
  });
}

class _RateItemCard extends StatelessWidget {
  final _RateEntry entry;
  final String customerId;

  const _RateItemCard({required this.entry, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFF4B400);

    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor =
    isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15);
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.grey[400] : Colors.grey[600];

    final invoice = entry.order['invoiceId'] ??
        entry.order['id'] ??
        (entry.orderId.length > 8
            ? entry.orderId.substring(0, 8).toUpperCase()
            : entry.orderId);
    final name = (entry.item['name'] ?? 'Item').toString();
    final qty = num.tryParse((entry.item['qty'] ?? entry.item['quantity'] ?? 1).toString()) ?? 1;
    final price = num.tryParse((entry.item['price'] ?? 0).toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #$invoice',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12, color: secondaryText)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: amber.withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('DELIVERED',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark ? amber : const Color(0xFFB8860B))),
              ),
            ],
          ),
          Divider(height: 20, color: borderColor),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The product's own photo.
              _ItemPhoto(
                image: (entry.item['image'] ?? entry.item['imageUrl'])?.toString(),
                productId: entry.productId,
                branchId: (entry.item['branchId'] ?? entry.order['branchId'])?.toString(),
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: primaryText)),
                    const SizedBox(height: 2),
                    Text('Qty: $qty',
                        style: TextStyle(fontSize: 12, color: secondaryText)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('₱${(price * qty).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _RateItemDialog(
                  orderId: entry.orderId,
                  productId: entry.productId,
                  productName: name,
                  customerId: customerId,
                ),
              ),
              icon: const Icon(Icons.star_rounded, size: 18),
              label: const Text('RATE THIS ITEM'),
              style: ElevatedButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: Colors.black, // dark text on the amber button
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Square product photo for a To Rate card.
///
/// 1. Uses the image saved on the order item (web link, app link or base64).
/// 2. If the order has none (older orders), looks the product up in the
///    branch inventory and uses its image.
/// 3. If there is still nothing, shows a flower icon instead of a blank box.
class _ItemPhoto extends StatefulWidget {
  final String? image;
  final String productId;
  final String? branchId;
  final bool isDark;

  const _ItemPhoto({
    required this.image,
    required this.productId,
    required this.branchId,
    required this.isDark,
  });

  @override
  State<_ItemPhoto> createState() => _ItemPhotoState();
}

class _ItemPhotoState extends State<_ItemPhoto> {
  // Created ONCE (initState), so scrolling the list does not re-query.
  late final Future<String?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _resolveImage();
  }

  Future<String?> _resolveImage() async {
    final saved = (widget.image ?? '').trim();
    if (saved.isNotEmpty && saved.toLowerCase() != 'null') return saved;

    final branch = widget.branchId;
    if (branch == null || branch.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branch)
          .collection('inventory')
          .doc(widget.productId)
          .get();
      final img = (snap.data()?['image'] ?? '').toString().trim();
      return img.isEmpty ? null : img;
    } catch (_) {
      return null; // photo is optional - never break the card over it
    }
  }

  Widget _placeholder() => Container(
    color: widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F1E6),
    child: const Center(
        child: Icon(Icons.local_florist_outlined, color: Color(0xFFF4B400), size: 28)),
  );

  Widget _buildImage(String src) {
    try {
      if (src.startsWith('http://') || src.startsWith('https://')) {
        return Image.network(src,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
      }
      if (src.startsWith('data:image') || src.contains(';base64,')) {
        return Image.memory(base64Decode(src.split(',').last),
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
      }
    } catch (_) {}
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        height: 64,
        child: FutureBuilder<String?>(
          future: _imageFuture,
          builder: (context, snap) {
            final src = snap.data;
            if (src == null || src.isEmpty) return _placeholder();
            return _buildImage(src);
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final OrderBucket bucket;
  const _EmptyState({required this.bucket});

  String get _message {
    switch (bucket) {
      case OrderBucket.toPay:
        return 'No orders awaiting payment';
      case OrderBucket.toShip:
        return 'No orders being prepared';
      case OrderBucket.toDeliver:
        return 'No orders out for delivery';
      case OrderBucket.toRate:
        return 'Nothing to rate right now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 56, color: isDark ? Colors.grey[700] : Colors.grey[300]),
          const SizedBox(height: 12),
          Text(_message,
              style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? orderId;
  final bool allowCancel;

  const _OrderCard({
    required this.data,
    this.orderId,
    this.allowCancel = false,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _isCancelling = false;

  // Short names so the build() below reads exactly as it did before.
  Map<String, dynamic> get data => widget.data;

  /// Pending = nobody at the shop has started on it yet. Same rule as the
  /// website and as the Firestore rules (a customer may only cancel a
  /// 'pending' order).
  bool get _isPending => (data['status'] ?? '').toString().toLowerCase() == 'pending';

  /// An online (GCash / Maya) order that is already paid. Cancelling it would
  /// need a refund, which is not automatic, so the customer must ask the shop.
  bool get _isPaidOnline {
    final method = (data['payment_method'] ?? data['paymentMethod'] ?? '').toString().toLowerCase();
    final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase();
    final online = ['gcash', 'maya', 'paymaya', 'paymongo'].contains(method);
    return online && paymentStatus.contains('paid');
  }

  Future<void> _confirmAndCancel() async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this order? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      // Exactly these two fields: the Firestore rules let a customer cancel
      // their OWN 'pending' order and change nothing else.
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      // Let the shop know (same notification the My Orders page sends).
      try {
        final shortId = '#${(orderId.length > 8 ? orderId.substring(0, 8) : orderId).toUpperCase()}';
        final customerName = (data['customer_name'] ?? data['customerName'] ?? 'A customer').toString();
        await InventoryData.createNotification(
          title: 'Order Cancellation Requested',
          message: '$customerName cancelled order $shortId.',
          type: 'warning',
          branchId: data['branchId'],
        );
      } catch (e) {
        // The order IS cancelled; a failed notification must not look like a failure.
        debugPrint('Cancel notification failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully'), backgroundColor: Colors.green),
        );
      }
      // No manual refresh: the live orders stream drops this card from the list.
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel the order: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = (data['items'] as List?) ?? [];
    final invoiceId = data['invoiceId'] ?? data['id'] ?? '—';
    final total = (data['total_price'] ?? data['totalAmount'] ?? 0).toDouble();
    final status = (data['status'] ?? 'pending').toString();

    // Full theme adaptation — this card used to be hardcoded white
    // regardless of app theme, which is why it stood out so jarringly
    // against a dark background.
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15);
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[500];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order #$invoiceId',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4B400).withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF4B400) : const Color(0xFFB8860B)),
                ),
              ),
            ],
          ),
          Divider(height: 20, color: borderColor),
          ...items.take(3).map((item) {
            final m = item as Map;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('${m['name'] ?? 'Item'} × ${m['qty'] ?? 1}',
                        style: TextStyle(fontSize: 13, color: primaryTextColor)),
                  ),
                  Text('₱${((m['price'] ?? 0) * (m['qty'] ?? 1)).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, color: primaryTextColor)),
                ],
              ),
            );
          }),
          if (items.length > 3)
            Text('+ ${items.length - 3} more item(s)',
                style: TextStyle(fontSize: 11, color: secondaryTextColor)),
          Divider(height: 20, color: borderColor),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12, color: primaryTextColor)),
              Text('₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
            ],
          ),
          // Cancel is offered while the order is still pending.
          if (widget.allowCancel && _isPending) ...[
            const SizedBox(height: 12),
            if (_isPaidOnline)
              Text(
                'This order is already paid. To cancel it, please contact the shop.',
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _confirmAndCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: _isCancelling
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                      : const Text('CANCEL ORDER', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Rating popup for ONE product.
class _RateItemDialog extends StatefulWidget {
  final String orderId;
  final String productId;
  final String productName;
  final String customerId;

  const _RateItemDialog({
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.customerId,
  });

  @override
  State<_RateItemDialog> createState() => _RateItemDialogState();
}

class _RateItemDialogState extends State<_RateItemDialog> {
  static const Color _amber = Color(0xFFF4B400);
  static const List<String> _labels = ['Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  int _stars = 0; // 0 = nothing chosen yet
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rate Your Item', style: TextStyle(color: textColor)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.productName,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
          const SizedBox(height: 12),
          // spaceBetween spreads 5 stars across whatever width the dialog has.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              return IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 34,
                icon: Icon(
                  i < _stars ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _amber,
                ),
                onPressed: _isSubmitting ? null : () => setState(() => _stars = i + 1),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(_stars == 0 ? 'Tap a star to rate' : _labels[_stars - 1],
              style: TextStyle(
                  fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: _amber),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: (_isSubmitting || _stars == 0) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _amber,
            // Dark letters on the amber button (default was amber-on-amber).
            foregroundColor: Colors.black,
            disabledBackgroundColor: _amber.withOpacity(0.35),
            disabledForegroundColor: Colors.black54,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          child: _isSubmitting
              ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('SUBMIT'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      // Document id "orderId_productId": the same product in the same order
      // can only ever be rated once.
      await FirebaseFirestore.instance
          .collection('product_ratings')
          .doc('${widget.orderId}_${widget.productId}')
          .set({
        'orderId': widget.orderId,
        'productId': widget.productId,
        'productName': widget.productName,
        'userId': user?.uid ?? widget.customerId,
        'userName': user?.displayName ?? user?.email?.split('@').first ?? 'Customer',
        'rating': _stars,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Thanks for rating! 🌸'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit rating: $e')),
        );
      }
    }
  }
}