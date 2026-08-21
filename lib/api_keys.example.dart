// lib/api_keys.example.dart
//
// ============================================================
// TEMPLATE FILE -- this one IS safe to commit to Git.
// ============================================================
// It contains no real keys, only placeholders, so it documents what
// this project needs without exposing anything.
//
// SETUP: copy this file to api_keys.dart (same lib/ folder), then
// replace the placeholder strings below with your real keys.
// api_keys.dart is gitignored and will never be pushed.

class ApiKeys {
  // Get this from Google AI Studio: https://aistudio.google.com/apikey
  static const String geminiApiKey = 'PASTE_YOUR_GEMINI_API_KEY_HERE';

  // Get this from https://platform.stability.ai -> API Keys
  static const String stabilityApiKey = 'PASTE_YOUR_STABILITY_API_KEY_HERE';

  // Get this from PayMongo Dashboard -> Settings -> Developers
  static const String paymongoSecretKey = 'PASTE_YOUR_PAYMONGO_SECRET_KEY_HERE';

  // Get this from https://www.pexels.com/api -> your API key
  static const String pexelsApiKey = 'PASTE_YOUR_PEXELS_API_KEY_HERE';
}