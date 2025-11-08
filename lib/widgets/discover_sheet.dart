import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/trail_item.dart'; // mantido se quiser usar depois
import '../data/trail_models.dart';
import '../state/selected_trail.dart';
import '../repo/asset_trails_repo.dart';

class DiscoverSheet extends StatefulWidget {
  final LatLng coordinate;
  final double? elevationMeters;
  final List<TrailItem> nearby; // (não usamos na nova “Trilhas próximas”)

  const DiscoverSheet({
    super.key,
    required this.coordinate,
    required this.elevationMeters,
    required this.nearby,
  });

  @override
  State<DiscoverSheet> createState() => _DiscoverSheetState();
}

class _DiscoverSheetState extends State<DiscoverSheet>
    with SingleTickerProviderStateMixin {
  static const double _nearbyRadiusKm = 100.0;

  // Um único controller para TabBar/TabBarView
  late final TabController _tab = TabController(length: 3, vsync: this);

  // Catálogo dos assets
  List<TrailSummary> _all = [];
  bool _loadingAll = true;

  // Trilhas a até 100 km do usuário (ordenadas por proximidade)
  List<_NearbyAssetTrail> _nearby100 = [];
  bool _loadingNearby = true;

  @override
  void initState() {
    super.initState();
    _loadAssetsAndNearby();
  }

  Future<void> _loadAssetsAndNearby() async {
    setState(() {
      _loadingAll = true;
      _loadingNearby = true;
    });

    final list = await AssetTrailsRepo.instance.listAll();
    _all = list;
    _loadingAll = false;

    // calcula próximas (100 km) pelo ponto inicial da trilha
    final here = widget.coordinate;
    final items = <_NearbyAssetTrail>[];

    for (final s in list) {
      LatLng? start = s.start;
      if (start == null) {
        final data = await AssetTrailsRepo.instance.loadById(s.id);
        start =
            data.summary.start ??
            (data.line.isNotEmpty ? data.line.first : null);
      }
      if (start == null) continue;

      final d = _haversineKm(here, start);
      if (d <= _nearbyRadiusKm) items.add(_NearbyAssetTrail(summary: s, km: d));
    }

    items.sort((a, b) => a.km.compareTo(b.km));
    setState(() {
      _nearby100 = items;
      _loadingNearby = false;
    });
  }

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
    double rad(double d) => d * (pi / 180.0);
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final la1 = rad(a.latitude);
    final la2 = rad(b.latitude);
    final h = (1 - cos(dLat)) / 2 + cos(la1) * cos(la2) * (1 - cos(dLon)) / 2;
    return 2 * R * asin(sqrt(h));
  }

  void _selectTrail(String id) {
    selectedTrailId.select(id);
    Navigator.of(context).maybePop(); // opcional: fecha o sheet
  }

  void _copyCoords() {
    final lat = widget.coordinate.latitude.toStringAsFixed(5);
    final lon = widget.coordinate.longitude.toStringAsFixed(5);
    Clipboard.setData(ClipboardData(text: '$lat, $lon'));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Coordenadas copiadas')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) {
          return Material(
            elevation: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                // Handle
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Tabs
                TabBar(
                  controller: _tab,
                  labelColor: Colors.black87,
                  unselectedLabelColor: Colors.black54,
                  tabs: const [
                    Tab(text: 'Visão geral'),
                    Tab(text: 'Trilhas próximas'),
                    Tab(text: 'Clima'),
                  ],
                ),

                // Coordenadas/Elevação: visíveis APENAS na aba 0 (Visão geral)
                AnimatedBuilder(
                  animation: _tab,
                  builder: (_, __) {
                    final showInfo = _tab.index == 0;
                    return showInfo
                        ? _InfoHeader(
                            coordinate: widget.coordinate,
                            elevationMeters: widget.elevationMeters,
                            onCopy: _copyCoords,
                          )
                        : const SizedBox.shrink();
                  },
                ),

                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      // VISÃO GERAL
                      _OverviewTab(
                        loadingNearby: _loadingNearby,
                        nearby100: _nearby100.take(3).toList(), // máx. 3
                        radiusKm: _nearbyRadiusKm,
                        onSeeAllNearby: () => _tab.animateTo(1),
                        onSelect: _selectTrail,
                      ),

                      // TRILHAS PRÓXIMAS — TODAS as trilhas no raio de 100 km (sem coords/elevação)
                      _NearbyAssetsTab(
                        loading: _loadingNearby,
                        items: _nearby100,
                        onSelect: _selectTrail,
                        scroll: scroll,
                        radiusKm: _nearbyRadiusKm,
                      ),

                      // CLIMA (placeholder)
                      const _WeatherTab(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  final LatLng coordinate;
  final double? elevationMeters;
  final VoidCallback onCopy;

  const _InfoHeader({
    required this.coordinate,
    required this.elevationMeters,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final lat = coordinate.latitude.toStringAsFixed(5);
    final lon = coordinate.longitude.toStringAsFixed(5);
    final elev = elevationMeters != null
        ? '${elevationMeters!.toStringAsFixed(0)} m'
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x11000000)),
          bottom: BorderSide(color: Color(0x11000000)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, color: Colors.black54, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Coordenadas',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '$lat, $lon',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onCopy, child: const Text('Copiar')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.terrain, color: Colors.black54, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Elevação',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(elev, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final bool loadingNearby;
  final List<_NearbyAssetTrail> nearby100; // já limitado a 3
  final double radiusKm;
  final VoidCallback onSeeAllNearby;
  final void Function(String id) onSelect;

  const _OverviewTab({
    required this.loadingNearby,
    required this.nearby100,
    required this.radiusKm,
    required this.onSeeAllNearby,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              'Trilhas próximas (até ${radiusKm.toStringAsFixed(0)} km)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const Spacer(),
            TextButton(
              onPressed: onSeeAllNearby,
              child: const Text('Ver todas'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (loadingNearby)
          const _SkeletonList(count: 3)
        else if (nearby100.isEmpty)
          const Text('Nenhuma trilha embarcada neste raio.')
        else
          ...nearby100.map(
            (n) => _TrailCard(
              summary: n.summary,
              trailing: Text('${n.km.toStringAsFixed(1)} km'),
              onTap: () => onSelect(n.summary.id),
            ),
          ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Resumo do local',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'Aqui você vê suas coordenadas e elevação (acima) e até 3 trilhas num raio de 100 km. '
          'Toque em "Ver todas" para abrir a aba Trilhas próximas.',
        ),
      ],
    );
  }
}

/// Aba "Trilhas próximas": todas as trilhas dentro de 100 km (sem coordenadas/elevação)
class _NearbyAssetsTab extends StatelessWidget {
  final bool loading;
  final List<_NearbyAssetTrail> items;
  final void Function(String id) onSelect;
  final ScrollController scroll;
  final double radiusKm;

  const _NearbyAssetsTab({
    required this.loading,
    required this.items,
    required this.onSelect,
    required this.scroll,
    required this.radiusKm,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: _SkeletonList(count: 5),
      );
    }
    if (items.isEmpty) {
      return const Center(child: Text('Nenhuma trilha embarcada neste raio.'));
    }

    return ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (ctx, i) {
        final n = items[i];
        return _TrailCard(
          summary: n.summary,
          trailing: Text('${n.km.toStringAsFixed(1)} km'),
          onTap: () => onSelect(n.summary.id),
        );
      },
    );
  }
}

class _TrailCard extends StatelessWidget {
  final TrailSummary summary;
  final Widget? trailing;
  final VoidCallback onTap;

  const _TrailCard({required this.summary, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (summary.region != null) summary.region!,
      if (summary.lengthKm != null) '${summary.lengthKm} km',
    ].join(' • ');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3FF),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.route, color: Color(0xFF2B5FFF)),
        ),
        title: Text(summary.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle.isEmpty ? 'Trilha embarcada' : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing ?? const Icon(Icons.map),
        onTap: onTap,
      ),
    );
  }
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Clima: integrar depois.'));
  }
}

class _NearbyAssetTrail {
  final TrailSummary summary;
  final double km;
  _NearbyAssetTrail({required this.summary, required this.km});
}

class _SkeletonList extends StatelessWidget {
  final int count;
  const _SkeletonList({this.count = 3});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0x0F000000),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
