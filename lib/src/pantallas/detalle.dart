// Registro de una parada: destino, navegación, ubicación GPS obligatoria, datos del medidor y fotos de evidencia.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../gps.dart';
import '../mapa.dart';
import '../modelos.dart';
import '../tema.dart';
import 'comun.dart';

/// Modo de viaje para Google Maps: en la app (google.navigation) y en la versión web (travelmode).
enum ModoViaje {
  moto('Moto', Icons.two_wheeler, 'l', 'two-wheeler'),
  aPie('A pie', Icons.directions_walk, 'w', 'walking'),
  vehiculo('Vehículo', Icons.directions_car, 'd', 'driving');

  const ModoViaje(this.nombre, this.icono, this.modoApp, this.modoWeb);
  final String nombre;
  final IconData icono;
  final String modoApp;
  final String modoWeb;
}

class PantallaDetalle extends StatefulWidget {
  const PantallaDetalle({super.key, required this.tarea, required this.configuracion});

  final Tarea tarea;
  final ConfiguracionMovil configuracion;

  @override
  State<PantallaDetalle> createState() => _PantallaDetalleState();
}

class _PantallaDetalleState extends State<PantallaDetalle> {
  final _formulario = GlobalKey<FormState>();
  final _medidor = TextEditingController();
  final _lectura = TextEditingController();
  final _observacion = TextEditingController();
  final _mapa = MapController();
  final List<File> _fotos = [];
  late String _resultado = widget.tarea.resultadoRealizado;
  ModoViaje _modo = ModoViaje.moto;
  Position? _posicion;
  bool _mapaListo = false;
  bool _ubicando = false;
  bool _guardando = false;
  String? _errorGps;
  String? _error;

  Tarea get _t => widget.tarea;
  int get _radio => widget.configuracion.radioValidacionMetros;
  int get _maximoFotos => widget.configuracion.maximoFotos;
  bool get _realizado => _resultado == _t.resultadoRealizado;
  double? get _distancia => _posicion == null
      ? null
      : Geolocator.distanceBetween(_posicion!.latitude, _posicion!.longitude, _t.lat, _t.lon);
  bool get _hayCambios =>
      _fotos.isNotEmpty || _lectura.text.isNotEmpty || _medidor.text.isNotEmpty || _observacion.text.isNotEmpty;

  List<String> get _motivos => [
        'Casa cerrada',
        'Medidor no encontrado',
        'No permitieron el ingreso',
        'Dirección no encontrada',
        if (_t.esCorte) 'Presentó comprobante de pago' else 'Ya tenía servicio',
      ];

  @override
  void initState() {
    super.initState();
    _ubicar();
  }

  @override
  void dispose() {
    _medidor.dispose();
    _lectura.dispose();
    _observacion.dispose();
    _mapa.dispose();
    super.dispose();
  }

