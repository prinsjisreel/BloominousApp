import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class InventoryData {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Selected Branch ID (can be updated by location detection)
  static String? selectedBranchId =
      'main_branch'; // Default to main_branch instead of 'all' for better reliability

  // --- Collection Accessors ---

  static CollectionReference _inventoryCollection() {
    String bid = selectedBranchId ?? 'main_branch';
    if (bid == 'all') bid = 'main_branch';
    return _db.collection('branches').doc(bid).collection('inventory');
  }

  static CollectionReference _ordersCollection() {
    return _db.collection('orders');
  }

  static CollectionReference _tripoCollection() {
    return _db.collection('kiri_history');
  }

  static CollectionReference _usersCollection() {
    return _db.collection('users');
  }

  static CollectionReference _branchesCollection() {
    return _db.collection('branches');
  }

  static CollectionReference _spoilageCollection() {
    String bid = selectedBranchId ?? 'main_branch';
    if (bid == 'all') bid = 'main_branch';
    return _db.collection('branches').doc(bid).collection('spoilage');
  }

  static CollectionReference _freshnessCollection() {
    return _db.collection('freshness_analysis');
  }

  // --- Stream Methods ---

  static Stream<List<Map<String, dynamic>>> inventoryStream(
      {String? branchId, String? category}) {
    final bid = branchId ?? (selectedBranchId ?? 'main_branch');
    if (bid != 'all') {
      _checkExpiredRecycledBouquets(bid);
    }

    if (bid == 'all') {
      return _db.collectionGroup('inventory').snapshots().map((snapshot) {
        final docs = snapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final pathParts = doc.reference.path.split('/');
              final branchDocId =
                  pathParts.length >= 2 ? pathParts[1] : 'unknown';
              return {
                ...data,
                'id': doc.id,
                'branchId': data['branchId'] ?? branchDocId,
              };
            })
            .where((d) => d['isDeleted'] != true && d['status'] != 'archived')
            .toList();

        // Filter by category in memory if needed
        if (category != null && category != 'All') {
          return docs.where((d) => d['category'] == category).toList();
        }
        return docs;
      }).handleError((err) {
        debugPrint('Error in collectionGroup inventory: $err');
        return <Map<String, dynamic>>[];
      });
    }

    // Direct branch query
    return _db
        .collection('branches')
        .doc(bid)
        .collection('inventory')
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              ...data,
              'id': doc.id,
              'branchId': bid,
            };
          })
          .where((d) => d['isDeleted'] != true && d['status'] != 'archived')
          .toList();

      if (category != null && category != 'All') {
        return docs.where((d) => d['category'] == category).toList();
      }
      return docs;
    }).handleError((err) {
      debugPrint('Error in branch inventory: $err');
      return <Map<String, dynamic>>[];
    });
  }

  static Stream<List<String>> globalCategoriesStream() {
    return _db.collectionGroup('categories').snapshots().map((snapshot) {
      final namesFromDocs = snapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String?)
          .where((name) => name != null)
          .cast<String>()
          .toSet()
          .toList();

      // Fallback categories that match what the user wants to see
      final List<String> fallback = [
        'Flowers',
        'Chocolates',
        'Stuffed Toys',
        'Wines',
        'Bouquets',
        'Other Items',
        'Gifts',
        'Balloons'
      ];

      // Combine docs and fallback, then deduplicate
      final Set<String> combined = {...namesFromDocs, ...fallback};
      final List<String> result = combined.toList();
      result.sort();
      return result;
    }).handleError((error) {
      debugPrint('Error in globalCategoriesStream: $error');
      return [
        'Flowers',
        'Chocolates',
        'Stuffed Toys',
        'Wines',
        'Bouquets',
        'Other Items'
      ];
    });
  }

  static Stream<List<Map<String, dynamic>>> getUserOrdersStream(
      {String? userId, String? email}) {
    Query query = _ordersCollection();
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    } else if (email != null) {
      query = query.where('customer_email', isEqualTo: email);
    }
    return query.snapshots().map((snapshot) {
      final docs = snapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
      // Sort in memory to avoid needing composite indexes for every filter combination
      docs.sort((a, b) {
        final dateA = (a['createdAt'] ?? a['created_at']) as dynamic;
        final dateB = (b['createdAt'] ?? b['created_at']) as dynamic;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        try {
          final tA = dateA is Timestamp ? dateA : Timestamp.now();
          final tB = dateB is Timestamp ? dateB : Timestamp.now();
          return tB.compareTo(tA);
        } catch (e) {
          return 0;
        }
      });
      return docs;
    });
  }

  static Stream<List<Map<String, dynamic>>> ordersStream({String? branchId}) {
    final bid = branchId ?? selectedBranchId;
    Query query = _ordersCollection();
    if (bid != null && bid != 'all') {
      query = query.where('branchId', isEqualTo: bid);
    }
    return query.snapshots().map((snapshot) {
      final docs = snapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
      // Sort in memory to avoid needing composite indexes for every branch
      docs.sort((a, b) {
        final dateA = (a['createdAt'] ?? a['created_at']) as dynamic;
        final dateB = (b['createdAt'] ?? b['created_at']) as dynamic;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        try {
          final tA = dateA is Timestamp ? dateA : Timestamp.now();
          final tB = dateB is Timestamp ? dateB : Timestamp.now();
          return tB.compareTo(tA);
        } catch (e) {
          return 0;
        }
      });
      return docs;
    });
  }

  static Stream<List<Map<String, dynamic>>> getBranchesStream() {
    return _branchesCollection().snapshots().map((snapshot) => snapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList());
  }

  static Future<List<Map<String, dynamic>>> getBranches() async {
    final snap = await _branchesCollection().get();
    return snap.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> lowStockStream(
      {int threshold = 10}) {
    return _inventoryCollection()
        .where('stock', isLessThanOrEqualTo: threshold)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return {
                ...data,
                'id': doc.id,
              };
            })
            .where((d) => d['isDeleted'] != true && d['status'] != 'archived')
            .toList());
  }

  static Stream<List<Map<String, dynamic>>> spoilageStream() {
    return _spoilageCollection().snapshots().map((snapshot) {
      final docs = snapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
      // Sort in memory to be resilient to missing timestamps
      docs.sort((a, b) {
        final dateA = (a['createdAt'] ?? a['created_at']) as dynamic;
        final dateB = (b['createdAt'] ?? b['created_at']) as dynamic;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return (dateB as Timestamp).compareTo(dateA as Timestamp);
      });
      return docs;
    });
  }

  static Stream<List<Map<String, dynamic>>> deliveryOrdersStream(
      {String? branchId}) {
    // Stream all active/delivered orders and filter in memory to avoid Firestore index errors or hiding unassigned branch orders
    return _ordersCollection().snapshots().map((snapshot) {
      final docs = snapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .where((d) => d['isDeleted'] != true && d['status'] != 'archived')
          .toList();

      if (branchId != null && branchId.isNotEmpty) {
        return docs.where((order) {
          final oBranch = order['branchId'];
          return oBranch == null || oBranch == '' || oBranch == branchId;
        }).toList();
      }
      return docs;
    });
  }

  static Stream<List<Map<String, dynamic>>> employeesStream(
      {String? branchId, List<String>? roles}) {
    Query query = _usersCollection()
        .where('role', whereIn: roles ?? ['employee', 'delivery']);
    if (branchId != null) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList());
  }

  static Stream<Map<String, dynamic>?> getCustomerLoyaltyDocStream(
      String customerId) {
    return _db.collection('customers').doc(customerId).snapshots().map((doc) =>
        doc.exists
            ? {...doc.data() as Map<String, dynamic>, 'id': doc.id}
            : null);
  }

  static Stream<List<Map<String, dynamic>>> getCustomerLoyaltyStream(
      String customerId) {
    return _db
        .collection('customers')
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList());
  }

  static Stream<List<Map<String, dynamic>>> tripoHistoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.fromIterable([]);
    return _tripoCollection()
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) {
      final docs = snap.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
      docs.sort((a, b) {
        final dateA = a['createdAt'] as dynamic;
        final dateB = b['createdAt'] as dynamic;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        try {
          return (dateB as Timestamp).compareTo(dateA as Timestamp);
        } catch (e) {
          return 0;
        }
      });
      return docs;
    });
  }

  // --- Action Methods ---

  static Future<String> placeOrder(Map<String, dynamic> orderData) async {
    final docRef = await _ordersCollection().add({
      ...orderData,
      'createdAt': FieldValue.serverTimestamp(),
      'branchId': selectedBranchId ?? 'main_branch',
    });
    return docRef.id;
  }

  static Future<void> updateOrderStatus(String orderId, String status) async {
    await _ordersCollection().doc(orderId).update({'status': status});
  }

  static Future<void> updateDeliveryStatus(
    String orderId,
    String status, {
    String? deliveryNotes,
    String? proofOfDeliveryPhoto,
    double? deliveredLat,
    double? deliveredLng,
    String? driverName,
    String? recipientName,
  }) async {
    final bool isDelivered = status.toLowerCase() == 'delivered';
    final Map<String, dynamic> updateData = {
      'status': isDelivered ? 'delivered' : status,
      'delivery_status': isDelivered
          ? 'Delivered'
          : (status == 'out_for_delivery' ? 'Out for Delivery' : status),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (isDelivered) {
      updateData['deliveredAt'] = FieldValue.serverTimestamp();
      updateData['podTimestamp'] = FieldValue.serverTimestamp();
      updateData['paymentStatus'] = 'Paid';
      updateData['locked'] = true;
    }

    if (deliveryNotes != null && deliveryNotes.isNotEmpty) {
      updateData['deliveryNotes'] = deliveryNotes;
    }

    if (recipientName != null && recipientName.isNotEmpty) {
      updateData['podRecipient'] = recipientName;
      updateData['recipientName'] = recipientName;
    } else if (deliveryNotes != null && deliveryNotes.isNotEmpty) {
      updateData['podRecipient'] = deliveryNotes;
    }

    if (proofOfDeliveryPhoto != null && proofOfDeliveryPhoto.isNotEmpty) {
      updateData['proofOfDeliveryPhoto'] = proofOfDeliveryPhoto;
      updateData['podPhotoUrl'] = proofOfDeliveryPhoto;
    }

    if (deliveredLat != null && deliveredLng != null) {
      updateData['deliveredLat'] = deliveredLat;
      updateData['deliveredLng'] = deliveredLng;
    }

    if (driverName != null && driverName.isNotEmpty) {
      updateData['driverName'] = driverName;
      updateData['courierName'] = driverName;
    }

    await _ordersCollection().doc(orderId).update(updateData);
  }

  static Future<void> updateDeliverySequence(
      List<Map<String, dynamic>> orderedStops) async {
    for (int i = 0; i < orderedStops.length; i++) {
      final id = orderedStops[i]['id'];
      if (id != null) {
        await _ordersCollection().doc(id).update({'stopSequence': i + 1});
      }
    }
  }

  static Future<void> updateStock(String productId, int quantityChange) async {
    final docRef = _inventoryCollection().doc(productId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      int newStock = (snapshot.get('stock') ?? 0) + quantityChange;
      transaction.update(docRef, {'stock': newStock});
    });
  }

  static Future<void> decrementStock(String productId, int quantity) async {
    await updateStock(productId, -quantity);
  }

  static Future<void> updateProduct(
      String productId, Map<String, dynamic> data) async {
    await _inventoryCollection().doc(productId).update(data);
  }

  static Future<void> addProduct(Map<String, dynamic> data) async {
    await _inventoryCollection().add(data);
  }

  static Future<void> deleteProduct(String productId) async {
    // Soft-delete: update status to 'archived' and isDeleted to true to preserve historical data
    await _inventoryCollection().doc(productId).update({
      'isDeleted': true,
      'status': 'archived',
      'archivedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, int>> reportSpoilage({
    required String productId,
    required int quantity,
    required String reason,
    String? flowerName,
    double? lossAmount,
    String? reportedBy,
    bool isSalvaged = false,
  }) async {
    final batch = _db.batch();
    final bid = selectedBranchId ?? 'main_branch';

    // 1. Add Spoilage/Salvage Record
    final spoilageRef = _spoilageCollection().doc();
    batch.set(spoilageRef, {
      'productId': productId,
      'quantity': quantity,
      'reason': reason,
      'flower_name': flowerName,
      'loss_amount': lossAmount,
      'reported_by': reportedBy,
      'is_salvaged': isSalvaged,
      'createdAt': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    });

    // 2. Deduct Original Inventory
    final inventoryRef = _inventoryCollection().doc(productId);
    batch.update(inventoryRef, {'stock': FieldValue.increment(-quantity)});

    int newBouquets = 0;
    int newLeftovers = 0;

    // 3. Handle Salvaged Items (Add to Recycled Bouquet)
    if (isSalvaged) {
      final recycledQuery = await _inventoryCollection()
          .where('name', isEqualTo: 'Recycled Bouquet')
          .limit(1)
          .get();

      final description =
          "This bouquet is composed of salvaged flowers (Mixed varieties). Limited offer: Only good for two days.";
      int currentLeftovers = 0;

      if (recycledQuery.docs.isNotEmpty) {
        final docData =
            recycledQuery.docs.first.data() as Map<String, dynamic>?;
        if (docData != null) {
          currentLeftovers = docData['leftoverFlowers'] ?? 0;
        }
      }

      final totalFlowers = quantity + currentLeftovers;
      newBouquets = totalFlowers ~/ 4; // Integer division
      newLeftovers = totalFlowers % 4;

      if (recycledQuery.docs.isNotEmpty) {
        batch.update(recycledQuery.docs.first.reference, {
          'stock': FieldValue.increment(newBouquets),
          'leftoverFlowers': newLeftovers,
          'description': description,
          'price': 150.0, // Fixed price for bouquets
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create Recycled Bouquet item if not exists
        final recRef = _inventoryCollection().doc();
        batch.set(recRef, {
          'name': 'Recycled Bouquet',
          'price': 150.0,
          'stock': newBouquets,
          'leftoverFlowers': newLeftovers,
          'category': 'Bouquets',
          'description': description,
          'image':
              'https://images.unsplash.com/photo-1582794543139-8ac9cb0f7b11?q=80&w=200&auto=format&fit=crop',
          'branchId': bid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // 4. Add Notification
    final notifRef = _db.collection('notifications').doc();
    final notifTitle =
        isSalvaged ? 'Bouquet Created from Salvage' : 'Spoilage Reported';

    String notifMsg = '';
    if (isSalvaged) {
      if (newBouquets > 0) {
        notifMsg =
            '[$bid] $quantity pcs of ${flowerName ?? 'Flowers'} salvaged. Built $newBouquets Recycled Bouquet(s) (leftover: $newLeftovers flower(s)).';
      } else {
        notifMsg =
            '[$bid] $quantity pcs of ${flowerName ?? 'Flowers'} salvaged to pool (leftover: $newLeftovers flower(s)). Needs 4 flowers for 1 bouquet.';
      }
    } else {
      notifMsg =
          '[$bid] $quantity pcs of ${flowerName ?? 'Flowers'} reported as spoiled ($reason).';
    }

    batch.set(notifRef, {
      'title': notifTitle,
      'message': notifMsg,
      'type': isSalvaged ? 'success' : 'warning',
      'branchId': bid,
      'created_at': FieldValue.serverTimestamp(),
      'read': false
    });

    await batch.commit();

    return {
      'newBouquets': newBouquets,
      'newLeftovers': newLeftovers,
    };
  }

  static Future<void> saveFreshnessAnalysis({
    required String productName,
    required String batchCode,
    required int freshnessScore,
    required String status,
    String? aiRecommendation,
  }) async {
    final bid = selectedBranchId ?? 'main_branch';
    await _freshnessCollection().add({
      'productName': productName,
      'batchCode': batchCode,
      'freshnessScore': freshnessScore,
      'status': status,
      'aiRecommendation': aiRecommendation,
      'branchId': bid,
      'createdAt': FieldValue.serverTimestamp(),
      'scanned_at': FieldValue.serverTimestamp(), // Match web version
    });
  }

  static Future<void> recycleFromAnalysis({
    required String productName,
    required int quantity,
    required String analysisId,
  }) async {
    final bid = selectedBranchId ?? 'main_branch';

    // 1. Find product in inventory
    final invSnap = await _db
        .collection('branches')
        .doc(bid)
        .collection('inventory')
        .where('name', isEqualTo: productName)
        .limit(1)
        .get();

    if (invSnap.docs.isEmpty)
      throw Exception('Product not found in inventory.');

    final productDoc = invSnap.docs.first;
    final stockToRecycle =
        quantity > 0 ? quantity : (productDoc.get('stock') ?? 0);

    if (stockToRecycle <= 0) throw Exception('No stock available to recycle.');

    // Use reportSpoilage with isSalvaged: true to handle the logic centrally
    await reportSpoilage(
      productId: productDoc.id,
      quantity: stockToRecycle,
      reason: 'Salvaged from low freshness scan',
      flowerName: productName,
      lossAmount: 0,
      reportedBy: 'AI Sys (Recycle Prompt)',
      isSalvaged: true,
    );

    // Mark analysis as recycled if needed (optional metadata)
    await _freshnessCollection().doc(analysisId).update({'is_recycled': true});
  }

  static Stream<List<Map<String, dynamic>>> freshnessStream(
      {String? branchId}) {
    final bid = branchId ?? (selectedBranchId ?? 'main_branch');
    Query query = _freshnessCollection();
    if (bid != 'all') {
      query = query.where('branchId', isEqualTo: bid);
    }

    return query.snapshots().map((snap) {
      final docs = snap.docs
          .map((doc) => {
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id,
              })
          .toList();

      docs.sort((a, b) {
        final dA = (a['createdAt'] ?? a['scanned_at']) as dynamic;
        final dB = (b['createdAt'] ?? b['scanned_at']) as dynamic;
        if (dA == null || dB == null) return 0;
        return (dB as Timestamp).compareTo(dA as Timestamp);
      });
      return docs;
    });
  }

  static Future<void> updateCustomerLoyalty(
      {required String customerId, required int points}) async {
    final ref = _db.collection('customers').doc(customerId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (snap.exists) {
        transaction.update(ref, {'points': (snap.get('points') ?? 0) + points});
      } else {
        transaction.set(ref, {'customerId': customerId, 'points': points});
      }
    });
  }

  static Future<void> createEmployee({
    required String uid,
    required String email,
    String? firstName,
    String? middleName,
    String? lastName,
    String? birthday,
    String? sex,
    String? employeeId,
    String? role,
    String? branchId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _usersCollection().doc(uid).set({
      'uid': uid,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'birthday': birthday,
      'sex': sex,
      'email': normalizedEmail,
      'employeeId': employeeId,
      'role': role ?? 'employee',
      'branchId': branchId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> createNewEmployee({
    required String uid,
    required String email,
    String? firstName,
    String? middleName,
    String? lastName,
    String? birthday,
    String? sex,
    String? employeeId,
    String? role,
    String? branchId,
  }) async {
    await createEmployee(
      uid: uid,
      email: email,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      birthday: birthday,
      sex: sex,
      employeeId: employeeId,
      role: role,
      branchId: branchId,
    );
  }

  static Future<void> saveTripoModel(Map<String, dynamic> tripoData) async {
    await _tripoCollection().add({
      ...tripoData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, dynamic>?> getUserData(String userId) async {
    if (userId.isEmpty) return null;
    final doc = await _usersCollection().doc(userId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['email'] == '789jojoalvarado@gmail.com' ||
          data['username'] == '789jojoalvarado@gmail.com') {
        data['role'] = 'super-admin';
      }
      return data;
    }

    // Fallback: search by current user's email if UID doc doesn't exist
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == userId && user.email != null) {
      final normalizedEmail = user.email!.trim().toLowerCase();

      // If it is the super admin, auto-provision and force-return the super-admin data
      if (normalizedEmail == '789jojoalvarado@gmail.com') {
        final superAdminData = {
          'uid': userId,
          'email': normalizedEmail,
          'username': '789jojoalvarado',
          'firstName': 'Super',
          'lastName': 'Admin',
          'role': 'super-admin',
          'branchId': 'main_branch',
          'createdAt': FieldValue.serverTimestamp(),
        };
        await _usersCollection().doc(userId).set(superAdminData);
        return superAdminData;
      }

      // First query by 'email'
      var snap = await _usersCollection()
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        // Fallback: query by 'username'
        snap = await _usersCollection()
            .where('username', isEqualTo: normalizedEmail)
            .limit(1)
            .get();
      }

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data() as Map<String, dynamic>;
        // Optional: Save the UID mapping to the existing document for future checkings
        // ignore_const_await
        await snap.docs.first.reference.update({'uid': userId});
        return data;
      }
    }
    return null;
  }

  static Future<String?> getUserRole(String userId) async {
    final data = await getUserData(userId);
    return data?['role'] as String?;
  }

  static Future<void> changePassword(String newPassword) async {
    await FirebaseAuth.instance.currentUser?.updatePassword(newPassword);
  }

  static Future<void> syncInventoryFromFirestore() async {
    // This could be a complex sync logic, for now a placeholder
    debugPrint('Syncing inventory...');
  }

  static Future<void> addBranch(Map<String, dynamic> data) async {
    await _branchesCollection().add(data);
  }

  static Future<void> updateBranch(
      String branchId, Map<String, dynamic> data) async {
    await _branchesCollection().doc(branchId).update(data);
  }

  static Future<void> deleteBranch(String branchId) async {
    await _branchesCollection().doc(branchId).delete();
  }

  static Future<Map<String, dynamic>?> getBranchDetails(String branchId) async {
    final doc = await _branchesCollection().doc(branchId).get();
    return doc.exists ? doc.data() as Map<String, dynamic> : null;
  }

  static Future<Map<String, dynamic>?> getProductById(String productId) async {
    final doc = await _inventoryCollection().doc(productId).get();
    return doc.exists
        ? {...doc.data() as Map<String, dynamic>, 'id': doc.id}
        : null;
  }

  static Future<Map<String, dynamic>?> getProductByCode(String code) async {
    // 1. Try searching in the currently selected branch with 'code' (primary field)
    try {
      var snap = await _inventoryCollection()
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      // 2. Fallback to 'sku' field if 'code' was empty
      if (snap.docs.isEmpty) {
        snap = await _inventoryCollection()
            .where('sku', isEqualTo: code)
            .limit(1)
            .get();
      }

      if (snap.docs.isNotEmpty) {
        return {
          ...snap.docs.first.data() as Map<String, dynamic>,
          'id': snap.docs.first.id
        };
      }
    } catch (e) {
      debugPrint('Error searching in selected branch: $e');
    }

    // 3. Global fallback: Search across ALL branches if not found in current one
    // We try collectionGroup first in a local try-catch to avoid crashing if composite index is missing
    try {
      final globalSnap = await _db
          .collectionGroup('inventory')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (globalSnap.docs.isNotEmpty) {
        return {
          ...globalSnap.docs.first.data() as Map<String, dynamic>,
          'id': globalSnap.docs.first.id
        };
      }

      final globalSkuSnap = await _db
          .collectionGroup('inventory')
          .where('sku', isEqualTo: code)
          .limit(1)
          .get();
      if (globalSkuSnap.docs.isNotEmpty) {
        return {
          ...globalSkuSnap.docs.first.data() as Map<String, dynamic>,
          'id': globalSkuSnap.docs.first.id
        };
      }
    } catch (e) {
      debugPrint('Collection group search failed (index might be missing): $e');
    }

    // 4. Fully compliant branch-by-branch search fallback (does NOT require any collectionGroup index)
    try {
      final branchesSnap = await _db.collection('branches').get();
      for (final branchDoc in branchesSnap.docs) {
        final bId = branchDoc.id;
        if (bId == selectedBranchId) continue; // Already searched

        final branchInventory =
            _db.collection('branches').doc(bId).collection('inventory');
        var bSnap =
            await branchInventory.where('code', isEqualTo: code).limit(1).get();
        if (bSnap.docs.isEmpty) {
          bSnap = await branchInventory
              .where('sku', isEqualTo: code)
              .limit(1)
              .get();
        }

        if (bSnap.docs.isNotEmpty) {
          return {
            ...bSnap.docs.first.data() as Map<String, dynamic>,
            'id': bSnap.docs.first.id
          };
        }
      }
    } catch (e) {
      debugPrint('Resilient branch-by-branch fallback search failed: $e');
    }

    return null;
  }

  static Future<void> migrateDataToBranch(String targetBranchId) async {
    debugPrint('Starting migration to branch: $targetBranchId');
    int totalMigrated = 0;

    // Helper to migrate a collection from source to target branch
    Future<void> migrateCollection(
        Query sourceQuery, CollectionReference targetRef) async {
      final snapshot = await sourceQuery.get();
      debugPrint(
          'Migrating ${snapshot.docs.length} docs from ${sourceQuery.parameters}');
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        // Ensure branchId is set inside the document too
        data['branchId'] = targetBranchId;
        await targetRef.doc(doc.id).set(data);
        totalMigrated++;
      }
    }

    // 1. Migrate Inventory
    await migrateCollection(
      _db.collection('branches').doc('main_branch').collection('inventory'),
      _db.collection('branches').doc(targetBranchId).collection('inventory'),
    );
    await migrateCollection(
      _db.collection('inventory'),
      _db.collection('branches').doc(targetBranchId).collection('inventory'),
    );

    // 2. Migrate Categories
    await migrateCollection(
      _db.collection('branches').doc('main_branch').collection('categories'),
      _db.collection('branches').doc(targetBranchId).collection('categories'),
    );
    await migrateCollection(
      _db.collection('categories'),
      _db.collection('branches').doc(targetBranchId).collection('categories'),
    );

    // 3. Migrate Spoilage
    await migrateCollection(
      _db.collection('branches').doc('main_branch').collection('spoilage'),
      _db.collection('branches').doc(targetBranchId).collection('spoilage'),
    );
    await migrateCollection(
      _db.collection('spoilage'),
      _db.collection('branches').doc(targetBranchId).collection('spoilage'),
    );
    // Also try root-level "inventory_spoilage" if it exists from older versions
    await migrateCollection(
      _db.collection('inventory_spoilage'),
      _db.collection('branches').doc(targetBranchId).collection('spoilage'),
    );

    // 4. Update Orders
    final orders = await _db.collection('orders').get();
    debugPrint('Checking ${orders.docs.length} orders for migration...');
    for (var doc in orders.docs) {
      final data = doc.data();
      if (data['branchId'] == null || data['branchId'] == 'main_branch') {
        await doc.reference.update({'branchId': targetBranchId});
      }
    }

    debugPrint('Migration complete. Total documents processed: $totalMigrated');
    selectedBranchId = targetBranchId;
  }

  static Future<void> seedInventoryIfEmpty() async {
    final bid = selectedBranchId ?? 'main_branch';
    final snap = await _db
        .collection('branches')
        .doc(bid)
        .collection('inventory')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      debugPrint('Seeding inventory for $bid...');
      final List<Map<String, dynamic>> initialFlowers = [
        {
          'name': 'Red Rose',
          'price': 100.0,
          'stock': 50,
          'image':
              'https://images.unsplash.com/photo-1548512406-8159fe4eb372?q=80&w=200&auto=format&fit=crop',
          'category': 'Flowers',
          'description': 'A classic deep red rose.',
          'branchId': bid,
        },
        {
          'name': 'Chivas Regal',
          'price': 450.0,
          'stock': 20,
          'image':
              'https://images.unsplash.com/photo-1514451913147-97213062635b?q=80&w=200&auto=format&fit=crop',
          'category': 'Gifts',
          'description': 'Premium selection.',
          'branchId': bid,
        },
        {
          'name': 'Teddy Bear',
          'price': 250.0,
          'stock': 30,
          'image':
              'https://images.unsplash.com/photo-1559440666-4aa49195b090?q=80&w=200&auto=format&fit=crop',
          'category': 'Stuffed Toys',
          'description': 'Soft and cuddly.',
          'branchId': bid,
        }
      ];

      for (final flower in initialFlowers) {
        await _db
            .collection('branches')
            .doc(bid)
            .collection('inventory')
            .add(flower);
      }
    }
  }

  static Future<void> updateUserRoleAndBranch(
      String email, String role, String? branchId) async {
    final normalizedEmail = email.trim().toLowerCase();
    final snapshot = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.update({
        'role': role,
        'branchId': branchId,
        'email': normalizedEmail, // Ensure it's stored normalized
      });
    } else {
      // If user doc doesn't exist yet, we add it.
      // Note: Ideally we'd have the UID, but searching by email in getUserData will find this.
      await _db.collection('users').add({
        'email': normalizedEmail,
        'role': role,
        'branchId': branchId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Auto-check expired Recycled Bouquet (2 days older) & Remove "Recycled Flowers" documents
  static Future<void> _checkExpiredRecycledBouquets(String bid) async {
    try {
      final invCol =
          _db.collection('branches').doc(bid).collection('inventory');

      // 1. Double check and cleanup of stale 'Recycled Flowers'
      final flowersSnap =
          await invCol.where('name', isEqualTo: 'Recycled Flowers').get();
      if (flowersSnap.docs.isNotEmpty) {
        final batchDel = _db.batch();
        for (var doc in flowersSnap.docs) {
          batchDel.delete(doc.reference);
        }
        await batchDel.commit();
        debugPrint('Flutter: Cleaned up Recycled Flowers in $bid.');
      }

      // 2. Scan and handle Recycled Bouquet expiration (2 days)
      final snap =
          await invCol.where('name', isEqualTo: 'Recycled Bouquet').get();
      if (snap.docs.isEmpty) return;

      final doc = snap.docs.first;
      final data = doc.data() as Map<String, dynamic>;
      final stock = data['stock'] ?? 0;
      if (stock <= 0) return;

      final dynamic timestamp = data['updatedAt'] ?? data['createdAt'];
      if (timestamp == null) return;

      final DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else {
        return;
      }

      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays >= 2) {
        final batch = _db.batch();

        // Set stock of Recycled Bouquet to 0
        batch.update(doc.reference, {
          'stock': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Add Spoilage/Loss Record
        final spoilRef =
            _db.collection('branches').doc(bid).collection('spoilage').doc();
        batch.set(spoilRef, {
          'productId': doc.id,
          'product_id': doc.id,
          'flower_name': 'Recycled Bouquet',
          'quantity': stock,
          'loss_amount': stock * (data['price'] ?? 150.0),
          'reason': 'Expired Recycled Bouquet',
          'reported_by': 'System (Auto Expiry)',
          'is_salvaged': false,
          'createdAt': FieldValue.serverTimestamp(),
          'created_at': FieldValue.serverTimestamp(),
        });

        // Add Notification
        final notifRef = _db.collection('notifications').doc();
        batch.set(notifRef, {
          'title': 'Recycled Bouquet Expired',
          'message':
              '[$bid] $stock pcs of Recycled Bouquet expired after 2 days and moved to spoilage.',
          'type': 'warning',
          'branchId': bid,
          'created_at': FieldValue.serverTimestamp(),
          'read': false,
        });

        await batch.commit();
        debugPrint(
            'Flutter: Successfully expired Recycled Bouquet inside branch: $bid ($stock pcs)');
      }
    } catch (e) {
      debugPrint('Error expiring Recycled Bouquet in Flutter: $e');
    }
  }
}
