import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GoogleMapsService {
  // To use this, add your GOOGLE_MAP_API_KEY to your environment or replace here
  static const String _apiKey =
      String.fromEnvironment('GOOGLE_MAPS_PLATFORM_KEY', defaultValue: '');

  static Future<Map<String, dynamic>> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    if (_apiKey.isEmpty) {
      throw 'Google Maps API Key is missing. Please add GOOGLE_MAPS_PLATFORM_KEY to your secrets.';
    }

    final url = Uri.parse('https://routes.googleapis.com/v2:computeRoutes');

    final body = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": originLat,
            "longitude": originLng,
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": destLat,
            "longitude": destLng,
          }
        }
      },
      "travelMode": "DRIVING",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,
      "routeModifiers": {
        "avoidTolls": true,
        "avoidHighways": false,
        "avoidFerries": false
      },
      "languageCode": "en-US",
      "units": "METRIC"
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final distanceMeters = route['distanceMeters'] as int;
        return {
          'distanceKm': distanceMeters / 1000.0,
          'duration': route['duration'],
          'polyline': route['polyline']['encodedPolyline'],
        };
      }
      throw 'No routes found';
    } else {
      debugPrint('Routes API Error: ${response.body}');
      throw 'Failed to calculate route: ${response.statusCode}';
    }
  }
}
