import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../services/location_service.dart';
import '../../services/map_style_service.dart';
import '../../widgets/app_side_drawer.dart';
import '../../widgets/discover_sheet.dart';
import '../../models/trail_item.dart';

// NOVO: estado e repositório das trilhas embarcadas
import '../../state/selected_trail.dart';
import '../../repo/asset_trails_repo.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _controllerCompleter = Completer<MapLibreMapController>();

  // Serviços
  late final LocationService _locationService;
  late final MapStyleService _styleService;

  // Estado do mapa
  bool _styleLoaded = false;
  LatLng? _lastLatLng;
  CameraPosition? _camera;
  double _bearing = 0.0;

  // Minha posição (círculo)
  Circle? _meCircle;
  bool _locEnabled = false;

  // ===== NOVO: Desenho da trilha selecionada =====
  Line? _currentLine;
  final List<Symbol> _currentSymbols = [];

  // Estilo
  String _styleId = MapStyleService.defaultStyleId;

  // Chave MapTiler via --dart-define
  String get _apiKey =>
      const String.fromEnvironment('MAPTILER_KEY', defaultValue: '');

  String get _styleString => _styleService.styleUrl(_styleId);

  static const _initial = CameraPosition(
    target: LatLng(-22.5697, -47.4010),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _locationService = LocationService();
    _styleService = MapStyleService(_apiKey);

    // NOVO: escuta seleção de trilha disparada pelo DiscoverSheet
    selectedTrailId.addListener(_onSelectedTrailChanged);
  }

  @override
  void dispose() {
    _locationService.stop();
    // NOVO: remove listener
    selectedTrailId.removeListener(_onSelectedTrailChanged);
    super.dispose();
  }

  Future<MapLibreMapController?> _ctl() async {
    if (!_styleLoaded) return null;
    if (!_controllerCompleter.isCompleted) return null;
    return _controllerCompleter.future;
  }

  // ===== helpers para o círculo =====
  CircleOptions _meOptions(LatLng at) => CircleOptions(
    geometry: at,
    circleColor: '#1378ff',
    circleOpacity: 0.9,
    circleRadius: 7.0,
    circleStrokeWidth: 2.0,
    circleStrokeColor: '#ffffff',
  );

  Future<void> _updateMeCircle(LatLng at) async {
    final ctl = await _ctl();
    if (ctl == null) return;

    // Se o style foi trocado, invalida o handle antigo
    if (_meCircle == null) {
      _meCircle = await ctl.addCircle(_meOptions(at));
      return;
    }

    try {
      await ctl.updateCircle(_meCircle!, CircleOptions(geometry: at));
    } catch (_) {
      // Se falhar (p.ex. handle antigo inválido após troca de style), recria
      try {
        _meCircle = await ctl.addCircle(_meOptions(at));
      } catch (_) {}
    }
  }

  Future<void> _removeMeCircle() async {
    final ctl = await _ctl();
    if (ctl != null && _meCircle != null) {
      try {
        await ctl.removeCircle(_meCircle!);
      } catch (_) {}
    }
    _meCircle = null;
  }

  // ========= Localização =========
  Future<void> _toggleLocation() async {
    if (_locEnabled) {
      // DESATIVAR: para o stream e remove a bolinha do mapa
      await _locationService.stop();
      await _removeMeCircle(); // <- remove a anotação
      setState(() {
        _locEnabled = false;
        // Mantemos _lastLatLng para permitir "Centralizar em mim" depois se quiser
      });
      return;
    }

    // ATIVAR
    final ok = await _locationService.ensureServiceAndPermission();
    if (!ok) return;

    _locationService.startPositionStream(
      onData: (pos) async {
        _lastLatLng = LatLng(pos.latitude, pos.longitude);
        await _updateMeCircle(_lastLatLng!);
      },
      onError: (e, st) {},
    );

    final current = await _locationService.getCurrent();
    if (current != null) {
      _lastLatLng = LatLng(current.latitude, current.longitude);
      await _updateMeCircle(_lastLatLng!);
      final ctl = await _ctl();
      if (ctl != null) {
        await ctl.animateCamera(
          CameraUpdate.newLatLngZoom(
            _lastLatLng!,
            max(14, _camera?.zoom ?? 14),
          ),
        );
      }
    }
    setState(() => _locEnabled = true);
  }

  Future<void> _centerOnMe() async {
    LatLng? target = _lastLatLng;

    if (target == null) {
      // Tenta pegar a posição atual (one-shot) sem iniciar o stream
      final ok = await _locationService.ensureServiceAndPermission();
      if (ok) {
        final current = await _locationService.getCurrent();
        if (current != null) {
          target = LatLng(current.latitude, current.longitude);
          _lastLatLng = target;
          // Só desenha a bolinha se o tracking estiver ligado
          if (_locEnabled) {
            await _updateMeCircle(target);
          }
        }
      }
    }

    final ctl = await _ctl();
    if (ctl != null && target != null) {
      await ctl.animateCamera(
        CameraUpdate.newLatLngZoom(target, max(14, _camera?.zoom ?? 14)),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sem posição ainda. Ative a localização para obter sua posição.',
            ),
          ),
        );
      }
    }
  }

  // ========= UI: estilo =========
  Future<void> _pickStyle() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: MapStyleService.styles.map((s) {
              final selected = s.id == _styleId;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(s.label),
                subtitle: Text(s.id),
                onTap: () => Navigator.pop(ctx, s.id),
              );
            }).toList(),
          ),
        );
      },
    );

    if (choice != null && choice != _styleId) {
      // Ao trocar de style, zere as anotações (serão recriadas no onStyleLoaded)
      setState(() {
        _styleLoaded = false;
        _meCircle = null; // <- importante
        _styleId = choice;

        // NOVO: invalida também os overlays de trilha (handles ficam inválidos ao trocar style)
        _currentLine = null;
        _currentSymbols.clear();
      });
    }
  }

  // ========= UI: descobrir =========
  void _openDiscover() async {
    // 1) Tenta usar a última posição conhecida (bolinha azul)
    LatLng? here = _lastLatLng;

    // 2) Se ainda não tiver, tenta um one-shot do GPS sem ligar o stream
    if (here == null) {
      final ok = await _locationService.ensureServiceAndPermission();
      if (ok) {
        final current = await _locationService.getCurrent();
        if (current != null) {
          here = LatLng(current.latitude, current.longitude);
          _lastLatLng = here; // guarda como última posição
        }
      }
    }

    // 3) Fallback final (só para não quebrar): centro atual da câmera ou inicial
    here ??= _camera?.target ?? _initial.target;

    // (opcional) elevação mock por enquanto
    final double elevation = 600;

    // Nearby dummy (até você trocar para a lista real)
    final nearby = <TrailItem>[
      const TrailItem(
        name: 'Trilha do Mirante',
        distanceKm: 4.2,
        difficulty: 1,
      ),
      const TrailItem(name: 'Cavas Trail', distanceKm: 8.6, difficulty: 2),
      const TrailItem(name: 'Serra Alta', distanceKm: 12.3, difficulty: 3),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        // NADA de DefaultTabController — o Discover já tem o próprio controller
        return DiscoverSheet(
          coordinate: here!, // <- agora é a sua posição (fixa)
          elevationMeters: elevation,
          nearby: nearby,
        );
      },
    );
  }

  // ========= NOVO: Desenho de trilha selecionada =========
  Future<void> _clearCurrentTrail() async {
    final ctl = await _ctl();
    if (ctl == null) {
      _currentLine = null;
      _currentSymbols.clear();
      return;
    }

    if (_currentLine != null) {
      try {
        await ctl.removeLine(_currentLine!);
      } catch (_) {}
      _currentLine = null;
    }
    if (_currentSymbols.isNotEmpty) {
      for (final s in _currentSymbols) {
        try {
          await ctl.removeSymbol(s);
        } catch (_) {}
      }
      _currentSymbols.clear();
    }
  }

  Future<void> _drawTrail({
    required List<LatLng> line,
    required List<LatLng> waypoints,
  }) async {
    final ctl = await _ctl();
    if (ctl == null) return;

    // Posiciona câmera no início da trilha
    if (line.isNotEmpty) {
      await ctl.animateCamera(CameraUpdate.newLatLngZoom(line.first, 13));
    }

    // Linha principal
    _currentLine = await ctl.addLine(
      LineOptions(geometry: line, lineWidth: 4.0, lineOpacity: 0.9),
    );

    // Waypoints simples
    for (final p in waypoints) {
      final sym = await ctl.addSymbol(
        SymbolOptions(geometry: p, iconImage: 'marker-15', iconSize: 1.1),
      );
      _currentSymbols.add(sym);
    }
  }

  Future<void> _onSelectedTrailChanged() async {
    final id = selectedTrailId.value;
    if (id == null) return;

    // Carrega data do asset e desenha
    final data = await AssetTrailsRepo.instance.loadById(id);

    await _clearCurrentTrail();
    await _drawTrail(line: data.line, waypoints: data.waypoints);
  }

  Future<void> _redrawSelectedTrailIfAny() async {
    final id = selectedTrailId.value;
    if (id == null) return;
    final ctl = await _ctl();
    if (ctl == null) return;

    final data = await AssetTrailsRepo.instance.loadById(id);
    await _clearCurrentTrail();
    await _drawTrail(line: data.line, waypoints: data.waypoints);
  }

  // ========= UI: zoom / bússola =========
  Future<void> _zoom(int delta) async {
    final ctl = await _ctl();
    if (ctl == null) return;
    await ctl.animateCamera(
      delta > 0 ? CameraUpdate.zoomIn() : CameraUpdate.zoomOut(),
    );
  }

  Future<void> _resetNorth() async {
    final ctl = await _ctl();
    if (ctl == null) return;
    final cam = _camera ?? _initial;
    await ctl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: cam.target,
          zoom: cam.zoom,
          tilt: cam.tilt,
          bearing: 0.0,
        ),
      ),
    );
    setState(() => _bearing = 0.0);
  }

  // ========= BUILD =========
  @override
  Widget build(BuildContext context) {
    assert(
      _apiKey.isNotEmpty,
      'MAPTILER_KEY não definida. Rode com --dart-define=MAPTILER_KEY=pk_xxx',
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppSideDrawer(
        onSelect: (route) {
          if (route == '/descobrir') _openDiscover();
        },
      ),
      body: Stack(
        children: [
          // MAPA
          MapLibreMap(
            styleString: _styleString,
            initialCameraPosition: _initial,
            onMapCreated: (c) => _controllerCompleter.complete(c),
            onStyleLoadedCallback: () async {
              // Style novo carregou: invalida handles e só recria bolinha se tracking estiver ligado
              _styleLoaded = true;

              // Invalida handles antigos
              _meCircle = null;
              _currentLine = null;
              _currentSymbols.clear();

              // Recria minha posição (se tracking on)
              if (_locEnabled && _lastLatLng != null) {
                await _updateMeCircle(_lastLatLng!);
              }

              // NOVO: re-desenha a trilha atualmente selecionada (se houver)
              await _redrawSelectedTrailIfAny();

              setState(() {});
            },
            compassEnabled: false, // usaremos nossa bússola
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: false,
            attributionButtonMargins: const Point(12, 12),
            logoViewMargins: const Point(12, 48),
            onCameraMove: (pos) {
              _camera = pos;
              _bearing = pos.bearing;
              setState(() {});
            },
          ),

          // TOPO: menu + "search"
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 12,
            child: Row(
              children: [
                _RoundButton(
                  icon: Icons.menu,
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    child: const Row(
                      children: [
                        Icon(Icons.search, size: 20, color: Colors.black54),
                        SizedBox(width: 8),
                        Text('Search', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // DIREITA: tools
          Positioned(
            right: 12,
            top: MediaQuery.of(context).padding.top + 90,
            child: Column(
              children: [
                _CompassButton(bearingDegrees: _bearing, onTap: _resetNorth),
                const SizedBox(height: 10),
                _ToolButton(icon: Icons.zoom_in, onTap: () => _zoom(1)),
                const SizedBox(height: 10),
                _ToolButton(icon: Icons.zoom_out, onTap: () => _zoom(-1)),
                const SizedBox(height: 10),
                _ToolButton(
                  icon: Icons.layers,
                  onTap: _pickStyle,
                  tooltip: 'Estilos',
                ),
                const SizedBox(height: 10),
                _ToolButton(
                  icon: _locEnabled ? Icons.gps_off : Icons.gps_fixed,
                  onTap: _toggleLocation,
                  tooltip: _locEnabled
                      ? 'Parar localização'
                      : 'Ativar localização',
                ),
                const SizedBox(height: 10),
                _ToolButton(
                  icon: Icons.location_on,
                  onTap: _centerOnMe,
                  tooltip: 'Centralizar em mim',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ====== Widgets simples locais ======
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.black87),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  const _ToolButton({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, size: 22, color: Colors.black87);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class _CompassButton extends StatelessWidget {
  final double bearingDegrees;
  final VoidCallback onTap;
  const _CompassButton({required this.bearingDegrees, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final angleRad = -bearingDegrees * pi / 180.0;

    return Tooltip(
      message: 'Alinhar ao norte',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angleRad,
            child: const Icon(
              Icons.navigation,
              size: 22,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
