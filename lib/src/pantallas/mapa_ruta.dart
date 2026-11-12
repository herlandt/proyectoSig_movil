// Mapa de la ruta asignada: partida, paradas numeradas en orden, tramos por las calles y la ubicación actual.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../gps.dart';
import '../mapa.dart';
import '../modelos.dart';
import '../tema.dart';
import 'comun.dart';
import 'detalle.dart';

class PantallaMapaRuta extends StatefulWidget {
  const PantallaMapaRuta({super.key, required this.idAsignacion, required this.tareas, required this.configuracion});

  final int idAsignacion;

  /// Paradas pendientes de esta ruta, para registrarlas desde el mapa.
  final List<Tarea> tareas;
  final ConfiguracionMovil configuracion;

  @override
  State<PantallaMapaRuta> createState() => _PantallaMapaRutaState();
}

class _PantallaMapaRutaState extends State<PantallaMapaRuta> {
  static const _distancia = Distance();

  final _mapa = MapController();
  late final List<Tarea> _tareas = List.of(widget.tareas);
  RutaAsignacion? _ruta;
  int? _seleccion; // idDetalle
  LatLng? _yo;
  double _precision = 0;
  bool _mapaListo = false;
  bool _cargando = true;
  bool _ubicando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    _ubicar(centrar: false);
  }

  @override
  void dispose() {
    _mapa.dispose();
    super.dispose();
  }

  /// Las paradas anuladas (por un nuevo cálculo de la ruta) no se dibujan.
  List<ParadaRuta> get _paradas => [for (final p in _ruta?.paradas ?? const <ParadaRuta>[]) if (p.estado != 'Anulada') p];

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final ruta = await ApiCliente.instancia.ruta(widget.idAsignacion);
      if (!mounted) return;
      setState(() {
        _ruta = ruta;
        _seleccion ??= ruta.paradas.where((p) => p.pendiente).firstOrNull?.idDetalle;
      });
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        await irAlAcceso(context, aviso: avisoSesionVencida);
        return;
      }
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _ubicar({bool centrar = true}) async {
    setState(() => _ubicando = true);
    try {
      final p = await ubicacionActual();
      if (!mounted) return;
      setState(() {
        _yo = LatLng(p.latitude, p.longitude);
        _precision = p.accuracy;
      });
      if (centrar && _mapaListo) _mapa.move(_yo!, 17);
    } on ErrorGps catch (e) {
      if (centrar && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  Future<void> _registrar(Tarea tarea) async {
    final r = await Navigator.of(context).push<ResultadoRegistro>(
        MaterialPageRoute(builder: (_) => PantallaDetalle(tarea: tarea, configuracion: widget.configuracion)));
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resumenRegistro(r))));
    setState(() {
      _tareas.removeWhere((t) => t.idDetalle == tarea.idDetalle);
      _seleccion = null;
    });
    await _cargar();
  }

  Color _color(ParadaRuta p) => switch (p.estado) {
        'Ejecutada' => colorExito,
        'Observada' => colorAviso,
        'Pendiente' => colorPrimario,
        _ => colorNeutro,
      };

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final titulo = ruta == null ? 'Ruta' : 'Ruta de ${ruta.tipo == 'Corte' ? 'corte' : 'reconexión'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ruta == null
          ? Center(
              child: _cargando
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Aviso(_error ?? 'No se pudo cargar la ruta.')),
            )
          : Column(
              children: [
                if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Aviso(_error!)),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapa,
                        options: MapOptions(
                          initialCameraFit: CameraFit.coordinates(
                            coordinates: [ruta.partida, for (final p in _paradas) p.punto],
                            padding: const EdgeInsets.all(48),
                            maxZoom: 18,
                          ),
                          onMapReady: () => _mapaListo = true,
                          onTap: (_, _) => setState(() => _seleccion = null),
                        ),
                        children: [
                          capaOsm(),
                          PolylineLayer(polylines: _tramos()),
                          if (_yo != null) ...capasPosicion(_yo!, _precision),
                          MarkerLayer(markers: _marcadores(ruta)),
                          atribucionOsm(),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: 'Mi ubicación',
                          onPressed: _ubicando ? null : _ubicar,
                          child: _ubicando
                              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(top: false, child: _panelInferior(ruta)),
              ],
            ),
    );
  }

  /// Tramo de cada parada (desde la anterior, por las calles): pendientes en azul, realizados en gris.
  List<Polyline> _tramos() => [
        for (final p in _paradas)
          if (p.tramo.length > 1)
            Polyline(
              points: p.tramo,
              strokeWidth: p.pendiente ? 5 : 4,
              color: p.pendiente ? colorPrimario : colorNeutro.withValues(alpha: 0.7),
              borderStrokeWidth: p.pendiente ? 1.5 : 0,
              borderColor: Colors.white,
            ),
      ];

  List<Marker> _marcadores(RutaAsignacion ruta) {
    // Las pendientes encima de las realizadas, y la seleccionada encima de todas.
    final orden = [..._paradas]..sort((a, b) {
        int peso(ParadaRuta p) => p.idDetalle == _seleccion ? 2 : (p.pendiente ? 1 : 0);
        return peso(a).compareTo(peso(b));
      });
    return [
      marcadorPartida(ruta.partida),
      for (final p in orden)
        marcadorParada(p.punto, p.orden,
            color: _color(p),
            resaltada: p.idDetalle == _seleccion,
            alTocar: () => setState(() => _seleccion = p.idDetalle)),
    ];
  }

  Widget _panelInferior(RutaAsignacion ruta) {
    final tema = Theme.of(context);
    final parada = _paradas.where((p) => p.idDetalle == _seleccion).firstOrNull;
    if (parada == null) {
      final pendientes = _paradas.where((p) => p.pendiente).length;
      return ListTile(
        leading: const Icon(Icons.route_outlined),
        title: Text('$pendientes pendiente(s) de ${_paradas.length} · ${formatoDistancia(ruta.distanciaMetros)} de recorrido'),
        subtitle: const Text('Toque una parada del mapa para ver su detalle.'),
      );
    }
    final tarea = _tareas.where((t) => t.idDetalle == parada.idDetalle).firstOrNull;
    final nombre = parada.nombre?.trim();
    final yo = _yo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _color(parada),
            foregroundColor: Colors.white,
            child: Text('${parada.orden}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Código ${parada.codigoVisible}', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    (nombre == null || nombre.isEmpty) ? 'Sin nombre registrado' : nombre,
                    nombreEstadoParada(parada.estado),
                    if (yo != null) 'a ${formatoDistancia(_distancia.as(LengthUnit.Meter, yo, parada.punto))}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (tarea != null && parada.pendiente) ...[
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _registrar(tarea), child: const Text('Registrar')),
          ],
        ],
      ),
    );
  }
}
