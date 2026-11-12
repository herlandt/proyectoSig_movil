// VisorSIG Campo: aplicación móvil de cortadores y reconectadores (parte 2 del proyecto VisorDatosSIG 2026).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/api.dart';
import 'src/pantallas/acceso.dart';
import 'src/pantallas/tareas.dart';
import 'src/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiCliente.instancia.cargar();
  runApp(const VisorSigCampo());
}

class VisorSigCampo extends StatelessWidget {
  const VisorSigCampo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VisorSIG Campo',
        debugShowCheckedModeBanner: false,
        theme: temaVisor(),
        locale: const Locale('es', 'BO'),
        supportedLocales: const [Locale('es', 'BO'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Con un token guardado entra directo; si venció, la primera consulta lo devuelve al acceso.
        home: ApiCliente.instancia.conSesion ? const PantallaTareas() : const PantallaAcceso(),
      );
}
