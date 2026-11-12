// Cliente HTTP de la API móvil (token Bearer). Los errores del servidor (ProblemDetails) llegan en español.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

class ErrorApi implements Exception {
  final String mensaje;
  final int? estado;
  const ErrorApi(this.mensaje, [this.estado]);
  bool get sesionVencida => estado == 401;
  @override
  String toString() => mensaje;
}

/// Hora local con su desfase (ISO 8601): el servidor la convierte a la hora de Bolivia.
String isoConZona(DateTime fecha) {
  final o = fecha.timeZoneOffset;
  final signo = o.isNegative ? '-' : '+';
  final h = o.inHours.abs().toString().padLeft(2, '0');
  final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${fecha.toIso8601String()}$signo$h:$m';
}

class ApiCliente {
  ApiCliente._();
  static final ApiCliente instancia = ApiCliente._();

  /// En el emulador de Android, 10.0.2.2 es la computadora; con un celular por USB se usa «adb reverse».
  static const servidorPorDefecto = 'http://10.0.2.2:5080';
  static const _claveServidor = 'servidor';
  static const _claveToken = 'token';

  final _almacen = const FlutterSecureStorage();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 40),
    sendTimeout: const Duration(seconds: 60),
  ));
  String? _token;
  String servidor = servidorPorDefecto;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    servidor = prefs.getString(_claveServidor) ?? servidorPorDefecto;
    _token = await _almacen.read(key: _claveToken);
  }

  bool get conSesion => _token != null;

  Future<void> cambiarServidor(String url) async {
    var limpio = url.trim();
    while (limpio.endsWith('/')) {
      limpio = limpio.substring(0, limpio.length - 1);
    }
    if (!limpio.startsWith('http://') && !limpio.startsWith('https://')) limpio = 'http://$limpio';
    servidor = limpio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveServidor, limpio);
  }

  Future<void> iniciarSesion(String login, String contrasena) async {
    final r = await _enviar(() => _dio.post('$servidor/api/movil/sesion',
        data: {'login': login, 'contrasena': contrasena}, options: Options(headers: _cabeceras(conToken: false))));
    final token = (r.data as Map<String, dynamic>)['accessToken'] as String?;
    if (token == null) throw const ErrorApi('El servidor no devolvió un token de sesión.');
    _token = token;
    await _almacen.write(key: _claveToken, value: token);
  }

  Future<void> cerrarSesion() async {
    _token = null;
    await _almacen.delete(key: _claveToken);
  }

  Future<Perfil> perfil() async => Perfil.desdeJson((await _get('/api/movil/perfil')) as Map<String, dynamic>);

  Future<List<Tarea>> tareas() async =>
      [for (final t in (await _get('/api/movil/tareas')) as List) Tarea.desdeJson(t as Map<String, dynamic>)];

  Future<RutaAsignacion> ruta(int idAsignacion) async =>
      RutaAsignacion.desdeJson((await _get('/api/movil/asignaciones/$idAsignacion/ruta')) as Map<String, dynamic>);

  Future<void> iniciarRecorrido(int idAsignacion) =>
      _enviar(() => _dio.post('$servidor/api/movil/asignaciones/$idAsignacion/iniciar', options: Options(headers: _cabeceras())));

  /// Registro de la parada con sus fotos (multipart). La ubicación es obligatoria: sin ella el servidor no guarda.
  Future<ResultadoRegistro> registrar({
    required int idDetalle,
    required String resultado,
    String? numeroMedidor,
    String? lectura,
    String? observacion,
    required double lat,
    required double lon,
    double? precision,
    required List<File> fotos,
  }) async {
    final datos = FormData.fromMap({
      'resultado': resultado,
      if (numeroMedidor != null && numeroMedidor.isNotEmpty) 'numeroMedidor': numeroMedidor,
      if (lectura != null && lectura.isNotEmpty) 'lectura': lectura,
      if (observacion != null && observacion.isNotEmpty) 'observacion': observacion,
      'lat': lat.toString(),
      'lon': lon.toString(),
      if (precision != null) 'precision': precision.toStringAsFixed(1),
      'fechaDispositivo': isoConZona(DateTime.now()),
      'fotos': [
        for (var i = 0; i < fotos.length; i++)
          await MultipartFile.fromFile(fotos[i].path, filename: 'evidencia_${i + 1}.jpg'),
      ],
    });
    final r = await _enviar(() => _dio.post('$servidor/api/movil/tareas/$idDetalle/ejecucion',
        data: datos, options: Options(headers: _cabeceras())));
    return ResultadoRegistro.desdeJson(r.data as Map<String, dynamic>);
  }

  Future<int> enviarPosiciones(int? idAsignacion, List<Map<String, dynamic>> posiciones) async {
    final r = await _enviar(() => _dio.post('$servidor/api/movil/posiciones',
        data: {'idAsignacion': idAsignacion, 'posiciones': posiciones}, options: Options(headers: _cabeceras())));
    return ((r.data as Map<String, dynamic>)['guardadas'] as num?)?.toInt() ?? 0;
  }

  Map<String, String> _cabeceras({bool conToken = true}) => {
        'Accept': 'application/json',
        if (conToken && _token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _get(String ruta) async =>
      (await _enviar(() => _dio.get('$servidor$ruta', options: Options(headers: _cabeceras())))).data;

  Future<Response<dynamic>> _enviar(Future<Response<dynamic>> Function() solicitud) async {
    try {
      return await solicitud();
    } on DioException catch (e) {
      final r = e.response;
      if (r == null) {
        throw ErrorApi('No se pudo conectar con el servidor ($servidor). Revise la red y la dirección del servidor.');
      }
      if (r.statusCode == 401 && _token != null) await cerrarSesion();
      final datos = r.data;
      String? mensaje;
      if (datos is Map) mensaje = (datos['detail'] ?? datos['title'])?.toString();
      throw ErrorApi(mensaje ?? (r.statusCode == 401 ? 'La sesión venció. Ingrese nuevamente.' : 'Error del servidor (${r.statusCode}).'),
          r.statusCode);
    }
  }
}
