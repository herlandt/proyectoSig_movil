// Pruebas de la app móvil: lectura de la API, reglas del formulario y pantalla de acceso.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:visor_sig_movil/src/api.dart';
import 'package:visor_sig_movil/src/modelos.dart';
import 'package:visor_sig_movil/src/pantallas/acceso.dart';

void main() {
  test('Tarea se lee de la API y conoce su resultado', () {
    final t = Tarea.desdeJson({
      'idDetalle': 5, 'idAsignacion': 2, 'tipo': 'Reconexion', 'estadoAsignacion': 'Pendiente', 'orden': 3,
      'idCodigo': 77, 'codFijo': 1234, 'nombre': 'Juan Pérez', 'lat': -16.37, 'lon': -60.96,
      'distanciaTramoMetros': 120.5, 'distanciaAccesoMetros': 8.2,
    });
    expect(t.esCorte, isFalse);
    expect(t.nombreTipo, 'Reconexión');
    expect(t.resultadoRealizado, 'Reconectado');
    expect(t.codigoVisible, '1234');
    expect(t.ubicacion.latitude, -16.37);
    expect(t.ubicacion.longitude, -60.96);
  });

  test('Ruta: los puntos de la API vienen como [lon, lat]', () {
    final r = RutaAsignacion.desdeJson({
      'idAsignacion': 1, 'tipo': 'Corte', 'partida': [-60.96, -16.37], 'distanciaMetros': 1500,
      'paradas': [
        {
          'idDetalle': 9, 'orden': 1, 'estado': 'Pendiente', 'idCodigo': 4, 'codFijo': null, 'nombre': null,
          'punto': [-60.95, -16.38], 'tramo': [[-60.96, -16.37], [-60.955, -16.375], [-60.95, -16.38]],
        },
      ],
    });
    expect(r.partida.latitude, -16.37);
    expect(r.partida.longitude, -60.96);
    final parada = r.paradas.single;
    expect(parada.pendiente, isTrue);
    expect(parada.tramo, hasLength(3));
    expect(parada.codigoVisible, '4');
  });

  test('Lectura: coma decimal aceptada, separador de miles rechazado', () {
    expect(normalizarLectura('1234,5'), '1234.5');
    expect(normalizarLectura(' 98.25 '), '98.25');
    expect(normalizarLectura('0'), '0');
    expect(normalizarLectura('1.234,5'), isNull);
    expect(normalizarLectura('12.345'), isNull);
    expect(normalizarLectura('-3'), isNull);
    expect(normalizarLectura('1e5'), isNull);
  });

  test('Fecha con desfase horario para el servidor', () {
    final texto = isoConZona(DateTime(2026, 10, 30, 9, 5, 7));
    expect(RegExp(r'^2026-10-30T09:05:07\.000[+-]\d{2}:\d{2}$').hasMatch(texto), isTrue, reason: texto);
  });

  test('Distancias legibles', () {
    expect(formatoDistancia(85.4), '85 m');
    expect(formatoDistancia(1530), '1,53 km');
  });

  testWidgets('El acceso pide usuario y contraseña antes de llamar al servidor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PantallaAcceso(aviso: 'La sesión venció. Ingrese nuevamente.')));
    expect(find.text('La sesión venció. Ingrese nuevamente.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pump();
    expect(find.text('Ingrese su usuario.'), findsOneWidget);
    expect(find.text('Ingrese su contraseña.'), findsOneWidget);
  });
}
