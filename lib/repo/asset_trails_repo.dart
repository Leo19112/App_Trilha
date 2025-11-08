import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gpx/gpx.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../data/trail_models.dart';
import 'dart:math';

class AssetTrailsRepo {
  AssetTrailsRepo._();
  static final instance = AssetTrailsRepo._();

  List<TrailSummary>? _cacheSummaries;
  final Map<String, TrailData> _cacheData = {};

  Future<List<TrailSummary>> listAll() async {
    if (_cacheSummaries != null) return _cacheSummaries!;
    final txt = await rootBundle.loadString('assets/trails/index.json');
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final list = (j['trails'] as List).cast<Map<String, dynamic>>();
    _cacheSummaries = list.map(TrailSummary.fromJson).toList();
    return _cacheSummaries!;
  }

  Future<TrailData> loadById(String id) async {
    if (_cacheData.containsKey(id)) return _cacheData[id]!;

    final all = await listAll();
    final s = all.firstWhere((e) => e.id == id);

    final gpxText = await rootBundle.loadString('assets/trails/${s.file}');
    final gpx = GpxReader().fromString(gpxText);

    final line = <LatLng>[];
    final wpts = <LatLng>[];

    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat != null && pt.lon != null) {
            line.add(LatLng(pt.lat!, pt.lon!));
          }
        }
      }
    }
    for (final w in gpx.wpts) {
      if (w.lat != null && w.lon != null) {
        wpts.add(LatLng(w.lat!, w.lon!));
      }
    }

    // Se length_km não vier no index, calcula uma estimativa rápida
    double? lengthKm = s.lengthKm ?? _estimateLengthKm(line);
    final filledSummary = TrailSummary(
      id: s.id,
      name: s.name,
      file: s.file,
      region: s.region,
      lengthKm: lengthKm,
      start: s.start ?? (line.isNotEmpty ? line.first : null),
    );

    final data = TrailData(summary: filledSummary, line: line, waypoints: wpts);
    _cacheData[id] = data;
    return data;
  }

  double? _estimateLengthKm(List<LatLng> line) {
    if (line.length < 2) return null;
    double dist = 0;
    const R = 6371.0;
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1];
      final b = line[i];
      final dLat = _deg2rad(b.latitude - a.latitude);
      final dLon = _deg2rad(b.longitude - a.longitude);
      final la1 = _deg2rad(a.latitude);
      final la2 = _deg2rad(b.latitude);
      final h = (1 - cos(dLat)) / 2 + cos(la1) * cos(la2) * (1 - cos(dLon)) / 2;
      dist += 2 * R * asin(sqrt(h));
    }
    return double.parse(dist.toStringAsFixed(2));
  }

  double _deg2rad(double d) => d * (3.141592653589793 / 180.0);
}
