import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrderTrackingPage extends StatefulWidget {
  final String customerId;
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

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  OrderBucket? _bucketFor(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (order['paymentStatus'] ?? '').toString().toLowerCase();
    final paymentMethod = (order['payment_method'] ?? order['paymentMethod'] ?? '')
        .toString()
        .toLowerCase();

    if (status == 'cancelled') return null;

    if (status == 'delivered' || status == 'completed') {
      return OrderBucket.toRate;
    }

    if (status == 'shipped' || status == 'out_for_delivery') {
      return OrderBucket.toDeliver;
    }

    final isOnlinePayment = paymentMethod == 'gcash' ||
        paymentMethod == 'maya' ||
        paymentMethod == 'paymaya' ||
        paymentMethod == 'paymongo';
    final paymentUnresolved =
        paymentStatus.contains('pending') || paymentStatus.contains('awaiting');

    if (isOnlinePayment && paymentUnresolved) {
      return OrderBucket.toPay;
    }

    return OrderBucket.toShip;
  }

  /// Now fails toward SHOWING the order in "To Rate" rather than hanging
  /// forever — if the rating-status check errors for any reason (a
  /// permission hiccup, a transient network drop), the safer default is
  /// "let the customer see and rate it" rather than a spinner that never
  /// resolves. Worst case with this default: an already-rated order
  /// reappears once. Worst case with the OLD behavior: the tab is
  /// permanently broken.
  Future<bool> _isFullyRated(Map<String, dynamic> order) async {
    final items = (order['items'] as List?) ?? [];
    if (items.isEmpty) return true;

    try {
      for (final item in items) {
        final productId = (item as Map)['id'] ?? item['productId'];
        if (productId == null) continue;

        final ratingSnap = await FirebaseFirestore.instance
            .collection('product_ratings')
            .where('productId', isEqualTo: productId)
            .where('userId', isEqualTo: widget.customerId)
            .limit(1)
            .get();

        if (ratingSnap.docs.isEmpty) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Rating check failed, defaulting to "needs rating": $e');
      return false;
    }
  }

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
              _OrderList(docs: buckets[OrderBucket.toPay]!, bucket: OrderBucket.toPay),
              _OrderList(docs: buckets[OrderBucket.toShip]!, bucket: OrderBucket.toShip),
              _OrderList(
                  docs: buckets[OrderBucket.toDeliver]!, bucket: OrderBucket.toDeliver),
              _ToRateList(
                docs: buckets[OrderBucket.toRate]!,
                customerId: widget.customerId,
                isFullyRated: _isFullyRated,
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
      ),
    );
  }
}

class _ToRateList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String customerId;
  final Future<bool> Function(Map<String, dynamic>) isFullyRated;

  const _ToRateList({
    required this.docs,
    required this.customerId,
    required this.isFullyRated,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const _EmptyState(bucket: OrderBucket.toRate);

    return FutureBuilder<List<bool>>(
      future: Future.wait(docs.map((d) => isFullyRated(d.data() as Map<String, dynamic>))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFF4B400)));
        }

        // This branch is what was missing before — an error here used to
        // leave the loading spinner showing forever, since nothing ever
        // checked for it.
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'Could not check rating status.\n${snapshot.error ?? ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        final unratedDocs = <QueryDocumentSnapshot>[];
        for (int i = 0; i < docs.length; i++) {
          if (snapshot.data![i] == false) unratedDocs.add(docs[i]);
        }

        if (unratedDocs.isEmpty) return const _EmptyState(bucket: OrderBucket.toRate);

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: unratedDocs.length,
          itemBuilder: (context, index) => _OrderCard(
            data: unratedDocs[index].data() as Map<String, dynamic>,
            showRateButton: true,
            customerId: customerId,
          ),
        );
      },
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

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showRateButton;
  final String? customerId;

  const _OrderCard({required this.data, this.showRateButton = false, this.customerId});

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
          if (showRateButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showRateDialog(context, items, customerId!),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF4B400)),
                  foregroundColor: const Color(0xFFF4B400),
                ),
                child: const Text('RATE ITEMS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showRateDialog(BuildContext context, List items, String customerId) {
    showDialog(
      context: context,
      builder: (context) => _RateItemsDialog(items: items, customerId: customerId),
    );
  }
}

class _RateItemsDialog extends StatefulWidget {
  final List items;
  final String customerId;
  const _RateItemsDialog({required this.items, required this.customerId});

  @override
  State<_RateItemsDialog> createState() => _RateItemsDialogState();
}

class _RateItemsDialogState extends State<_RateItemsDialog> {
  final Map<String, int> _ratings = {};
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rate Your Items',
          style: TextStyle(color: isDark ? Colors.white : Colors.black)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.items.map((item) {
            final m = item as Map;
            final id = m['id'] ?? m['productId'];
            final name = m['name'] ?? 'Item';
            final current = _ratings[id] ?? 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black)),
                  Row(
                    children: List.generate(5, (i) {
                      return IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          i < current ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFF4B400),
                        ),
                        onPressed: () => setState(() => _ratings[id] = i + 1),
                      );
                    }),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _isSubmitting || _ratings.isEmpty ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF4B400)),
          child: _isSubmitting
              ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('SUBMIT'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      _ratings.forEach((productId, rating) {
        final ref = FirebaseFirestore.instance.collection('product_ratings').doc();
        batch.set(ref, {
          'productId': productId,
          'userId': widget.customerId,
          'rating': rating,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit rating: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}