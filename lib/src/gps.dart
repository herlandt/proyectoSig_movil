// GPS: permisos, ubicación actual y seguimiento del recorrido (envío periódico de posiciones para el monitoreo).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';

class ErrorGps implements Exception {
  final String mensaje;
  const ErrorGps(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Pide permiso y verifica que el GPS esté encendido. Lanza [ErrorGps] con un mensaje para el trabajador.
Future<void> asegurarGps() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ErrorGps('El GPS está apagado. Actívelo en los ajustes del celular.');
  }
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
  if (permiso == LocationPermission.denied) {
    throw const ErrorGps('Sin permiso de ubicación no se puede registrar el trabajo.');
  }
  if (permiso == LocationPermission.deniedForever) {
    throw const ErrorGps('El permiso de ubicación está bloqueado. Habilítelo en Ajustes > Aplicaciones > VisorSIG Campo.');
  }
}

/// Ubicación actual con alta precisión (lectura nueva, no la última guardada).
Future<Position> ubicacionActual() async {
  await asegurarGps();
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(accuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 25)),
    );
  } on TimeoutException {
    throw const ErrorGps('No se obtuvo señal GPS. Salga a un lugar abierto e intente de nuevo.');
  }
}

/// Android 13 o superior: sin este permiso la notificación «Recorrido en curso» no aparece (el envío funciona igual).
Future<void> pedirPermisoNotificaciones() async {
  if (await Permission.notification.isDenied) await Permission.notification.request();
}

/// Seguimiento del recorrido: escucha el GPS con un servicio en primer plano (notificación permanente) y envía
/// las posiciones acumuladas cada [intervalo]. Si no hay red, las conserva y las reenvía en el siguiente intento.
class Seguimiento extends ChangeNotifier {
  Seguimiento._();
  static final Seguimiento instancia = Seguimiento._();

  static const _maximoPorEnvio = 500;    // límite del servidor
  static const _maximoEnCola = 2000;

  StreamSubscription<Position>? _suscripcion;
  Timer? _temporizador;
  final List<Map<String, dynamic>> _pendientes = [];
  bool _enviando = false;
  int? _idAsignacion;
  DateTime? ultimoEnvio;
  int enviadas = 0;
  String? ultimoError;

  bool get activo => _suscripcion != null;
  int get enCola => _pendientes.length;
  int? get idAsignacion => _idAsignacion;

  Future<void> iniciar({required int? idAsignacion, required int intervaloSegundos}) async {
    await asegurarGps();
    await detener(enviarPendientes: false);
    _idAsignacion = idAsignacion;
    ultimoError = null;
    final intervalo = Duration(seconds: intervaloSegundos.clamp(5, 600));
    _suscripcion = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: intervalo,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Recorrido en curso',
          notificationText: 'VisorSIG Campo está enviando su ubicación al supervisor.',
          enableWakeLock: true,
        ),
      ),
    ).listen(_agregar, onError: (Object _) {
      ultimoError = 'Se perdió la señal GPS o el GPS fue apagado.';
      notifyListeners();
    });
    _temporizador = Timer.periodic(intervalo, (_) => enviar());
    notifyListeners();
  }

  void _agregar(Position p) {
    _pendientes.add({
      'fecha': isoConZona(p.timestamp.toLocal()),
      'lat': p.latitude,
      'lon': p.longitude,
      'precision': p.accuracy,
      'velocidad': p.speed,
    });
    // Sin red durante horas: se descartan las más antiguas (no mientras un envío está en curso).
    if (!_enviando && _pendientes.length > _maximoEnCola) _pendientes.removeRange(0, _pendientes.length - _maximoEnCola);
    notifyListeners();
  }

  Future<void> enviar() async {
    if (_enviando || _pendientes.isEmpty) return;
    _enviando = true;
    final lote = List<Map<String, dynamic>>.from(_pendientes.take(_maximoPorEnvio));
    try {
      enviadas += await ApiCliente.instancia.enviarPosiciones(_idAsignacion, lote);
      _pendientes.removeRange(0, lote.length);
      ultimoEnvio = DateTime.now();
      ultimoError = null;
    } on ErrorApi catch (e) {
      ultimoError = e.mensaje;
      if (e.estado == 400) _pendientes.removeRange(0, lote.length);   // lote rechazado: reenviarlo no sirve
      if (e.sesionVencida) await detener(enviarPendientes: false);    // sin sesión no hay a quién enviar
      // Sin red o error del servidor: se reintenta en el próximo ciclo.
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }

  Future<void> detener({bool enviarPendientes = true}) async {
    _temporizador?.cancel();
    _temporizador = null;
    await _suscripcion?.cancel();
    _suscripcion = null;
    if (enviarPendientes) await enviar();
    notifyListeners();
  }
}
