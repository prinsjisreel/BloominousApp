import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceSecurityService {
  static const String _deviceIdKey = 'bloom_device_id';
  static const String _attemptsKey = 'login_attempts';
  static const String _lockoutLevelKey = 'lockout_level';
  static const String _lockoutUntilKey = 'lockout_until';

  Future<String> getDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
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

  Future<void> _applyLockout(SharedPreferences prefs, int newLevel, int seconds) async {
    final lockoutUntil = DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
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