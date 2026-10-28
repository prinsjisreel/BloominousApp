import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown for problems the customer can understand (e.g. the address book is
/// full). Anything else (network, permissions) is rethrown as-is.
class SavedAddressException implements Exception {
  final String message;
  SavedAddressException(this.message);

  @override
  String toString() => message;
}

/// Turns any way of typing a Philippine mobile number into the 11-digit
/// "09XXXXXXXXX" shape the web address book stores.
///   "+63 917 123 4567" -> "09171234567"      "9171234567" -> "09171234567"
/// Anything that does not look like a PH mobile number is returned as digits only.
String normalizePhPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('63') && digits.length == 12) {
    digits = '0${digits.substring(2)}';
  } else if (digits.length == 10 && digits.startsWith('9')) {
    digits = '0$digits';
  }
  return digits;
}

/// One saved delivery address: customers/{uid}/addresses/{addressId}.
///
/// SHARED WEB + APP CONTRACT: field names, limits and nullability match
/// `isValidSavedAddress()` in firestore.rules and the address book in
/// templates/checkout.php. An address saved on the website shows up in the app
/// and the other way round.
class SavedAddress {
  final String id; // '' while the address has not been saved yet
  final String fullName;
  final String phone;
  final String address; // the one-line text the order carries
  final String? regionCode;
  final String regionName;
  final String? provinceCode;
  final String provinceName; // 'Metro Manila' when the region has no provinces
  final String? cityCode;
  final String cityName;
  final String barangay;
  final String street;
  final String postalCode; // '' when unknown (the rules want a string, not null)
  final double? destLat; // the map point the delivery fee was calculated from
  final double? destLng;
  final bool isDefault;
  final DateTime? updatedAt;

  const SavedAddress({
    this.id = '',
    required this.fullName,
    required this.phone,
    required this.address,
    this.regionCode,
    required this.regionName,
    this.provinceCode,
    this.provinceName = '',
    this.cityCode,
    required this.cityName,
    required this.barangay,
    required this.street,
    this.postalCode = '',
    this.destLat,
    this.destLng,
    this.isDefault = false,
    this.updatedAt,
  });

