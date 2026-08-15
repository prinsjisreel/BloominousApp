import 'sound_helper_stub.dart'
    if (dart.library.js) 'sound_helper_web.dart'
    if (dart.library.io) 'sound_helper_mobile.dart';

class SoundHelper {
  static void playBeep() {
    try {
      playPlatformScannerBeep();
    } catch (e) {
      // Safe fallback
    }
  }
}
