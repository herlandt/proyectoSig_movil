// Elementos compartidos por las pantallas.
import 'package:flutter/material.dart';

import '../api.dart';
import '../gps.dart';
import '../modelos.dart';
import '../tema.dart';
import 'acceso.dart';

enum TipoAviso { error, advertencia, exito }

/// Mensaje dentro de la pantalla (no solo color: lleva icono y texto; los lectores de pantalla lo anuncian).
class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.tipo = TipoAviso.error});

  final String texto;
  final TipoAviso tipo;

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (tipo) {
      TipoAviso.error => (colorPeligro, Icons.error_outline),
      TipoAviso.advertencia => (colorAviso, Icons.warning_amber_rounded),
      TipoAviso.exito => (colorExito, Icons.check_circle_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }
}

/// Cierra la sesión del celular (envía antes las posiciones pendientes) y vuelve a la pantalla de acceso.
Future<void> irAlAcceso(BuildContext context, {String? aviso}) async {
  await Seguimiento.instancia.detener();
  await ApiCliente.instancia.cerrarSesion();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => PantallaAcceso(aviso: aviso)), (_) => false);
}

const avisoSesionVencida = 'La sesión venció. Ingrese nuevamente.';

/// Resumen para el trabajador de lo que guardó el servidor.
String resumenRegistro(ResultadoRegistro r) {
  final estado = r.estado == 'Ejecutada' ? 'Trabajo registrado' : 'Parada registrada como observada';
  final lugar = 'a ${formatoDistancia(r.distanciaAlPuntoMetros)} del código${r.dentroDelRadio ? '' : ' (fuera del radio)'}';
  return '$estado · $lugar · ${r.fotos} foto(s)';
}

String formatoHora(DateTime fecha) =>
    '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
