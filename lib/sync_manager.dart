import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_db.dart';
import 'connectivity_service.dart';
import 'inventory_data.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final _syncStatusController = StreamController<bool>.broadcast();
  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  bool _isSyncing = false;

  void init() {
    connectivityService.statusStream.listen((status) {
      if (status == ConnectivityStatus.online) {
        syncData();
      }
    });

    // Also populate initial inventory cache if empty
    _initialCache();
  }

  Future<void> _initialCache() async {
    final count = await LocalDB.query('inventory');
    if (count.isEmpty) {
      print('Populating initial inventory cache...');
      await InventoryData.syncInventoryFromFirestore();
    }
  }

  Future<void> syncData() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _syncStatusController.add(true);
    print('Starting background sync...');

    try {
      await _syncInventory();
      await _syncOrders();
      await _syncSpoilage();
      await _syncFreshness();
    } catch (e) {
      print('Sync failed: $e');
    } finally {
      _isSyncing = false;
      _syncStatusController.add(false);
      print('Sync process finished.');
    }
  }

  Future<void> _syncInventory() async {
    final unsynced =
        await LocalDB.query('inventory', where: 'isSynced = ?', whereArgs: [0]);
    for (var item in unsynced) {
      final id = item['id'] as String;
      try {
        final data = Map<String, dynamic>.from(item);
        data.remove('id');
        data.remove('isSynced');

        await FirebaseFirestore.instance.collection('inventory').doc(id).set({
          ...data,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await LocalDB.update('inventory', {'isSynced': 1}, id);
      } catch (e) {
        print('Error syncing inventory item: $id - $e');
      }
    }
  }

  Future<void> _syncOrders() async {
    final unsynced =
        await LocalDB.query('orders', where: 'isSynced = ?', whereArgs: [0]);
    for (var order in unsynced) {
      final id = order['id'] as String;
      try {
        final data = Map<String, dynamic>.from(order);
        data.remove('id');
        data.remove('isSynced');

        // Decode items if it was encoded
        dynamic items = data['items'];
        if (items is String) {
          items = jsonDecode(items);
          data['items'] = items;
        }

        final batch = FirebaseFirestore.instance.batch();

        // 1. Upload Order
        batch.set(
            FirebaseFirestore.instance.collection('orders').doc(id),
            {
              ...data,
              'isSynced': true,
              'createdAt': data['createdAt'] != null
                  ? DateTime.parse(data['createdAt'])
                  : FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        // 2. Decrement Stocks in Cloud
        if (items is List) {
          for (var item in items) {
            final productId = item['id'];
            final quantity = item['quantity'] ?? 1;
            batch.update(
                FirebaseFirestore.instance
                    .collection('inventory')
                    .doc(productId),
                {
                  'stock': FieldValue.increment(-quantity),
                });
          }
        }

        await batch.commit();
        await LocalDB.update('orders', {'isSynced': 1}, id);
      } catch (e) {
        print('Error syncing order: $id - $e');
      }
    }
  }

  Future<void> _syncSpoilage() async {
    final unsynced =
        await LocalDB.query('spoilage', where: 'isSynced = ?', whereArgs: [0]);
    for (var record in unsynced) {
      final id = record['id'] as String;
      final productId = record['product_id'] as String;
      final quantity = record['quantity'] as int;
      final flowerName = record['flower_name'] as String;
      final reason = record['reason'] as String;

      try {
        final data = Map<String, dynamic>.from(record);
        data.remove('id');
        data.remove('isSynced');

        final batch = FirebaseFirestore.instance.batch();

        // 1. Upload spoilage report
        final spoilageRef =
            FirebaseFirestore.instance.collection('spoilage').doc(id);
        batch.set(spoilageRef, {
          ...data,
          'isSynced': true,
          'created_at': data['created_at'] != null
              ? DateTime.parse(data['created_at'])
              : FieldValue.serverTimestamp(),
        });

        // 2. Decrement Firestore stock
        final inventoryRef =
            FirebaseFirestore.instance.collection('inventory').doc(productId);
        batch.update(inventoryRef, {
          'stock': FieldValue.increment(-quantity),
        });

        // 3. Create Notification
        final notifRef =
            FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(notifRef, {
          'title': 'Spoilage Synced',
          'message':
              '$quantity pcs of $flowerName reported as spoiled ($reason).',
          'type': 'warning',
          'created_at': FieldValue.serverTimestamp(),
          'read': false,
        });

        await batch.commit();
        await LocalDB.update('spoilage', {'isSynced': 1}, id);
      } catch (e) {
        print('Error syncing spoilage item $id: $e');
      }
    }
  }

  Future<void> _syncFreshness() async {
    final unsynced = await LocalDB.query('freshness_analysis',
        where: 'isSynced = ?', whereArgs: [0]);
    for (var record in unsynced) {
      final id = record['id'] as String;
      try {
        final data = Map<String, dynamic>.from(record);
        data.remove('id');
        data.remove('isSynced');

        await FirebaseFirestore.instance
            .collection('freshness_analysis')
            .doc(id)
            .set({
          ...data,
          'isSynced': true,
          'scanned_at': data['scanned_at'] != null
              ? DateTime.parse(data['scanned_at'])
              : FieldValue.serverTimestamp(),
        });

        await LocalDB.update('freshness_analysis', {'isSynced': 1}, id);
      } catch (e) {
        print('Error syncing freshness record $id: $e');
      }
    }
  }
}

final syncManager = SyncManager();
