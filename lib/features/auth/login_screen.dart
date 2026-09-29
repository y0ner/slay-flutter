import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase/supabase_config.dart';
import '../../core/theme/terminal_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/shimmer_loader.dart';

/// Login estilo "terminal cálida" (referencia: prompt >_ naranja,
/// panel oscuro con borde 1px, etiquetas con marcador naranja,
/// botón primario naranja cuadrado, input con ícono y sin redondeos).
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
    _emailFocus.unfocus();
    _passFocus.unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

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
    if (s.contains('password should be at least')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (s.contains('failed host') ||
        s.contains('name or service not known') ||
        s.contains('connection refused') ||
        s.contains('502') ||
        s.contains('503') ||
        s.contains('504')) {
      return 'El servidor de Supabase no responde o está pausado.';
    }
    if (s.contains('network') ||
        s.contains('socket') ||
        s.contains('timeout')) {
      return 'Problema de conexión con Supabase. Verificá tu red.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final configured = SupabaseConfig.isConfigured;

    return Scaffold(
      backgroundColor: TerminalTheme.nightBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // FIX perf: Scaffold ya redimensiona el body cuando se abre
            // el teclado (resizeToAvoidBottomInset por defecto). Depender
            // de `viewInsets` acá provocaba un rebuild completo en CADA
            // frame de la animación del teclado.
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _LoginCard(
                configured: configured,
                isRegister: _isRegister,
                obscure: _obscure,
                loading: _loading,
                error: _error,
                formKey: _formKey,
                emailCtrl: _emailCtrl,
                passCtrl: _passCtrl,
                emailFocus: _emailFocus,
                passFocus: _passFocus,
                onSubmit: _submit,
                onToggleRegister: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isRegister = !_isRegister;
                    _error = null;
                  });
                },
                onToggleObscure: () {
                  HapticFeedback.selectionClick();
                  setState(() => _obscure = !_obscure);
                },
                onContinueLocal: () => context.go('/'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.configured,
    required this.isRegister,
    required this.obscure,
    required this.loading,
    required this.error,
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.emailFocus,
    required this.passFocus,
    required this.onSubmit,
    required this.onToggleRegister,
    required this.onToggleObscure,
    required this.onContinueLocal,
  });

  final bool configured;
  final bool isRegister;
  final bool obscure;
  final bool loading;
  final String? error;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final FocusNode emailFocus;
  final FocusNode passFocus;
  final VoidCallback onSubmit;
  final VoidCallback onToggleRegister;
  final VoidCallback onToggleObscure;
  final VoidCallback onContinueLocal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      decoration: BoxDecoration(
        color: TerminalTheme.nightPanel,
        border: Border.all(color: TerminalTheme.nightLine, width: 1),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Prompt >_ como logo ──────────────────────────
            const _PromptGlyph(),
            const SizedBox(height: 20),

            Text(
              isRegister ? 'Crear cuenta' : 'Iniciar sesión',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: TerminalTheme.pixelFamily,
                fontSize: 28,
                color: TerminalTheme.nightFg,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isRegister
                  ? 'Creá tu cuenta para empezar.'
                  : 'Accedé a tu cuenta para continuar.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontSize: 13.5,
                color: TerminalTheme.nightMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            if (!configured) ...[
              _OfflineNotice(onContinue: onContinueLocal),
              const SizedBox(height: 20),
            ],

            _FieldLabel('CORREO ELECTRÓNICO'),
            const SizedBox(height: 8),
            _TerminalField(
              controller: emailCtrl,
              focusNode: emailFocus,
              hint: 'tu@email.com',
              icon: Icons.mail_outline_rounded,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => passFocus.requestFocus(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresá tu correo electrónico';
                }
                if (!v.contains('@') || !v.contains('.')) {
                  return 'Ingresá un correo válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            _FieldLabel('CONTRASEÑA'),
            const SizedBox(height: 8),
            _TerminalField(
              controller: passCtrl,
              focusNode: passFocus,
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => onSubmit(),
              suffixIcon: IconButton(
                tooltip: obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                  color: TerminalTheme.nightMuted,
                ),
                onPressed: onToggleObscure,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresá tu contraseña';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),

            if (error != null) ...[
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: TerminalTheme.nightHeart.withValues(alpha: 0.10),
                  border: Border.all(
                    color: TerminalTheme.nightHeart.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: TerminalTheme.nightHeart, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          fontFamily: TerminalTheme.monoFamily,
                          color: TerminalTheme.nightHeart,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ── Botón primario naranja cuadrado ──────────────
            _PrimaryButton(
              text: isRegister ? 'Crear cuenta' : 'Iniciar sesión',
              loading: loading,
              onPressed: loading ? null : onSubmit,
            ),
            const SizedBox(height: 28),

            // ── Separador "o continua con" ───────────────────
            const _DividerWithLabel('o continua con'),
            const SizedBox(height: 20),

            // ── Botón GitHub outline ─────────────────────────
            _GithubButton(),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isRegister
                      ? '¿Ya tenés una cuenta? '
                      : '¿No tenés una cuenta? ',
                  style: const TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 12.5,
                    color: TerminalTheme.nightMuted,
                  ),
                ),
                GestureDetector(
                  onTap: loading ? null : onToggleRegister,
                  child: Text(
                    isRegister ? 'Iniciar sesión' : 'Registrate',
                    style: const TextStyle(
                      fontFamily: TerminalTheme.monoFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: TerminalTheme.nightAccent,
                      decoration: TextDecoration.underline,
                      decorationColor: TerminalTheme.nightAccent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El prompt `>_` en naranja — firma visual del login.
class _PromptGlyph extends StatelessWidget {
  const _PromptGlyph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '>',
              style: TextStyle(
                fontFamily: TerminalTheme.pixelFamily,
                fontSize: 40,
                height: 1,
                color: TerminalTheme.nightAccent,
              ),
            ),
            SizedBox(width: 4),
            Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: _UnderscoreBlock(),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnderscoreBlock extends StatelessWidget {
  const _UnderscoreBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 7,
      color: TerminalTheme.nightAccent,
    );
  }
}

/// Etiqueta de campo: cuadradito naranja + texto en mayúsculas.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          color: TerminalTheme.nightAccent,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontFamily: TerminalTheme.monoFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: TerminalTheme.nightAccent,
          ),
        ),
      ],
    );
  }
}

