// Colores y tema: los mismos del visor web (sitio.css) para que ambas aplicaciones se reconozcan como un sistema.
import 'package:flutter/material.dart';

const colorPrimario = Color(0xFF1F4E79);
const colorPrimarioOscuro = Color(0xFF163A5A);
const colorExito = Color(0xFF198754);
const colorAviso = Color(0xFF9A5B00);     // ámbar oscuro: legible como texto sobre fondo claro
const colorPeligro = Color(0xFFB02A37);
const colorResalte = Color(0xFFFFD400);   // siguiente parada (mismo resaltado del visor web)
const colorNeutro = Color(0xFF6C757D);

ThemeData temaVisor() {
  final esquema = ColorScheme.fromSeed(seedColor: colorPrimario).copyWith(primary: colorPrimario, onPrimary: Colors.white);
  return ThemeData(
    colorScheme: esquema,
    appBarTheme: const AppBarTheme(backgroundColor: colorPrimario, foregroundColor: Colors.white),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
