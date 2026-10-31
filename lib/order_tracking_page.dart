import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'inventory_data.dart';

class OrderTrackingPage extends StatefulWidget {
  final String customerId;
  /// Which tab to open: 0 = To Pay, 1 = To Ship, 2 = To Receive,
  /// 3 = To Rate, 4 = Completed, 5 = Cancelled. This is also the left-to-right
  /// order of the tab bar. Default 0 = To Pay.
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

// ---------------------------------------------------------------------------
// Small shared helpers (file-private: only this file uses them)
// ---------------------------------------------------------------------------

/// 'IN TRANSIT', 'in transit' and 'in_transit' all become 'in_transit'.
String _normalizedStatus(Map<String, dynamic> order) => (order['status'] ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_');

/// Anything (number, text, null) -> a number. Bad input becomes 0.
num _toNum(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

/// Firestore Timestamp / ISO text -> DateTime (or null when missing).
DateTime? _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// The first non-empty text found under any of [keys].
String _firstText(Map<String, dynamic> d, List<String> keys) {
  for (final k in keys) {
    final v = d[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
  }
  return '';
}

String _money(num v) => '₱${v.toStringAsFixed(2)}';

/// 2 -> "2", 1.5 -> "1.5" (no ugly "2.0").
String _qtyText(num q) => q % 1 == 0 ? q.toInt().toString() : q.toString();

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// True when the order was cancelled (by the customer or the shop). The
/// "Cancelled" tab lists these. 'CANCELLED', 'Cancelled' and 'cancelled' all
/// count; so does the US spelling 'canceled'.
bool _isCancelledOrder(Map<String, dynamic> order) {
  final status = _normalizedStatus(order);
  return status == 'cancelled' || status == 'canceled';
}

/// True once the customer pressed "Order Received" (or the order is an older
/// one that was already marked delivered / completed).
bool orderIsReceived(Map<String, dynamic> order) {
  final status = _normalizedStatus(order);
  if (status == 'delivered' || status == 'completed') return true;
  // containsKey (not "!= null"): while the write is still travelling to the
  // server, a pending server timestamp reads as null. The KEY already exists,
  // so the card can move to Completed immediately.
  return status == 'confirmed' && order.containsKey('receivedAt');
}

/// THE one place that decides which tab an order belongs in. The profile
/// page's badge counts and the tabs below both call this, so they can never
/// disagree.
///
///   pending                      -> To Pay   (nothing has started yet)
///   pending but already PAID     -> To Ship  (online payment went through)
///   processing / prepared / paid -> To Ship  (the shop is preparing it)
///   in transit / shipped         -> To Receive (on its way)
///   confirmed (driver delivered) -> To Receive until the customer presses
///                                   "Order Received", then -> To Rate bucket
///                                   (= the Completed tab and To Rate tab)
///   delivered / completed        -> To Rate bucket (already complete)
///   cancelled                    -> none (null). They are NOT counted in the
///                                   profile badges; the page puts them in their
///                                   own "Cancelled" tab instead.
OrderBucket? orderBucketFor(Map<String, dynamic> order) {
  final status = _normalizedStatus(order);
  final paymentStatus =
  (order['paymentStatus'] ?? order['payment_status'] ?? '').toString().toLowerCase();

  if (status == 'cancelled') return null;
  if (status == 'delivered' || status == 'completed') return OrderBucket.toRate;

  // 'confirmed' is what the driver's proof of delivery writes. The parcel is
  // at the customer's door, but the order is only COMPLETE once they confirm.
  if (status == 'confirmed') {
    return order.containsKey('receivedAt') ? OrderBucket.toRate : OrderBucket.toDeliver;
  }

  if (status == 'shipped' || status == 'out_for_delivery' || status == 'in_transit') {
    return OrderBucket.toDeliver;
  }

  if (status == 'pending' || status.isEmpty) {
    // A paid order has nothing left to pay, so it goes straight to To Ship.
    return paymentStatus == 'paid' ? OrderBucket.toShip : OrderBucket.toPay;
  }

  // processing, prepared, paid, ... = the shop is working on it.
  return OrderBucket.toShip;
}

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      // clamp keeps a bad number from crashing the screen.
      initialIndex: widget.initialTabIndex.clamp(0, 5).toInt(),
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
            Tab(text: 'To Receive'),
            Tab(text: 'To Rate'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
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

          // Cancelled orders get their own tab; everything else goes to its stage.
          final List<QueryDocumentSnapshot> cancelledDocs = [];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (_isCancelledOrder(data)) {
              cancelledDocs.add(doc);
              continue;
            }
            final bucket = _bucketFor(data);
            if (bucket != null) buckets[bucket]!.add(doc);
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Same order as the tab bar above:
              // To Pay, To Ship, To Receive, To Rate, Completed, Cancelled.
              _OrderList(docs: buckets[OrderBucket.toPay]!, bucket: OrderBucket.toPay),
              _OrderList(docs: buckets[OrderBucket.toShip]!, bucket: OrderBucket.toShip),
              _OrderList(
                  docs: buckets[OrderBucket.toDeliver]!, bucket: OrderBucket.toDeliver),
              _ToRateList(
                docs: buckets[OrderBucket.toRate]!,
                customerId: widget.customerId,
              ),
              // Completed = every order the customer has received. Same list
              // the To Rate tab starts from, but grouped by ORDER, with a
              // receipt, and rated or not.
              _CompletedList(
                docs: buckets[OrderBucket.toRate]!,
                customerId: widget.customerId,
              ),
              // Cancelled = every order that was cancelled, newest first.
              _CancelledList(docs: cancelledDocs),
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
        // doc.id is the real Firestore id the cancel / received buttons need.
        orderId: docs[index].id,
        // Only orders still waiting to be paid or shipped can be cancelled.
        allowCancel: bucket == OrderBucket.toShip || bucket == OrderBucket.toPay,
        // To Ship and To Receive show the delivery schedule the customer chose
        // at checkout (like Shopee's "estimated delivery" line).
        showDelivery: bucket == OrderBucket.toShip || bucket == OrderBucket.toDeliver,
      ),
    );
  }
}

/// "Cancelled" tab. Read-only cards: nothing can be done to a cancelled order.
class _CancelledList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const _CancelledList({required this.docs});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const _EmptyState(
        bucket: OrderBucket.toRate, // ignored: the message below replaces it
        messageOverride: 'No cancelled orders',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) => _OrderCard(
        data: docs[index].data() as Map<String, dynamic>,
        orderId: docs[index].id,
        allowCancel: false, // already cancelled
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ratings: ONE live query shared by To Rate, Completed and the rate sheet
// ---------------------------------------------------------------------------

/// Remembers which (order, product) pairs this customer already rated.
///  - new ratings carry an orderId  -> key "orderId_productId"
///  - older ratings have no orderId -> remembered by productId only
class _RatedIndex {
  final Set<String> _keys = {};
  final Set<String> _legacyProducts = {};

  _RatedIndex(Iterable<QueryDocumentSnapshot> docs) {
    for (final d in docs) {
      final m = d.data() as Map<String, dynamic>;
      final pid = (m['productId'] ?? '').toString();
      final oid = (m['orderId'] ?? '').toString();
      if (oid.isEmpty) {
        _legacyProducts.add(pid);
      } else {
        _keys.add('${oid}_$pid');
      }
    }
  }

  bool isRated(String orderId, String productId) =>
      _keys.contains('${orderId}_$productId') || _legacyProducts.contains(productId);
}

/// Listens (live) to this customer's ratings in `product_ratings` and hands
/// the result to [builder]. ONE query for all products is cheaper than one per
/// product and needs no special index. If the read ever fails we simply treat
/// everything as "not rated yet" so the customer can still see their items.
class _RatingsBuilder extends StatelessWidget {
  final String customerId;
  final Widget Function(BuildContext context, _RatedIndex rated) builder;

  const _RatingsBuilder({required this.customerId, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('product_ratings')
          .where('userId', isEqualTo: customerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFF4B400)));
        }
        return builder(context, _RatedIndex(snapshot.data?.docs ?? <QueryDocumentSnapshot>[]));
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

/// Flattens ONE order into one entry per item that is not rated yet.
List<_RateEntry> _unratedEntries(
    String orderId, Map<String, dynamic> order, _RatedIndex rated) {
  final out = <_RateEntry>[];
  final items = (order['items'] as List?) ?? [];
  for (final raw in items) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final productId = (item['id'] ?? item['productId'])?.toString();
    if (productId == null || productId.isEmpty) continue;
    if (rated.isRated(orderId, productId)) continue;
    out.add(_RateEntry(orderId: orderId, order: order, item: item, productId: productId));
  }
  return out;
}

/// "To Rate" tab. NOT grouped by order: every received product that still
/// needs a rating gets its own card, even when several were bought together.
/// The moment a rating is saved that product's card disappears by itself.
class _ToRateList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs; // received orders, newest first
  final String customerId;

