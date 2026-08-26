import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceSecurityService {
  // 'customer' is the default so AuthPage's existing calls
  // (DeviceSecurityService()) keep using the exact same keys
  // they already use — no migration needed for existing users.
  final String scope;
  DeviceSecurityService({this.scope = 'customer'});

  static const String _deviceIdKey = 'bloom_device_id';

  // Keys are namespaced per scope, except 'customer' which stays
  // on the original unprefixed keys for backward compatibility.
  String get _attemptsKey =>
      scope == 'customer' ? 'login_attempts' : 'login_attempts_$scope';
  String get _lockoutLevelKey =>
      scope == 'customer' ? 'lockout_level' : 'lockout_level_$scope';
  String get _lockoutUntilKey =>
      scope == 'customer' ? 'lockout_until' : 'lockout_until_$scope';

  /// Returns a stable, per-device identifier as a SHA-256 hex digest
  /// (64 lowercase hex chars) — matching the exact shape web's
  /// device_fingerprint.js produces, and specifically the shape
  /// submit_order.php's `preg_match('/^[a-f0-9]{64}$/', ...)` validates
  /// against. The underlying random UUID is still generated and stored
  /// exactly as before (so this identity is stable across app restarts,
  /// same as always) — it's only hashed at the point of returning it, so
  /// every consumer of this value (banned_devices lookups, the
  /// `deviceHashes` array on customer docs, submit_order.php) sees a
  /// consistent, correctly-shaped value.
  Future<String> getDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    final bytes = utf8.encode(deviceId);
    return sha256.convert(bytes).toString();
  }

  Future<Map<String, dynamic>> checkRateLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_lockoutUntilKey) ?? 0;
    final level = prefs.getInt(_lockoutLevelKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < lockoutUntil) {
      return {
        'locked': true,
        'superAdminLock': level >= 4,
        'remainingSeconds': ((lockoutUntil - now) / 1000).ceil(),
      };
    }
    return {'locked': false};
  }

  Future<void> recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    int attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
    int level = prefs.getInt(_lockoutLevelKey) ?? 0;

    await prefs.setInt(_attemptsKey, attempts);

    if (attempts >= 3 && level == 0) {
      await _applyLockout(prefs, 1, 15);
    } else if (attempts >= 1 && level == 1) {
      await _applyLockout(prefs, 2, 30);
    } else if (attempts >= 1 && level == 2) {
      await _applyLockout(prefs, 3, 60);
    } else if (attempts >= 1 && level >= 3) {
      await _applyLockout(prefs, 4, 3600); // 1 Hour + Super Admin Lock
    }
  }

  Future<void> _applyLockout(
      SharedPreferences prefs, int newLevel, int seconds) async {
    final lockoutUntil =
        DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
    await prefs.setInt(_lockoutUntilKey, lockoutUntil);
    await prefs.setInt(_lockoutLevelKey, newLevel);
    await prefs.setInt(_attemptsKey, 0);
  }

  Future<void> resetAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptsKey);
    await prefs.remove(_lockoutLevelKey);
    await prefs.remove(_lockoutUntilKey);
  }
}