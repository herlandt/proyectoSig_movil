// Modelos de la API móvil de VisorDatosSIG (BackendSIG · /api/movil).
import 'package:latlong2/latlong.dart';

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
int? _entero(dynamic v) => (v as num?)?.toInt();

/// [lon, lat] (formato de la API) → LatLng.
LatLng puntoDesde(dynamic p) => LatLng(_num((p as List)[1]), _num(p[0]));

/// Parámetros que define el administrador en «Configuración operativa».
class ConfiguracionMovil {
  final int intervaloGpsSegundos;
  final int maximoFotos;
  final int radioValidacionMetros;

  const ConfiguracionMovil({this.intervaloGpsSegundos = 30, this.maximoFotos = 3, this.radioValidacionMetros = 60});

  factory ConfiguracionMovil.desdeJson(Map<String, dynamic> j) => ConfiguracionMovil(
        intervaloGpsSegundos: _entero(j['intervaloGpsSegundos']) ?? 30,
        maximoFotos: _entero(j['maximoFotos']) ?? 3,
        radioValidacionMetros: _entero(j['radioValidacionMetros']) ?? 60,
      );
}

class Perfil {
  final int id;
  final String login;
  final String nombre;
  final List<String> roles;
  final List<String> tipos;
  final ConfiguracionMovil configuracion;

  const Perfil(this.id, this.login, this.nombre, this.roles, this.tipos, this.configuracion);

  factory Perfil.desdeJson(Map<String, dynamic> j) => Perfil(
        _entero(j['id']) ?? 0,
        j['login'] as String? ?? '',
        j['nombre'] as String? ?? '',
        List<String>.from(j['roles'] as List? ?? const []),
        List<String>.from(j['tipos'] as List? ?? const []),
        ConfiguracionMovil.desdeJson(j['configuracion'] as Map<String, dynamic>? ?? const {}),
      );

  String get rolVisible => tipos.map((t) => t == 'Corte' ? 'Cortador' : 'Reconectador').join(' · ');
}

/// Parada pendiente en el orden de la ruta.
class Tarea {
  final int idDetalle;
  final int idAsignacion;
  final String tipo; // 'Corte' | 'Reconexion'
  final String estadoAsignacion;
  final int orden;
  final int idCodigo;
  final int? codFijo;
  final String? nombre;
  final double lat;
  final double lon;
  final double distanciaTramoMetros;
  final double distanciaAccesoMetros;

  const Tarea(this.idDetalle, this.idAsignacion, this.tipo, this.estadoAsignacion, this.orden, this.idCodigo,
      this.codFijo, this.nombre, this.lat, this.lon, this.distanciaTramoMetros, this.distanciaAccesoMetros);

  factory Tarea.desdeJson(Map<String, dynamic> j) => Tarea(
        _entero(j['idDetalle']) ?? 0,
        _entero(j['idAsignacion']) ?? 0,
        j['tipo'] as String? ?? 'Corte',
        j['estadoAsignacion'] as String? ?? '',
        _entero(j['orden']) ?? 0,
        _entero(j['idCodigo']) ?? 0,
        _entero(j['codFijo']),
        j['nombre'] as String?,
        _num(j['lat']),
        _num(j['lon']),
        _num(j['distanciaTramoMetros']),
        _num(j['distanciaAccesoMetros']),
      );

  bool get esCorte => tipo == 'Corte';
  String get nombreTipo => esCorte ? 'Corte' : 'Reconexión';
  /// Resultado que significa trabajo hecho; la alternativa es «Observado».
  String get resultadoRealizado => esCorte ? 'Cortado' : 'Reconectado';
  String get codigoVisible => '${codFijo ?? idCodigo}';
  LatLng get ubicacion => LatLng(lat, lon);
}

class ParadaRuta {
  final int idDetalle;
  final int orden;
  final String estado; // Pendiente | Ejecutada | Observada | Anulada
  final int idCodigo;
  final int? codFijo;
  final String? nombre;
  final LatLng punto;
  final List<LatLng> tramo;

  const ParadaRuta(
      this.idDetalle, this.orden, this.estado, this.idCodigo, this.codFijo, this.nombre, this.punto, this.tramo);

  factory ParadaRuta.desdeJson(Map<String, dynamic> j) => ParadaRuta(
        _entero(j['idDetalle']) ?? 0,
        _entero(j['orden']) ?? 0,
        j['estado'] as String? ?? '',
        _entero(j['idCodigo']) ?? 0,
        _entero(j['codFijo']),
        j['nombre'] as String?,
        puntoDesde(j['punto']),
        [for (final p in (j['tramo'] as List? ?? const [])) puntoDesde(p)],
      );

  bool get pendiente => estado == 'Pendiente';
  String get codigoVisible => '${codFijo ?? idCodigo}';
}

/// Ruta completa de una asignación (para el mapa).
class RutaAsignacion {
  final int idAsignacion;
  final String tipo;
  final LatLng partida;
  final double distanciaMetros;
  final List<ParadaRuta> paradas;

  const RutaAsignacion(this.idAsignacion, this.tipo, this.partida, this.distanciaMetros, this.paradas);

  factory RutaAsignacion.desdeJson(Map<String, dynamic> j) => RutaAsignacion(
        _entero(j['idAsignacion']) ?? 0,
        j['tipo'] as String? ?? 'Corte',
        puntoDesde(j['partida']),
        _num(j['distanciaMetros']),
        [for (final p in (j['paradas'] as List? ?? const [])) ParadaRuta.desdeJson(p as Map<String, dynamic>)],
      );
}

/// Respuesta del servidor al registrar una parada.
class ResultadoRegistro {
  final String estado;
  final double distanciaAlPuntoMetros;
  final bool dentroDelRadio;
  final int fotos;

  const ResultadoRegistro(this.estado, this.distanciaAlPuntoMetros, this.dentroDelRadio, this.fotos);

  factory ResultadoRegistro.desdeJson(Map<String, dynamic> j) => ResultadoRegistro(
        j['estado'] as String? ?? '',
        _num(j['distanciaAlPuntoMetros']),
        j['dentroDelRadio'] as bool? ?? false,
        _entero(j['fotos']) ?? 0,
      );
}

String formatoDistancia(double metros) =>
    metros >= 1000 ? '${(metros / 1000).toStringAsFixed(2).replaceAll('.', ',')} km' : '${metros.round()} m';

/// Lectura escrita por el trabajador («1234,5») → texto que entiende el servidor («1234.5»); null si no es válida.
/// Hasta 2 decimales y sin separador de miles: «1.234» sería ambiguo (¿mil doscientos treinta y cuatro o 1,234?).
String? normalizarLectura(String texto) {
  final t = texto.trim().replaceAll(' ', '').replaceAll(',', '.');
  return RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(t) ? t : null;
}

String nombreEstadoParada(String estado) => switch (estado) {
      'Pendiente' => 'Pendiente',
      'Ejecutada' => 'Realizada',
      'Observada' => 'Observada',
      'Anulada' => 'Anulada',
      _ => estado,
    };