  const _ToRateList({required this.docs, required this.customerId});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const _EmptyState(bucket: OrderBucket.toRate);

    return _RatingsBuilder(
      customerId: customerId,
      builder: (context, rated) {
        // Flatten: order -> its items -> one entry per unrated item.
        final entries = <_RateEntry>[];
        for (final doc in docs) {
          entries.addAll(
              _unratedEntries(doc.id, doc.data() as Map<String, dynamic>, rated));
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

// ---------------------------------------------------------------------------
// COMPLETED tab (Shopee style): one card per RECEIVED order
// ---------------------------------------------------------------------------

class _CompletedList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs; // received orders, newest first
  final String customerId;

  const _CompletedList({required this.docs, required this.customerId});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const _EmptyState(
        bucket: OrderBucket.toRate,
        messageOverride: 'No completed orders yet',
      );
    }

    return _RatingsBuilder(
      customerId: customerId,
      builder: (context, rated) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) => _CompletedCard(
            orderId: docs[index].id,
            order: docs[index].data() as Map<String, dynamic>,
            rated: rated,
            customerId: customerId,
          ),
        );
      },
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> order;
  final _RatedIndex rated;
  final String customerId;

  const _CompletedCard({
    required this.orderId,
    required this.order,
    required this.rated,
    required this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFF4B400);

    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor =
    isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15);
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secondaryText = isDark ? Colors.grey[400] : Colors.grey[600];