  /// Reads one Firestore document defensively: a missing or oddly-typed field
  /// becomes an empty value instead of crashing the whole list.
  factory SavedAddress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};

    String text(String key) => (d[key] ?? '').toString();
    String? optionalText(String key) {
      final v = d[key];
      return (v is String && v.isNotEmpty) ? v : null;
    }

    double? number(String key) {
      final v = d[key];
      return v is num ? v.toDouble() : null;
    }

    final rawUpdated = d['updatedAt'];

    return SavedAddress(
      id: doc.id,
      fullName: text('fullName'),
      phone: text('phone'),
      address: text('address'),
      regionCode: optionalText('regionCode'),
      regionName: text('regionName'),
      provinceCode: optionalText('provinceCode'),
      provinceName: text('provinceName'),
      cityCode: optionalText('cityCode'),
      cityName: text('cityName'),
      barangay: text('barangay'),
      street: text('street'),
      postalCode: text('postalCode'),
      destLat: number('destLat'),
      destLng: number('destLng'),
      isDefault: d['isDefault'] == true,
      updatedAt: rawUpdated is Timestamp ? rawUpdated.toDate() : null,
    );
  }

  /// Only the keys firestore.rules allows (`hasOnly`), nothing more.
  /// createdAt is added separately, and only when the address is brand new.
  Map<String, dynamic> toMap({required bool isDefault}) {
    return {
      'fullName': fullName,
      'phone': phone,
      'address': address,
      'regionCode': regionCode,
      'regionName': regionName,
      'provinceCode': provinceCode,
      'provinceName': provinceName,
      'cityCode': cityCode,
      'cityName': cityName,
      'barangay': barangay,
      'street': street,
      'postalCode': postalCode,
      'destLat': destLat,
      'destLng': destLng,
      'isDefault': isDefault,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Same street + same phone = the same saved address (used to avoid saving
  /// the identical address twice after repeat orders).
  bool sameAs(String otherAddress, String otherPhone) {
    String clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return clean(address) == clean(otherAddress) &&
        normalizePhPhone(phone) == normalizePhPhone(otherPhone);
  }
}

/// The customer's address book. Every method works on the SIGNED-IN customer's
/// own folder only, which is exactly what firestore.rules allows (`isOwner`).
class SavedAddressService {
  /// Same cap the website enforces on screen.
  static const int maxAddresses = 10;

  static CollectionReference<Map<String, dynamic>>? _collection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('customers').doc(uid).collection('addresses');
  }

  /// Default address first, then the most recently changed.
  /// Sorted on the phone so Firestore needs no composite index.
  static List<SavedAddress> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(SavedAddress.fromDoc).toList();
    list.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  /// Live list: the sheet redraws by itself after every add / edit / delete.
  static Stream<List<SavedAddress>> watch() {
    final col = _collection();
    if (col == null) return Stream.value(const <SavedAddress>[]);
    return col.snapshots().map(_sorted);
  }

  /// One-time read (used when the checkout opens).
  static Future<List<SavedAddress>> fetchAll() async {
    final col = _collection();
    if (col == null) return const <SavedAddress>[];
    return _sorted(await col.get());
  }

  /// Creates a new address (when [address.id] is empty) or updates an existing one.
  /// Returns the document id.
  ///
  /// Keeps "only ONE default address" true: when this address becomes the
  /// default, every other default is switched off in the SAME batch, so the
  /// book can never be left with two defaults or none halfway through.
  static Future<String> save(SavedAddress address, {bool makeDefault = false}) async {
    final col = _collection();
    if (col == null) throw SavedAddressException('Please sign in to save addresses.');

    final existing = await col.get();
    final isNew = address.id.isEmpty;

    if (isNew && existing.docs.length >= maxAddresses) {
      throw SavedAddressException(
          'Your address book is full ($maxAddresses addresses). Delete one to save a new address.');
    }

    // The very first address is always the default.
    final becomesDefault = makeDefault || existing.docs.isEmpty || address.isDefault;

    final ref = isNew ? col.doc() : col.doc(address.id);
    final batch = FirebaseFirestore.instance.batch();

    if (becomesDefault) {
      for (final other in existing.docs) {
        if (other.id != ref.id && other.data()['isDefault'] == true) {
          batch.update(other.reference, {
            'isDefault': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    final data = address.toMap(isDefault: becomesDefault);
    if (isNew) {
      batch.set(ref, {...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      batch.set(ref, data, SetOptions(merge: true));
    }

    await batch.commit();
    return ref.id;
  }

  /// Makes [id] the one default address (and un-defaults the rest) in one batch.
  static Future<void> setDefault(String id) async {
    final col = _collection();
    if (col == null) throw SavedAddressException('Please sign in to manage addresses.');

    final all = await col.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in all.docs) {
      final shouldBeDefault = doc.id == id;
      if ((doc.data()['isDefault'] == true) != shouldBeDefault) {
        batch.update(doc.reference, {
          'isDefault': shouldBeDefault,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  /// Deletes an address. If it was the default and others remain, the most
  /// recently changed one becomes the new default, so the book never has
  /// addresses but no default.
  static Future<void> delete(String id) async {
    final col = _collection();
    if (col == null) throw SavedAddressException('Please sign in to manage addresses.');

    final all = _sorted(await col.get());
    final target = all.where((a) => a.id == id).toList();
    if (target.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(col.doc(id));

    if (target.first.isDefault) {
      final remaining = all.where((a) => a.id != id).toList();
      if (remaining.isNotEmpty) {
        batch.update(col.doc(remaining.first.id), {
          'isDefault': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}
