// Piezas comunes de los mapas: teselas de OpenStreetMap (con su atribución obligatoria) y marcadores.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tema.dart';

/// La política de uso de OpenStreetMap exige identificar la aplicación en el User-Agent.
/// [fundido] en false muestra cada tesela apenas llega (sin capa de opacidad), como conviene a un mapa pequeño y fijo.
TileLayer capaOsm({bool fundido = true}) => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'bo.edu.uagrm.ficct.visor_sig_movil',
      maxNativeZoom: 19,
      tileDisplay: fundido ? const TileDisplay.fadeIn() : const TileDisplay.instantaneous(),
    );

Widget atribucionOsm() => RichAttributionWidget(
      showFlutterMapAttribution: false,
      attributions: [
        TextSourceAttribution('Colaboradores de OpenStreetMap',
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
      ],
    );

/// Círculo numerado de una parada (el número es el orden de la ruta, no solo el color).
Marker marcadorParada(LatLng punto, int orden, {required Color color, bool resaltada = false, VoidCallback? alTocar}) {
  final lado = resaltada ? 42.0 : 34.0;
  return Marker(
    point: punto,
    width: lado,
    height: lado,
    child: GestureDetector(
      onTap: alTocar,
      child: Semantics(
        button: alTocar != null,
        label: 'Parada $orden',
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: resaltada ? colorResalte : Colors.white, width: resaltada ? 4 : 2),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
          child: Text('$orden', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    ),
  );
}

Marker marcadorPartida(LatLng punto) => Marker(
      point: punto,
      width: 34,
      height: 34,
      child: Semantics(
        label: 'Punto de partida',
        child: Container(
          decoration: BoxDecoration(
            color: colorPrimarioOscuro,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
          child: const Icon(Icons.flag, color: Colors.white, size: 18),
        ),
      ),
    );

/// Destino con forma de alfiler: la punta queda sobre el código fijo.
Marker marcadorDestino(LatLng punto) => Marker(
      point: punto,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: const Icon(Icons.location_on, color: colorPeligro, size: 44, semanticLabel: 'Código fijo'),
    );

/// Posición del trabajador: punto azul con el círculo de precisión del GPS.
List<Widget> capasPosicion(LatLng punto, double precisionMetros) => [
      CircleLayer(circles: [
        CircleMarker(
          point: punto,
          radius: precisionMetros.clamp(3, 500),
          useRadiusInMeter: true,
          color: const Color(0x331A73E8),
          borderColor: const Color(0x881A73E8),
          borderStrokeWidth: 1,
        ),
      ]),
      MarkerLayer(markers: [
        Marker(
          point: punto,
          width: 22,
          height: 22,
          child: Semantics(
            label: 'Mi ubicación',
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
              ),
            ),
          ),
        ),
      ]),
    ];
