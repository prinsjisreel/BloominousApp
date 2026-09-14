import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory_data.dart';

/// Records an entry to the admin_actions audit log every time a
/// privileged action is taken from the admin dashboard. Append-only —
/// firestore.rules blocks any update/delete on this collection, even
/// by admins, so an entry can never be edited or removed after the fact.
///
/// Best-effort by design: a logging failure must NEVER block or roll
/// back the real action it's trying to record. Losing one audit entry
/// to a network blip is an acceptable cost; losing the ability to
/// restrict a fraudulent account because logging failed is not.
class AdminAuditService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> logAction({
    required String action,
    required String targetUid,
    String? targetEmail,
    String? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Read the actor's OWN real role the same way the rest of the app
      // does — this is what gets checked server-side against
      // isValidAuditEntry()'s actorRole == getRole() requirement.
      final role = await InventoryData.getUserRole(user.uid) ?? 'unknown';

      await _db.collection('admin_actions').add({
        'actorUid': user.uid,
        'actorEmail': user.email ?? '',
        'actorRole': role,
        'action': action,
        'targetUid': targetUid,
        'targetEmail': targetEmail,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('AdminAuditService.logAction failed (action not blocked): $e');
    }
  }
}