  Future<void> _ubicar() async {
    setState(() {
      _ubicando = true;
      _errorGps = null;
    });
    try {
      final p = await ubicacionActual();
      if (!mounted) return;
      setState(() => _posicion = p);
      _encuadrar();
    } on ErrorGps catch (e) {
      if (mounted) setState(() => _errorGps = e.mensaje);
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  void _encuadrar() {
    if (!_mapaListo) return;
    final puntos = [_t.ubicacion, if (_posicion != null) LatLng(_posicion!.latitude, _posicion!.longitude)];
    _mapa.fitCamera(CameraFit.coordinates(coordinates: puntos, padding: const EdgeInsets.all(48), maxZoom: 18));
  }

  Future<void> _navegar() async {
    final destino = '${_t.lat},${_t.lon}';
    final app = Uri.parse('google.navigation:q=$destino&mode=${_modo.modoApp}');
    final web = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': destino, 'travelmode': _modo.modoWeb});
    try {
      if (await launchUrl(app, mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // Sin la app de Google Maps: se abre la versión web.
    }
    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // Se informa abajo.
    }
    if (mounted) setState(() => _error = 'No se encontró una aplicación de mapas para navegar hasta el código.');
  }

  Future<void> _tomarFoto() async {
    try {
      final foto = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
      if (foto != null && mounted) setState(() => _fotos.add(File(foto.path)));
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara: ${e.message ?? e.code}');
    }
  }

  void _agregarMotivo(String motivo) {
    final actual = _observacion.text.trim();
    _observacion.text = actual.isEmpty ? motivo : '$actual. $motivo';
    _observacion.selection = TextSelection.collapsed(offset: _observacion.text.length);
    setState(() {});
  }

  String? _validarLectura(String? texto) {
    final t = (texto ?? '').trim();
    if (t.isEmpty) return _realizado ? 'Registre la lectura actual del medidor.' : null;
    return normalizarLectura(t) == null ? 'Escriba solo la cifra, con hasta 2 decimales (ejemplo: 1234,5).' : null;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formulario.currentState!.validate()) return;
    if (_realizado && _fotos.isEmpty) {
      setState(() => _error = 'Tome al menos una fotografía del medidor.');
      return;
    }
    setState(() => _guardando = true);
    try {
      // Lectura nueva del GPS en el momento de guardar: es la que el servidor compara con el código fijo.
      final p = await ubicacionActual();
      if (!mounted) return;
      setState(() => _posicion = p);
      _encuadrar();
      final distancia = _distancia!;
      if (distancia > _radio && await _confirmarFueraDelRadio(distancia) != true) return;
      final lectura = _lectura.text.trim();
      final r = await ApiCliente.instancia.registrar(
        idDetalle: _t.idDetalle,
        resultado: _resultado,
        numeroMedidor: _medidor.text.trim(),
        lectura: lectura.isEmpty ? null : normalizarLectura(lectura),
        observacion: _observacion.text.trim(),
        lat: p.latitude,
        lon: p.longitude,
        precision: p.accuracy,
        fotos: _fotos,
      );
      if (mounted) Navigator.of(context).pop(r);
    } on ErrorGps catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        await irAlAcceso(context, aviso: avisoSesionVencida);
        return;
      }
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool?> _confirmarFueraDelRadio(double distancia) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.wrong_location_outlined, color: colorAviso),
          title: const Text('Está lejos del código'),
          content: Text('Su ubicación está a ${formatoDistancia(distancia)} del código fijo (radio permitido: $_radio m). '
              'Puede guardar, pero el registro quedará marcado como «fuera del radio» para el supervisor.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar igual')),
          ],
        ),
      );

  Future<void> _alSalir(bool salio, ResultadoRegistro? _) async {
    if (salio || _guardando) return;
    final descartar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Descartar el registro?'),
        content: const Text('Se perderán los datos y las fotos que todavía no guardó.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (descartar == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nombre = _t.nombre?.trim();
    return PopScope<ResultadoRegistro>(
      canPop: !_guardando && !_hayCambios,
      onPopInvokedWithResult: _alSalir,
      child: Scaffold(
        appBar: AppBar(title: Text('Parada ${_t.orden} · ${_t.nombreTipo}')),
        body: Form(
          key: _formulario,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text('Código fijo ${_t.codigoVisible}',
                  style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text((nombre == null || nombre.isEmpty) ? 'Sin nombre registrado' : nombre, style: tema.textTheme.titleMedium),
              const SizedBox(height: 12),
              // Sin ClipRRect ni fundido, como el mapa de la ruta: con ambos, el emulador (Impeller sobre OpenGLES)
              // dejaba este minimapa sin teselas.
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(border: Border.all(color: tema.colorScheme.outlineVariant)),
                child: SizedBox(height: 200, child: _miniMapa()),
              ),
              const SizedBox(height: 8),
              _estadoUbicacion(),
              const SizedBox(height: 12),
              SegmentedButton<ModoViaje>(
                segments: [
                  for (final m in ModoViaje.values) ButtonSegment(value: m, label: Text(m.nombre), icon: Icon(m.icono)),
                ],
                selected: {_modo},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _modo = s.first),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _navegar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Cómo llegar (Google Maps)'),
              ),
              const Divider(height: 36),
              Text('Resultado', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: _t.resultadoRealizado,
                      label: Text(_t.resultadoRealizado),
                      icon: Icon(_t.esCorte ? Icons.content_cut : Icons.power_outlined)),
                  const ButtonSegment(value: 'Observado', label: Text('Observado'), icon: Icon(Icons.report_outlined)),
                ],
                selected: {_resultado},
                onSelectionChanged: (s) => setState(() => _resultado = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _realizado
                    ? 'Registre la lectura y tome al menos una foto del medidor.'
                    : 'Elija «Observado» si no se pudo realizar e indique el motivo.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _medidor,
                decoration: const InputDecoration(labelText: 'Número de medidor (opcional)', prefixIcon: Icon(Icons.speed)),
                maxLength: 30,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _lectura,
                decoration: InputDecoration(
                  labelText: _realizado ? 'Lectura del medidor (m³)' : 'Lectura del medidor (opcional)',
                  prefixIcon: const Icon(Icons.pin_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                validator: _validarLectura,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _observacion,
                decoration: InputDecoration(
                  labelText: _realizado ? 'Observación (opcional)' : 'Motivo (obligatorio)',
                  alignLabelWithHint: true,
                ),
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                validator: (v) => !_realizado && (v ?? '').trim().isEmpty
                    ? 'Describa por qué no se pudo realizar (por ejemplo, «casa cerrada»).'
                    : null,
              ),
              if (!_realizado)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [for (final m in _motivos) ActionChip(label: Text(m), onPressed: () => _agregarMotivo(m))],
                ),
              const Divider(height: 36),
              Row(children: [
                Expanded(
                    child: Text('Fotos de evidencia', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                Text('${_fotos.length} de $_maximoFotos'),
              ]),
              Text(
                _realizado
                    ? 'Obligatoria al menos una: el medidor con la lectura visible.'
                    : 'Opcional: por ejemplo, la fachada de la casa cerrada.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (i, f) in _fotos.indexed)
                    _Miniatura(archivo: f, numero: i + 1, alQuitar: () => setState(() => _fotos.removeAt(i))),
                  if (_fotos.length < _maximoFotos) _BotonFoto(alTocar: _tomarFoto),
                ],
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[Aviso(_error!), const SizedBox(height: 12)],
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: _guardando
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_guardando ? 'Guardando…' : 'Guardar registro'),
              ),
              const SizedBox(height: 6),
              Text('Al guardar se toma su ubicación GPS actual; sin ella no se registra el trabajo.',
                  style: tema.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMapa() {
    final destino = _t.ubicacion;
    final p = _posicion;
    return FlutterMap(
      mapController: _mapa,
      options: MapOptions(
        initialCenter: destino,
        initialZoom: 17,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        onMapReady: () {
          _mapaListo = true;
          _encuadrar();
        },
      ),
      children: [
        capaOsm(fundido: false),
        // Zona válida para registrar: el radio que configuró el administrador alrededor del código fijo.
        CircleLayer(circles: [
          CircleMarker(
            point: destino,
            radius: _radio.toDouble(),
            useRadiusInMeter: true,
            color: colorExito.withValues(alpha: 0.12),
            borderColor: colorExito,
            borderStrokeWidth: 1.5,
          ),
        ]),
        if (p != null) ...capasPosicion(LatLng(p.latitude, p.longitude), p.accuracy),
        MarkerLayer(markers: [marcadorDestino(destino)]),
        atribucionOsm(),
      ],
    );
  }

  Widget _estadoUbicacion() {
    final p = _posicion;
    final distancia = _distancia;
    final boton = IconButton(
      tooltip: 'Actualizar ubicación',
      onPressed: _ubicando ? null : _ubicar,
      icon: _ubicando
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.my_location),
    );
    if (p == null || distancia == null) {
      return Row(children: [
        Expanded(
          child: _errorGps != null
              ? Aviso(_errorGps!, tipo: TipoAviso.advertencia)
              : const Text('Obteniendo su ubicación…'),
        ),
        boton,
      ]);
    }
    final dentro = distancia <= _radio;
    final color = dentro ? colorExito : colorAviso;
    final texto = dentro
        ? 'Está en el lugar: a ${formatoDistancia(distancia)} del código (GPS ±${p.accuracy.round()} m).'
        : 'Está a ${formatoDistancia(distancia)} del código; el radio permitido es $_radio m (GPS ±${p.accuracy.round()} m).';
    return Row(children: [
      Icon(dentro ? Icons.where_to_vote_outlined : Icons.wrong_location_outlined, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ),
      ),
      boton,
    ]);
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.archivo, required this.numero, required this.alQuitar});

  final File archivo;
  final int numero;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 104,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(archivo, fit: BoxFit.cover, cacheWidth: 312, semanticLabel: 'Foto $numero'),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filled(
                tooltip: 'Quitar foto $numero',
                onPressed: alQuitar,
                iconSize: 18,
                style: IconButton.styleFrom(backgroundColor: colorPeligro, foregroundColor: Colors.white),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
}

class _BotonFoto extends StatelessWidget {
  const _BotonFoto({required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: 104,
      child: OutlinedButton(
        onPressed: alTocar,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: color, width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.photo_camera_outlined, size: 30), SizedBox(height: 4), Text('Tomar foto')],
        ),
      ),
    );
  }
}
