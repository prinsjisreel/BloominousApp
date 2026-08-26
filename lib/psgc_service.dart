import 'dart:convert';
import 'package:http/http.dart' as http;

/// A single entry from the PSGC (Philippine Standard Geographic Code)
/// directory — a region, province, city/municipality, or barangay.
class PsgcItem {
  final String code;
  final String name;
  const PsgcItem({required this.code, required this.name});
}

/// Mirrors checkout.php's loadRegions()/loadProvinces()/loadCities()/
/// loadBarangays() exactly — same free, no-API-key government directory,
/// same special-case handling for Metro Manila (which has no province
/// level and returns cities/municipalities directly).
class PsgcService {
  static const String _baseUrl = 'https://psgc.gitlab.io/api';
  static const String metroManilaRegionCode = '130000000';

  static List<PsgcItem> _parseAndSort(String body) {
    final data = jsonDecode(body) as List;
    final items = data
        .map((e) => PsgcItem(code: e['code'] as String, name: e['name'] as String))
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  static Future<List<PsgcItem>> getRegions() async {
    final res = await http.get(Uri.parse('$_baseUrl/regions/'));
    if (res.statusCode != 200) throw 'Failed to load regions';
    return _parseAndSort(res.body);
  }

  /// Metro Manila skips the province level entirely — this returns its
  /// cities/municipalities directly instead, with isMetroManila=true so
  /// the caller knows to hide the province dropdown for this selection.
  static Future<({List<PsgcItem> items, bool isMetroManila})> getProvincesOrCities(
      String regionCode) async {
    if (regionCode == metroManilaRegionCode) {
      final res = await http
          .get(Uri.parse('$_baseUrl/regions/$regionCode/cities-municipalities/'));
      if (res.statusCode != 200) throw 'Failed to load cities';
      return (items: _parseAndSort(res.body), isMetroManila: true);
    }

    final res = await http.get(Uri.parse('$_baseUrl/regions/$regionCode/provinces/'));
    if (res.statusCode != 200) throw 'Failed to load provinces';
    return (items: _parseAndSort(res.body), isMetroManila: false);
  }

  static Future<List<PsgcItem>> getCities(String provinceCode) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/provinces/$provinceCode/cities-municipalities/'));
    if (res.statusCode != 200) throw 'Failed to load cities';
    return _parseAndSort(res.body);
  }

  static Future<List<PsgcItem>> getBarangays(String cityCode) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/cities-municipalities/$cityCode/barangays/'));
    if (res.statusCode != 200) throw 'Failed to load barangays';
    return _parseAndSort(res.body);
  }
}