/// Input de la casa: fondo nightBg, borde 1px nightLine, cuadrado,
/// ícono a la izquierda. Sin redondeos, sin glows.
class _TerminalField extends StatelessWidget {
  const _TerminalField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.keyboardType = TextInputType.text,
    this.autofillHints,
    this.onSubmitted,
    this.validator,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: const TextStyle(
        fontFamily: TerminalTheme.monoFamily,
        fontSize: 14.5,
        color: TerminalTheme.nightFg,
      ),
      cursorColor: TerminalTheme.nightAccent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: TerminalTheme.monoFamily,
          fontSize: 14,
          color: TerminalTheme.nightMuted,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: TerminalTheme.nightMuted,
        ),
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        filled: true,
        fillColor: TerminalTheme.nightBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: TerminalTheme.nightLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: TerminalTheme.nightLine),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: TerminalTheme.nightAccent,
            width: 1.2,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: TerminalTheme.nightHeart),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: TerminalTheme.nightHeart,
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Botón primario: naranja sólido, cuadrado, texto en mono bold.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.text,
    required this.loading,
    required this.onPressed,
  });

  final String text;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: const BoxDecoration(color: TerminalTheme.nightAccent),
        child: Center(
          child: loading
              ? ShimmerLoader(size: 20, strokeWidth: 2.2, color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        fontFamily: TerminalTheme.monoFamily,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GithubButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: TerminalTheme.nightLine, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.code_rounded,
              size: 20, color: TerminalTheme.nightFg),
          const SizedBox(width: 10),
          Text(
            'GitHub',
            style: const TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: TerminalTheme.nightFg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Separador con texto centrado: línea — texto — línea.
class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: TerminalTheme.nightLine, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: TerminalTheme.monoFamily,
              fontSize: 12,
              color: TerminalTheme.nightMuted,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: TerminalTheme.nightLine, thickness: 1),
        ),
      ],
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TerminalTheme.nightAccent.withValues(alpha: 0.08),
        border: Border.all(
          color: TerminalTheme.nightAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: TerminalTheme.nightAccent, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supabase no está configurado (--dart-define). Podés probar Slay con la base de datos local.',
                  style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 12,
                    color: TerminalTheme.nightFg,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onContinue,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: TerminalTheme.nightAccent),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continuar sin cuenta (demo local)',
                      style: TextStyle(
                        fontFamily: TerminalTheme.monoFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: TerminalTheme.nightAccent,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward,
                        size: 16, color: TerminalTheme.nightAccent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