    final invoice = _invoiceOf(orderId, order);
    final items = ((order['items'] as List?) ?? []).whereType<Map>().toList();
    final total = _toNum(order['total_price'] ?? order['totalAmount'] ?? 0);
    final receivedOn = _toDate(order['receivedAt']);
    final unrated = _unratedEntries(orderId, order, rated);

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
                        fontWeight: FontWeight.bold, fontSize: 13, color: primaryText)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('COMPLETED',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            ],
          ),
          Divider(height: 20, color: borderColor),

          // First two products with their photos (like Shopee's order row).
          ...items.take(2).map((m) {
            final item = Map<String, dynamic>.from(m);
            final qty = _toNum(item['qty'] ?? item['quantity'] ?? 1);
            final price = _toNum(item['price'] ?? 0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  _ItemPhoto(
                    image: (item['image'] ?? item['imageUrl'])?.toString(),
                    productId: (item['id'] ?? item['productId'] ?? '').toString(),
                    branchId: (item['branchId'] ?? order['branchId'])?.toString(),
                    isDark: isDark,
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((item['name'] ?? 'Item').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: primaryText)),
                        const SizedBox(height: 2),
                        Text('x${_qtyText(qty)}',
                            style: TextStyle(fontSize: 12, color: secondaryText)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_money(price * qty),
                      style: TextStyle(fontSize: 13, color: primaryText)),
                ],
              ),
            );
          }),
          if (items.length > 2)
            Text('+ ${items.length - 2} more item(s)',
                style: TextStyle(fontSize: 11, color: secondaryText)),

          Divider(height: 20, color: borderColor),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${items.length} item(s)',
                  style: TextStyle(fontSize: 12, color: secondaryText)),
              Row(
                children: [
                  Text('Order Total: ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12, color: primaryText)),
                  Text(_money(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                ],
              ),
            ],
          ),
          if (receivedOn != null) ...[
            const SizedBox(height: 4),
            Text('Received on ${DateFormat('MMM d, yyyy').format(receivedOn)}',
                style: TextStyle(fontSize: 11, color: secondaryText)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showReceipt(context, orderId, order),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('VIEW RECEIPT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? amber : const Color(0xFFB8860B),
                    side: const BorderSide(color: amber),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: unrated.isNotEmpty
                    ? ElevatedButton.icon(
                  onPressed: () => _showRateSheet(context, orderId, order, customerId),
                  icon: const Icon(Icons.star_rounded, size: 16),
                  label: Text('RATE (${unrated.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                )
                    : Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('RATED ✓',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing the items of ONE order that still need a rating.
/// It watches the ratings live, so a row vanishes as soon as it is rated.
void _showRateSheet(
    BuildContext context,
    String orderId,
    Map<String, dynamic> order,
    String customerId,
    ) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final paper = isDark ? const Color(0xFF1E1E1E) : Colors.white;
      final primaryText = isDark ? Colors.white : Colors.black87;
      final secondaryText = isDark ? Colors.grey[400] : Colors.grey[600];

      return Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: _RatingsBuilder(
            customerId: customerId,
            builder: (context, rated) {
              final entries = _unratedEntries(orderId, order, rated);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                    child: Text('Rate your items',
                        style: GoogleFonts.cormorantGaramond(
                            fontSize: 24, fontWeight: FontWeight.bold, color: primaryText)),
                  ),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 44),
                          const SizedBox(height: 10),
                          Text('All items rated. Thank you! 🌸',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: primaryText)),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('CLOSE'),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final name = (e.item['name'] ?? 'Item').toString();
                          final qty = _toNum(e.item['qty'] ?? e.item['quantity'] ?? 1);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                _ItemPhoto(
                                  image: (e.item['image'] ?? e.item['imageUrl'])?.toString(),
                                  productId: e.productId,
                                  branchId:
                                  (e.item['branchId'] ?? e.order['branchId'])?.toString(),
                                  isDark: isDark,
                                  size: 52,
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
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: primaryText)),
                                      Text('x${_qtyText(qty)}',
                                          style: TextStyle(fontSize: 12, color: secondaryText)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _RateItemDialog(
                                      orderId: e.orderId,
                                      productId: e.productId,
                                      productName: name,
                                      customerId: customerId,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF4B400),
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    textStyle: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  child: const Text('RATE'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// RECEIPT
// ---------------------------------------------------------------------------

/// The invoice number shown to the customer (same fallback chain as before).
String _invoiceOf(String orderId, Map<String, dynamic> order) {
  final saved = (order['invoiceId'] ?? order['id'] ?? '').toString().trim();
  if (saved.isNotEmpty) return saved;
  return orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId;
}

class _ReceiptLine {
  final String name;
  final num qty;
  final num price;
  const _ReceiptLine({required this.name, required this.qty, required this.price});
  num get lineTotal => qty * price;
}

/// Everything the receipt shows, worked out ONCE from the order document.
/// Field names differ a little between web and app orders, so every value is
/// looked up under all the names we know and simply left out if missing.
class _ReceiptData {
  final String invoice;
  final List<_ReceiptLine> lines;
  final num subtotal;
  final num deliveryFee;
  final num discount;
  final num total;
  final String customer;
  final String phone;
  final String address;
  final String payment;
  final String paymentStatus;
  final String schedule;
  final String courier;
  final String receivedBy;
  final DateTime? placedAt;
  final DateTime? receivedAt;
  final bool isComplete;

  const _ReceiptData({
    required this.invoice,
    required this.lines,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.customer,
    required this.phone,
    required this.address,
    required this.payment,
    required this.paymentStatus,
    required this.schedule,
    required this.courier,
    required this.receivedBy,
    required this.placedAt,
    required this.receivedAt,
    required this.isComplete,
  });

  factory _ReceiptData.from(String orderId, Map<String, dynamic> o) {
    final lines = <_ReceiptLine>[];
    for (final raw in (o['items'] as List?) ?? const []) {
      if (raw is! Map) continue;
      lines.add(_ReceiptLine(
        name: (raw['name'] ?? 'Item').toString(),
        qty: _toNum(raw['qty'] ?? raw['quantity'] ?? 1),
        price: _toNum(raw['price'] ?? 0),
      ));
    }

    num subtotal = 0;
    for (final l in lines) {
      subtotal += l.lineTotal;
    }

    num total = _toNum(o['total_price'] ?? o['totalAmount'] ?? o['totalPrice'] ?? o['total_amount'] ?? 0);
    if (total == 0) total = subtotal;

    // Delivery fee: use the saved one when the order has it; otherwise it is
    // whatever is left between the items and the total (a negative left-over
    // is a discount).
    num? knownFee;
    for (final k in const ['shippingFee', 'shipping_fee', 'deliveryFee', 'delivery_fee']) {
      if (o[k] != null) {
        knownFee = _toNum(o[k]);
        break;
      }
    }
    num fee;
    num discount;
    if (knownFee != null) {
      fee = knownFee;
      final gap = subtotal + fee - total;
      discount = gap > 0.009 ? gap : 0;
    } else {
      final diff = total - subtotal;
      fee = diff > 0 ? diff : 0;
      discount = diff < 0 ? -diff : 0;
    }

    final method = _firstText(o, ['payment_method', 'paymentMethod']).toLowerCase();
    String payment;
    switch (method) {
      case 'gcash':
        payment = 'GCash';
        break;
      case 'maya':
      case 'paymaya':
        payment = 'Maya';
        break;
      case 'cod':
        payment = 'Cash on Delivery';
        break;
      case '':
        payment = '';
        break;
      default:
        payment = method.toUpperCase();
    }

    return _ReceiptData(
      invoice: _invoiceOf(orderId, o),
      lines: lines,
      subtotal: subtotal,
      deliveryFee: fee,
      discount: discount,
      total: total,
      customer: _firstText(o, ['customer_name', 'customerName', 'recipientName', 'name']),
      phone: _firstText(o, ['phone', 'customer_phone', 'contact']),
      address: _firstText(o, ['address', 'shipping_address', 'shippingAddress', 'delivery_address']),
      payment: payment,
      paymentStatus: _capitalize(_firstText(o, ['paymentStatus', 'payment_status'])),
      schedule: _scheduleText(o['deliverySchedule']),
      courier: _firstText(o, ['courierName']),
      receivedBy: _firstText(o, ['podRecipient']),
      placedAt: _toDate(o['createdAt'] ?? o['created_at'] ?? o['timestamp']),
      receivedAt: _toDate(o['receivedAt']),
      isComplete: orderIsReceived(o),
    );
  }

  /// Plain-text version, used by the COPY button.
  String toPlainText() {
    final f = DateFormat('MMM d, yyyy h:mm a');
    final b = StringBuffer()
      ..writeln('BLOOMINOUS - ORDER RECEIPT')
      ..writeln('Order #$invoice');
    if (placedAt != null) b.writeln('Placed: ${f.format(placedAt!)}');
    if (receivedAt != null) b.writeln('Received: ${f.format(receivedAt!)}');
    if (payment.isNotEmpty) {
      b.writeln('Payment: $payment${paymentStatus.isNotEmpty ? ' ($paymentStatus)' : ''}');
    }
    if (schedule.isNotEmpty) b.writeln('Delivery: $schedule');
    b.writeln('------------------------------');
    for (final l in lines) {
      b.writeln('${l.name}  ${_qtyText(l.qty)} x ${_money(l.price)} = ${_money(l.lineTotal)}');
    }
    b
      ..writeln('------------------------------')
      ..writeln('Subtotal: ${_money(subtotal)}')
      ..writeln('Delivery fee: ${_money(deliveryFee)}');
    if (discount > 0) b.writeln('Discount: -${_money(discount)}');
    b
      ..writeln('TOTAL: ${_money(total)}')
      ..writeln('------------------------------');
    if (customer.isNotEmpty) b.writeln('Deliver to: $customer');
    if (phone.isNotEmpty) b.writeln(phone);
    if (address.isNotEmpty) b.writeln(address);
    return b.toString();
  }
}

/// "08:00-10:00" -> "8:00 AM – 10:00 AM". Anything odd is shown as-is.
String _slotText(String slot) {
  final parts = slot.split('-');
  if (parts.length != 2) return slot;
  String one(String hhmm) {
    final t = hhmm.trim().split(':');
    if (t.length != 2) return hhmm;
    final h = int.tryParse(t[0]);
    final m = int.tryParse(t[1]);
    if (h == null || m == null) return hhmm;
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
  }
  return '${one(parts[0])} – ${one(parts[1])}';
}

/// The order's saved delivery schedule as text. Returns '' (row hidden) when
/// the order carries none, so we never print a schedule we are not sure of.
String _scheduleText(dynamic s) {
  if (s is! Map) return '';
  if ((s['mode'] ?? '').toString() != 'scheduled') return 'As soon as possible';
  final date = DateTime.tryParse((s['date'] ?? '').toString());
  final slot = (s['slot'] ?? '').toString();
  if (date == null) return 'Scheduled';
  final day = DateFormat('EEE, MMM d, yyyy').format(date);
  return slot.isEmpty ? day : '$day, ${_slotText(slot)}';
}

Future<void> _showReceipt(
    BuildContext context, String orderId, Map<String, dynamic> order) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true, // lets the sheet use most of the screen height
    backgroundColor: Colors.transparent,
    builder: (_) => _ReceiptSheet(receipt: _ReceiptData.from(orderId, order)),
  );
}

class _DashedDivider extends StatelessWidget {
  final Color color;
  const _DashedDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          // One 4px dash every 8px across whatever width we were given.
          final count = (box.maxWidth / 8).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
                  (_) => SizedBox(
                width: 4,
                height: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: color)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  final _ReceiptData receipt;
  const _ReceiptSheet({required this.receipt});

  Widget _kv(String key, String value, Color muted, Color strong) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(key, style: TextStyle(fontSize: 12, color: muted)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: strong)),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, String value, Color muted, Color strong) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          Text(value, style: TextStyle(fontSize: 13, color: strong)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFF4B400);
    final paper = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final strong = isDark ? Colors.white : Colors.black87;
    final muted = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final dash = isDark ? Colors.white24 : Colors.black26;
    final dateFmt = DateFormat('MMM d, yyyy • h:mm a');

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                  children: [
                    const Center(
                        child: Icon(Icons.receipt_long_rounded, color: amber, size: 34)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('BLOOMINOUS',
                          style: GoogleFonts.cormorantGaramond(
                              fontSize: 26, fontWeight: FontWeight.bold, color: strong)),
                    ),
                    Center(
                      child: Text('Order Receipt',
                          style: TextStyle(fontSize: 12, color: muted, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: (r.isComplete ? Colors.green : amber)
                              .withOpacity(isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          r.isComplete ? 'COMPLETED' : 'DELIVERED • AWAITING YOUR CONFIRMATION',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: r.isComplete
                                  ? Colors.green
                                  : (isDark ? amber : const Color(0xFFB8860B))),
                        ),
                      ),
                    ),
                    _DashedDivider(color: dash),
                    _kv('Order No.', '#${r.invoice}', muted, strong),
                    if (r.placedAt != null)
                      _kv('Order placed', dateFmt.format(r.placedAt!), muted, strong),
                    if (r.payment.isNotEmpty)
                      _kv(
                        'Payment',
                        '${r.payment}${r.paymentStatus.isNotEmpty ? ' (${r.paymentStatus})' : ''}',
                        muted,
                        strong,
                      ),
                    if (r.schedule.isNotEmpty) _kv('Delivery', r.schedule, muted, strong),
                    if (r.receivedAt != null)
                      _kv('Received on', dateFmt.format(r.receivedAt!), muted, strong),
                    _DashedDivider(color: dash),
                    Text('ITEMS',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: muted)),
                    const SizedBox(height: 8),
                    for (final l in r.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.name,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: strong)),
                                  Text('${_qtyText(l.qty)} × ${_money(l.price)}',
                                      style: TextStyle(fontSize: 12, color: muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_money(l.lineTotal),
                                style: TextStyle(fontSize: 13, color: strong)),
                          ],
                        ),
                      ),
                    _DashedDivider(color: dash),
                    _moneyRow('Subtotal', _money(r.subtotal), muted, strong),
                    _moneyRow('Delivery fee', _money(r.deliveryFee), muted, strong),
                    if (r.discount > 0)
                      _moneyRow('Discount', '-${_money(r.discount)}', muted, Colors.redAccent),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16, color: strong)),
                        Text(_money(r.total),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      ],
                    ),
                    if (r.customer.isNotEmpty || r.phone.isNotEmpty || r.address.isNotEmpty) ...[
                      _DashedDivider(color: dash),
                      Text('DELIVERED TO',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: muted)),
                      const SizedBox(height: 8),
                      if (r.customer.isNotEmpty)
                        Text(r.customer,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: strong)),
                      if (r.phone.isNotEmpty)
                        Text(r.phone, style: TextStyle(fontSize: 12, color: muted)),
                      if (r.address.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(r.address, style: TextStyle(fontSize: 12, color: muted)),
                        ),
                    ],
                    if (r.courier.isNotEmpty || r.receivedBy.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (r.courier.isNotEmpty) _kv('Courier', r.courier, muted, strong),
                      if (r.receivedBy.isNotEmpty)
                        _kv('Received by', r.receivedBy, muted, strong),
                    ],
                    _DashedDivider(color: dash),
                    Center(
                      child: Text('Thank you for shopping with Bloominous 🌸',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: r.toPlainText()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Receipt copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('COPY'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? amber : const Color(0xFFB8860B),
                            side: const BorderSide(color: amber),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: amber,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          child: const Text('CLOSE'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Product photo
// ---------------------------------------------------------------------------

/// Square product photo for a card.
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
  final double size;

  const _ItemPhoto({
    required this.image,
    required this.productId,
    required this.branchId,
    required this.isDark,
    this.size = 64,
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
    if (branch == null || branch.isEmpty || widget.productId.isEmpty) return null;
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
        width: widget.size,
        height: widget.size,
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
  // When set, replaces the default message (used by the Completed tab, which
  // shares the toRate bucket but needs its own wording).
  final String? messageOverride;
  const _EmptyState({required this.bucket, this.messageOverride});

  String get _message {
    if (messageOverride != null) return messageOverride!;
    switch (bucket) {
      case OrderBucket.toPay:
        return 'No orders awaiting payment';
      case OrderBucket.toShip:
        return 'No orders being prepared';
      case OrderBucket.toDeliver:
        return 'No orders to receive';
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

// ---------------------------------------------------------------------------
// Order card for To Pay / To Ship / To Receive / Cancelled
// ---------------------------------------------------------------------------

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? orderId;
  final bool allowCancel;
  final bool showDelivery; // show the chosen delivery date + time window

  const _OrderCard({
    required this.data,
    this.orderId,
    this.allowCancel = false,
    this.showDelivery = false,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _isCancelling = false;
  bool _isReceiving = false;

  // Short names so the build() below reads exactly as it did before.
  Map<String, dynamic> get data => widget.data;

  /// Pending = nobody at the shop has started on it yet. Same rule as the
  /// website and as the Firestore rules (a customer may only cancel a
  /// 'pending' order).
  bool get _isPending => (data['status'] ?? '').toString().toLowerCase() == 'pending';

  /// The driver delivered it (status 'confirmed') but the customer has not
  /// pressed "Order Received" yet.
  bool get _awaitingReceipt =>
      _normalizedStatus(data) == 'confirmed' && !data.containsKey('receivedAt');

  bool get _isCancelled => _isCancelledOrder(data);

  /// The small line above the delivery date: where the parcel is right now.
  String get _deliveryHint {
    if (_awaitingReceipt) return 'Delivered';
    final s = _normalizedStatus(data);
    if (s == 'shipped' || s == 'out_for_delivery' || s == 'in_transit') {
      return 'Out for delivery';
    }
    return 'Preparing your order';
  }

  /// What the badge says. 'confirmed' is an internal word; to the customer it
  /// simply means "delivered".
  String get _statusLabel {
    if (_awaitingReceipt) return 'DELIVERED';
    return (data['status'] ?? 'pending').toString().toUpperCase();
  }

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

  /// "ORDER RECEIVED": the customer confirms the parcel arrived. This does NOT
  /// change `status` (the shop, the Sales Report and the website still see
  /// 'confirmed'); it only stamps `receivedAt`. The tabs read that stamp and
  /// move the order to Completed.
  Future<void> _confirmReceived() async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty || _isReceiving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Order Received?'),
        content: const Text(
            'Please confirm only if you have received all items in good condition. This will complete your order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('NOT YET'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF4B400),
              foregroundColor: Colors.black,
            ),
            child: const Text('YES, RECEIVED'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Grab the messenger BEFORE waiting: once the write lands, the live list
    // moves this card to Completed and this widget is disposed, so its own
    // context could no longer show the message.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isReceiving = true);
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'receivedAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Order completed! You can now rate your items in the Completed tab. 🌸'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isReceiving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not confirm the order: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = (data['items'] as List?) ?? [];
    final invoiceId = data['invoiceId'] ?? data['id'] ?? '—';
    final total = (data['total_price'] ?? data['totalAmount'] ?? 0).toDouble();
    // Cancelled cards: when it was cancelled + the delivery the customer had chosen.
    final cancelledAt = _toDate(data['cancelledAt']);
    final scheduleText = _scheduleText(data['deliverySchedule']);

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
                  // Cancelled = grey (same as the website); the rest = amber.
                  color: _isCancelled
                      ? Colors.grey.withOpacity(isDark ? 0.25 : 0.15)
                      : const Color(0xFFF4B400).withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isCancelled
                          ? (isDark ? Colors.grey[300] : Colors.grey[700])
                          : (isDark ? const Color(0xFFF4B400) : const Color(0xFFB8860B))),
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
          // To Ship / To Receive: the delivery the customer picked at checkout.
          if (widget.showDelivery && !_isCancelled && scheduleText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4B400).withOpacity(isDark ? 0.12 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF4B400).withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 20, color: Color(0xFFF4B400)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_deliveryHint  •  Your chosen delivery',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                        const SizedBox(height: 2),
                        Text(scheduleText,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: primaryTextColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isCancelled) ...[
            if (scheduleText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 15, color: secondaryTextColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Delivery: $scheduleText',
                        style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                  ),
                ],
              ),
            ],
            if (cancelledAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.cancel_outlined, size: 15, color: secondaryTextColor),
                  const SizedBox(width: 6),
                  Text('Cancelled on ${DateFormat('MMM d, yyyy · h:mm a').format(cancelledAt)}',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                ],
              ),
            ],
          ],
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

          // Delivered, waiting for the customer: receipt + ORDER RECEIVED.
          if (_awaitingReceipt) ...[
            const SizedBox(height: 10),
            Text(
              'Your order has been delivered. Please confirm once you have received it.',
              style: TextStyle(fontSize: 11, color: secondaryTextColor),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showReceipt(context, widget.orderId ?? '', data),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('VIEW RECEIPT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFFF4B400) : const Color(0xFFB8860B),
                      side: const BorderSide(color: Color(0xFFF4B400)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isReceiving ? null : _confirmReceived,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4B400),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    child: _isReceiving
                        ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('ORDER RECEIVED'),
                  ),
                ),
              ],
            ),
          ],

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