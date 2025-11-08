import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _sub;

  Future<bool> ensureServiceAndPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      return false;
    }
    return true;
  }

  Stream<Position> startPositionStream({
    LocationSettings? settings,
    required void Function(Position) onData,
    void Function(Object, StackTrace)? onError,
  }) {
    _sub?.cancel();
    final ls =
        settings ??
        const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
        );
    final stream = Geolocator.getPositionStream(locationSettings: ls);
    _sub = stream.listen(onData, onError: onError, cancelOnError: false);
    return stream;
  }

  Future<Position?> getCurrent() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
