import 'package:maplibre_gl/maplibre_gl.dart';

class TrailSummary {
  final String id;
  final String name;
  final String file; // nome do .gpx em assets/trails/
  final String? region;
  final double? lengthKm;
  final LatLng? start;

  TrailSummary({
    required this.id,
    required this.name,
    required this.file,
    this.region,
    this.lengthKm,
    this.start,
  });

  factory TrailSummary.fromJson(Map<String, dynamic> j) => TrailSummary(
    id: j['id'],
    name: j['name'],
    file: j['file'],
    region: j['region'],
    lengthKm: (j['length_km'] as num?)?.toDouble(),
    start: (j['start'] != null)
        ? LatLng(j['start']['lat'] * 1.0, j['start']['lon'] * 1.0)
        : null,
  );
}

class TrailData {
  final TrailSummary summary;
  final List<LatLng> line;
  final List<LatLng> waypoints;

  TrailData({
    required this.summary,
    required this.line,
    required this.waypoints,
  });
}
