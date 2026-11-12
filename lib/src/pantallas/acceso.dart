// Pantalla de acceso del trabajador (cortador o reconectador) y dirección del servidor.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'comun.dart';
import 'tareas.dart';

class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({super.key, this.aviso});

  /// Mensaje al volver a esta pantalla, por ejemplo cuando la sesión venció.
  final String? aviso;

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  final _formulario = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _contrasena = TextEditingController();
  final _servidor = TextEditingController(text: ApiCliente.instancia.servidor);
  bool _ocultar = true;
  bool _enviando = false;
  late String? _error = widget.aviso;

  @override
  void dispose() {
    _login.dispose();
    _contrasena.dispose();
    _servidor.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ApiCliente.instancia.cambiarServidor(_servidor.text);
      await ApiCliente.instancia.iniciarSesion(_login.text.trim(), _contrasena.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PantallaTareas()));
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String? _validarServidor(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Ingrese la dirección del servidor.';
    final uri = Uri.tryParse(texto.contains('://') ? texto : 'http://$texto');
    return uri == null || uri.host.isEmpty ? 'La dirección no es válida (ejemplo: https://visorsig-backend.onrender.com).' : null;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formulario,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.water_drop_outlined, size: 56, color: tema.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('VisorSIG Campo',
                          textAlign: TextAlign.center,
                          style: tema.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700, color: tema.colorScheme.primary)),
                      const SizedBox(height: 4),
                      Text('Cortes y reconexiones del servicio de agua',
                          textAlign: TextAlign.center, style: tema.textTheme.bodyMedium),
                      const SizedBox(height: 28),
                      if (_error != null) ...[Aviso(_error!), const SizedBox(height: 16)],
                      TextFormField(
                        controller: _login,
                        decoration: const InputDecoration(labelText: 'Usuario', prefixIcon: Icon(Icons.person_outline)),
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Ingrese su usuario.' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _contrasena,
                        obscureText: _ocultar,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                            icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _ocultar = !_ocultar),
                          ),
                        ),
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _enviando ? null : _ingresar(),
                        validator: (v) => (v ?? '').isEmpty ? 'Ingrese su contraseña.' : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _enviando ? null : _ingresar,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        icon: _enviando
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(_enviando ? 'Ingresando…' : 'Ingresar'),
                      ),
                      const SizedBox(height: 16),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Servidor'),
                        subtitle: Text(ApiCliente.instancia.servidor, overflow: TextOverflow.ellipsis),
                        // Margen superior: sin él, la etiqueta flotante del campo queda recortada.
                        childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
                        children: [
                          TextFormField(
                            controller: _servidor,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(labelText: 'Dirección de la API'),
                            validator: _validarServidor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Servidor en la nube: https://visorsig-backend.onrender.com\n'
                            'Emulador local: http://10.0.2.2:5080',
                            style: tema.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
