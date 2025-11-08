class TrailItem {
  final String name;
  final double distanceKm;
  final int difficulty; // 1..3

  const TrailItem({
    required this.name,
    required this.distanceKm,
    required this.difficulty,
  });
}
