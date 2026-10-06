import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// BLOOMINOUS - Firestore Cart Data (BloominousApp)
///
/// The app-side twin of BloominousWeb's assets/script/bloom_cart.js.
/// Both read and write the SAME Firestore document, so a customer has
/// ONE cart across the website and the mobile app.
///
/// --- DATA CONTRACT (must match bloom_cart.js + firestore.rules section 30) ---
/// carts/{uid}
/// {
///   userId:    "<uid>",                      // must equal the doc ID
///   items: {
///     "<productId>": {                       // inventory doc ID
///       id:       "<productId>",
///       name:     "Red Rose Bouquet",
///       price:    450,                       // number (display only)
///       qty:      2,                         // number, always > 0
///       branchId: "main_branch" | null,
///       image:    "https://..." | null
///     }
///   },
///   updatedAt: <server timestamp>
/// }
/// The security rules reject any other top-level field, and more than
/// 50 products in `items`.
class CartData {
  static const String _collection = 'carts';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  /// Returns the signed-in user, or throws a readable CartException.
  static User _requireUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw CartException('Please sign in to use your cart.');
    }
    return user;
  }

  /// Points at carts/{uid}.
  static DocumentReference<Map<String, dynamic>> _cartRefFor(String uid) {
    return _db.collection(_collection).doc(uid);
  }

  /// Safely turns a Firestore value into a number (handles int, double,
  /// or a numeric string). Returns null if it isn't a number at all.
  static num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  /// Converts the raw `items` map from Firestore into a clean, sorted list.
  /// Forces numbers to real numbers and drops anything with qty <= 0,
  /// exactly like normalizeItems() in bloom_cart.js.
  static List<Map<String, dynamic>> _normalize(dynamic rawItems) {
    final List<Map<String, dynamic>> clean = [];
    if (rawItems is! Map) return clean;

    rawItems.forEach((key, value) {
      if (value is! Map) return; // skip malformed entries
      final int qty = _toNum(value['qty'])?.toInt() ?? 0;
      if (qty <= 0) return; // skip empty entries

      final String id = key.toString();
      clean.add({
        'id': id,
        'name': value['name']?.toString() ?? 'Unnamed',
        'price': _toNum(value['price'])?.toDouble() ?? 0.0,
        'qty': qty,
        'branchId': value['branchId']?.toString(),
        'image': value['image']?.toString(),
      });
    });

    // Stable, alphabetical order so items don't jump around on screen.
    clean.sort((a, b) => (a['name'] as String)
        .toLowerCase()
        .compareTo((b['name'] as String).toLowerCase()));
    return clean;
  }

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  /// Live cart. Emits the current items now, then again on every change
  /// (from this phone, another phone, or the website).
  static Stream<List<Map<String, dynamic>>> getCartStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.error(CartException('Please sign in to view your cart.'));
    }
    return _cartRefFor(user.uid)
        .snapshots()
        .map((snap) => _normalize(snap.data()?['items']));
  }

  /// One-time read of the cart (e.g., right before submitting an order).
  static Future<List<Map<String, dynamic>>> getCart() async {
    final user = _requireUser();
    final snap = await _cartRefFor(user.uid).get();
    return _normalize(snap.data()?['items']);
  }

  // ---------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------

  /// Adds [qty] of a product. Uses a server-side increment so rapid taps
  /// (or the web + app at the same moment) never overwrite each other.
  static Future<void> addItem({
    required String productId,
    required String name,
    required num price,
    String? branchId,
    String? image,
    int qty = 1,
  }) async {
    if (productId.isEmpty) {
      throw CartException('This product is missing its ID.');
    }
    final user = _requireUser();

    await _cartRefFor(user.uid).set({
      'userId': user.uid,
      'items': {
        productId: {
          'id': productId,
          'name': name.isEmpty ? 'Unnamed' : name,
          'price': price.toDouble(),
          'branchId': branchId,
          'image': image,
          'qty': FieldValue.increment(qty),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Convenience wrapper for an inventory record (the same kind of
  /// Map<String, dynamic> that InventoryData returns, with an 'id' key).
  static Future<void> addFromInventory(
      Map<String, dynamic> product, {
        String? branchId,
      }) {
    return addItem(
      productId: product['id']?.toString() ?? '',
      name: product['name']?.toString() ?? 'Unnamed',
      price: _toNum(product['price']) ?? 0,
      branchId: branchId ?? product['branchId']?.toString(),
      image: product['image']?.toString(),
    );
  }

  /// Sets an exact quantity. 0 or less removes the item.
  static Future<void> setQty(String productId, int qty) async {
    if (qty <= 0) return removeItem(productId);
    final user = _requireUser();

    await _cartRefFor(user.uid).update({
      FieldPath(['items', productId, 'qty']): qty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes one product from the cart.
  static Future<void> removeItem(String productId) async {
    final user = _requireUser();

    await _cartRefFor(user.uid).update({
      FieldPath(['items', productId]): FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Empties the whole cart. Call this after an order is placed.
  static Future<void> clear() async {
    final user = _requireUser();
    await _cartRefFor(user.uid).delete();
  }

  // ---------------------------------------------------------------------
  // Shared math (same formulas as BloomCart.count / BloomCart.total)
  // ---------------------------------------------------------------------

  static int count(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (sum, item) => sum + (item['qty'] as int));
  }

  static double total(List<Map<String, dynamic>> items) {
    return items.fold<double>(
      0,
          (sum, item) => sum + (item['price'] as double) * (item['qty'] as int),
    );
  }

  // ---------------------------------------------------------------------
  // Error messages
  // ---------------------------------------------------------------------

  /// Turns any cart error into a sentence a customer can understand.
  static String friendlyError(Object error) {
    if (error is CartException) return error.message;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Your cart could not be saved. You may be signed out, or your cart is full (50 products max).';
        case 'unavailable':
          return 'No internet connection. Please try again.';
        case 'not-found':
          return 'That item is no longer in your cart.';
      }
    }
    return 'Something went wrong with your cart. Please try again.';
  }
}

/// A cart error with a message that is safe to show to customers.
class CartException implements Exception {
  final String message;
  CartException(this.message);

  @override
  String toString() => message;
}