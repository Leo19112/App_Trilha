class MapStyle {
  final String id;
  final String label;
  const MapStyle(this.id, this.label);
}

class MapStyleService {
  final String apiKey;
  static const defaultStyleId = 'outdoor-v2';

  static const styles = <MapStyle>[
    MapStyle('outdoor-v2', 'Outdoor'),
    MapStyle('topo-v2', 'Topográfico'),
    MapStyle('hybrid', 'Híbrido'),
    MapStyle('satellite', 'Satélite'),
    MapStyle('streets-v2', 'Streets'),
  ];

  MapStyleService(this.apiKey);

  String styleUrl(String styleId) =>
      'https://api.maptiler.com/maps/$styleId/style.json?key=$apiKey';
}
