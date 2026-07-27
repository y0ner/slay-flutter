import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/slay_theme.dart';
import '../../core/supabase/supabase_config.dart';
import '../../data/repositories/auth_repository.dart';

/// Pantalla de inicio de sesión / registro.
/// Si Supabase no está configurado (--dart-define faltante), permite
/// entrar igual como "demo local" para poder testear la UI sin backend.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _isRegister = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Trae el foco al email apenas entra para que el teclado no tape
    // la marca. En web/desktop no hace nada visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && MediaQuery.of(context).viewInsets.bottom == 0) {
        _emailFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Quitar foco y bajar el teclado antes del spinner.
    _emailFocus.unfocus();
    _passFocus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    // Feedback háptico sutil al enviar.
    HapticFeedback.selectionClick();
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegister) {
        await repo.signUp(_emailCtrl.text.trim(), _passCtrl.text);
      } else {
        await repo.signIn(_emailCtrl.text.trim(), _passCtrl.text);
      }
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mapea errores crudos de Supabase a algo más legible.
  String _friendlyError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('invalid login credentials') ||
        s.contains('invalid credentials')) {
      return 'Email o contraseña incorrectos.';
    }
    if (s.contains('user already registered')) {
      return 'Ese email ya está registrado. Probá iniciar sesión.';
    }
    if (s.contains('email not confirmed')) {
      return 'Revisá tu casilla y confirmá el email.';
    }
    if (s.contains('network') ||
        s.contains('socket') ||
        s.contains('failed host') ||
        s.contains('timeout')) {
      return 'Sin conexión. Revisá tu internet.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final configured = SupabaseConfig.isConfigured;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    // Padding bottom para que el teclado no tape el botón de submit.
    final keyboardInset = media.viewInsets.bottom;
    return Scaffold(
      // Bug #11: fondo con gradiente del theme (igual que el resto de
      // la app) en vez de un color plano. En dark mode evita el
      // "pantallazo negro" durante la transición post-logout.
      body: Container(
        decoration: BoxDecoration(
          gradient: slayBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ).copyWith(bottom: 24 + keyboardInset),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Branding ─────────────────────────────
                      _Brand(),
                      const SizedBox(height: 28),
                      Text(
                        'Slay',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegister
                            ? 'Creá tu cuenta'
                            : 'Bienvenido de vuelta',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gestioná tus tareas, categorías y pomodoros.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (!configured) ...[
                        _OfflineBanner(),
                        const SizedBox(height: 16),
                      ],

                      // ── Form card ────────────────────────────
                      // El Card eleva visualmente el formulario y lo
                      // separa del fondo con gradiente.
                      Card(
                        elevation: 0,
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailCtrl,
                                focusNode: _emailFocus,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                onFieldSubmitted: (_) => _passFocus.requestFocus(),
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Ingresá tu email'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passCtrl,
                                focusNode: _passFocus,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                keyboardType: TextInputType.visiblePassword,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _obscure = !_obscure);
                                    },
                                  ),
                                ),
                                validator: (v) => (v == null || v.length < 6)
                                    ? 'Mínimo 6 caracteres'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: scheme.onErrorContainer, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Submit ────────────────────────────────
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _loading
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _isRegister
                                        ? 'Crear cuenta'
                                        : 'Entrar',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isRegister = !_isRegister;
                                  _error = null;
                                });
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.primary,
                        ),
                        child: Text(
                          _isRegister
                              ? '¿Ya tenés cuenta? Iniciar sesión'
                              : '¿Sos nuevo? Crear cuenta',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
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

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Supabase no está configurado.\n'
              'Compila con --dart-define=SUPABASE_URL=... y SUPABASE_ANON_KEY=...',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo con gradiente y animación de pulse sutil. Reemplaza al
/// cuadrado plano anterior: aporta identidad visual al primer impacto
/// en la app.
class _Brand extends StatefulWidget {
  const _Brand();

  @override
  State<_Brand> createState() => _BrandState();
}

class _BrandState extends State<_Brand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Aura detrás del logo (sólo se ve en dark)
              if (isDark)
                Container(
                  width: 96 + (_pulse.value * 16),
                  height: 96 + (_pulse.value * 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.35),
                        scheme.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.bolt,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }
}