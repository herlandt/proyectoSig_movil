// Tareas del trabajador: paradas pendientes en el orden de la ruta y control del recorrido (envío de ubicación).
import 'package:flutter/material.dart';

import '../api.dart';
import '../gps.dart';
import '../modelos.dart';
import '../tema.dart';
import 'comun.dart';
import 'detalle.dart';
import 'mapa_ruta.dart';

class PantallaTareas extends StatefulWidget {
  const PantallaTareas({super.key});

  @override
  State<PantallaTareas> createState() => _PantallaTareasState();
}

class _PantallaTareasState extends State<PantallaTareas> {
  final _seguimiento = Seguimiento.instancia;
  Perfil? _perfil;
  List<Tarea> _tareas = const [];
  bool _cargando = true;
  bool _cambiandoRecorrido = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  ConfiguracionMovil get _configuracion => _perfil?.configuracion ?? const ConfiguracionMovil();

  /// Un trabajador con ambos roles puede tener una ruta de corte y otra de reconexión.
  Map<int, List<Tarea>> get _porAsignacion {
    final grupos = <int, List<Tarea>>{};
    for (final t in _tareas) {
      (grupos[t.idAsignacion] ??= []).add(t);
    }
    return grupos;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // El perfil se relee siempre: trae la configuración vigente (intervalo GPS, fotos, radio).
      final perfil = await ApiCliente.instancia.perfil();
      final tareas = await ApiCliente.instancia.tareas();
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _tareas = tareas;
      });
      if (tareas.isEmpty && _seguimiento.activo) {
        await _seguimiento.detener();
        _mensaje('Ruta terminada: se detuvo el envío de ubicación.');
      }
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

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _alternarRecorrido() async {
    setState(() => _cambiandoRecorrido = true);
    try {
      if (_seguimiento.activo) {
        await _seguimiento.detener();
        _mensaje('Recorrido detenido: ya no se envía su ubicación.');
        return;
      }
      final grupos = _porAsignacion;
      if (grupos.isEmpty) return;
      final id = grupos.length == 1 ? grupos.keys.first : await _elegirAsignacion(grupos);
      if (id == null) return;
      await ApiCliente.instancia.iniciarRecorrido(id);
      await pedirPermisoNotificaciones();
      await _seguimiento.iniciar(idAsignacion: id, intervaloSegundos: _configuracion.intervaloGpsSegundos);
      _mensaje('Recorrido iniciado: su ubicación se envía cada ${_configuracion.intervaloGpsSegundos} s.');
    } on ErrorGps catch (e) {
      _mensaje(e.mensaje);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        await irAlAcceso(context, aviso: avisoSesionVencida);
        return;
      }
      _mensaje(e.mensaje);
    } finally {
      if (mounted) setState(() => _cambiandoRecorrido = false);
    }
  }

  Future<int?> _elegirAsignacion(Map<int, List<Tarea>> grupos) => showDialog<int>(
        context: context,
        builder: (contexto) => SimpleDialog(
          title: const Text('¿Qué ruta va a recorrer?'),
          children: [
            for (final MapEntry(key: id, value: tareas) in grupos.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(contexto, id),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Text('Ruta de ${tareas.first.nombreTipo.toLowerCase()} · ${tareas.length} pendiente(s)'),
              ),
          ],
        ),
      );

  Future<void> _abrir(Tarea tarea) async {
    final r = await Navigator.of(context).push<ResultadoRegistro>(
        MaterialPageRoute(builder: (_) => PantallaDetalle(tarea: tarea, configuracion: _configuracion)));
    if (r == null || !mounted) return;
    _mensaje(resumenRegistro(r));
    await _cargar();
  }

  Future<void> _abrirMapa(int idAsignacion) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PantallaMapaRuta(
            idAsignacion: idAsignacion,
            tareas: _porAsignacion[idAsignacion] ?? const [],
            configuracion: _configuracion)));
    if (mounted) await _cargar();
  }

  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: Text(_seguimiento.activo
            ? 'Se detendrá el recorrido y se dejará de enviar su ubicación.'
            : '¿Desea cerrar la sesión en este celular?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (salir == true && mounted) await irAlAcceso(context);
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _porAsignacion;
    final perfil = _perfil;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis tareas'),
            if (perfil != null)
              Text('${perfil.nombre} · ${perfil.rolVisible}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _cargando ? null : _cargar),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (opcion) {
              if (opcion == 'salir') _confirmarSalida();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'salir',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _TarjetaRecorrido(
              intervaloSegundos: _configuracion.intervaloGpsSegundos,
              hayTareas: _tareas.isNotEmpty,
              ocupado: _cambiandoRecorrido,
              alAlternar: _alternarRecorrido,
            ),
            if (_error != null) ...[const SizedBox(height: 12), Aviso(_error!)],
            if (_cargando && _tareas.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (!_cargando && _error == null && _tareas.isEmpty) const _SinTareas(),
            for (final MapEntry(key: id, value: tareas) in grupos.entries) ...[
              const SizedBox(height: 16),
              _CabeceraRuta(tareas: tareas, alVerMapa: () => _abrirMapa(id)),
              for (final (i, t) in tareas.indexed) _ItemTarea(tarea: t, siguiente: i == 0, alTocar: () => _abrir(t)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TarjetaRecorrido extends StatelessWidget {
  const _TarjetaRecorrido(
      {required this.intervaloSegundos, required this.hayTareas, required this.ocupado, required this.alAlternar});

  final int intervaloSegundos;
  final bool hayTareas;
  final bool ocupado;
  final VoidCallback alAlternar;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Seguimiento.instancia,
        builder: (context, _) {
          final s = Seguimiento.instancia;
          final tema = Theme.of(context);
          final String detalle;
          if (!s.activo) {
            detalle = hayTareas
                ? 'Al salir a campo, inicie el recorrido: su ubicación se enviará al supervisor cada $intervaloSegundos s.'
                : 'Sin paradas pendientes no hace falta iniciar el recorrido.';
          } else if (s.ultimoError != null) {
            detalle = '${s.ultimoError} ${s.enCola} posición(es) en espera de envío.';
          } else if (s.ultimoEnvio != null) {
            detalle = 'Último envío a las ${formatoHora(s.ultimoEnvio!)} · ${s.enviadas} posición(es) enviadas.';
          } else {
            detalle = 'Esperando la primera posición del GPS…';
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(s.activo ? Icons.gps_fixed : Icons.gps_off, color: s.activo ? colorExito : colorNeutro),
                    const SizedBox(width: 8),
                    Text(s.activo ? 'Recorrido en curso' : 'Recorrido detenido',
                        style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Semantics(
                    liveRegion: true,
                    child: Text(detalle, style: TextStyle(color: s.activo && s.ultimoError != null ? colorAviso : null)),
                  ),
                  const SizedBox(height: 12),
                  if (s.activo)
                    OutlinedButton.icon(
                      onPressed: ocupado ? null : alAlternar,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Detener recorrido'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: ocupado || !hayTareas ? null : alAlternar,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar recorrido'),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _CabeceraRuta extends StatelessWidget {
  const _CabeceraRuta({required this.tareas, required this.alVerMapa});

  final List<Tarea> tareas;
  final VoidCallback alVerMapa;

  @override
  Widget build(BuildContext context) {
    final tipo = tareas.first.nombreTipo.toLowerCase();
    return Row(
      children: [
        Expanded(
          child: Text('Ruta de $tipo · ${tareas.length} pendiente(s)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        TextButton.icon(onPressed: alVerMapa, icon: const Icon(Icons.map_outlined), label: const Text('Ver mapa')),
      ],
    );
  }
}

class _ItemTarea extends StatelessWidget {
  const _ItemTarea({required this.tarea, required this.siguiente, required this.alTocar});

  final Tarea tarea;
  final bool siguiente;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final nombre = tarea.nombre?.trim();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      // La siguiente parada lleva borde y texto («Siguiente parada»): no depende solo del color.
      shape: siguiente
          ? RoundedRectangleBorder(
              side: const BorderSide(color: colorResalte, width: 3), borderRadius: BorderRadius.circular(12))
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colorPrimario,
          foregroundColor: Colors.white,
          child: Text('${tarea.orden}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        title: Text('Código ${tarea.codigoVisible}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (siguiente) 'Siguiente parada',
          (nombre == null || nombre.isEmpty) ? 'Sin nombre registrado' : nombre,
          'Tramo ${formatoDistancia(tarea.distanciaTramoMetros)}',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: alTocar,
      ),
    );
  }
}

class _SinTareas extends StatelessWidget {
  const _SinTareas();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.task_alt, size: 56, color: colorExito),
          const SizedBox(height: 12),
          Text('No tiene paradas pendientes', style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Cuando el administrador le asigne una ruta desde el visor web, aparecerá aquí. '
            'Deslice hacia abajo para actualizar.',
            style: tema.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
