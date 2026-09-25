import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase/supabase_config.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/shimmer_loader.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    const emeraldAccent = Color(0xFF10B981);
    const emeraldLight = Color(0xFF34D399);
    final accent = isDark ? emeraldLight : emeraldAccent;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF09090B) : const Color(0xFFF4F4F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ).copyWith(bottom: 24 + keyboardInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _LoginCard(
                isDark: isDark,
                accent: accent,
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
    required this.isDark,
    required this.accent,
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

  final bool isDark;
  final Color accent;
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
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF121214)
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(isRegister: isRegister, accent: accent, isDark: isDark),
            const SizedBox(height: 24),

            _ModeSelector(
              isRegister: isRegister,
              accent: accent,
              isDark: isDark,
              onSelect: (v) {
                if (isRegister != v) onToggleRegister();
              },
            ),
            const SizedBox(height: 28),

            if (!configured) ...[
              _OfflineNotice(
                accent: accent,
                isDark: isDark,
                onContinue: onContinueLocal,
              ),
              const SizedBox(height: 20),
            ],

            _InputField(
              label: 'Correo electrónico',
              hint: 'tu@email.com',
              icon: Icons.mail_outline_rounded,
              controller: emailCtrl,
              focusNode: emailFocus,
              accent: accent,
              isDark: isDark,
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

            _InputField(
              label: 'Contraseña',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              controller: passCtrl,
              focusNode: passFocus,
              accent: accent,
              isDark: isDark,
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
                  color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
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

            _SubmitButton(
              text: isRegister ? 'Crear cuenta' : 'Iniciar sesión',
              loading: loading,
              accent: accent,
              isDark: isDark,
              onPressed: loading ? null : onSubmit,
            ),

            const SizedBox(height: 20),

            Center(
              child: GestureDetector(
                onTap: loading ? null : onToggleRegister,
                child: Text(
                  isRegister
                      ? '¿Ya tenés una cuenta? Iniciar sesión'
                      : '¿No tenés una cuenta? Creá una aquí',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isRegister,
    required this.accent,
    required this.isDark,
  });

  final bool isRegister;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.25 : 0.18),
                accent.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.45 : 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.25 : 0.12),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(Icons.bolt_rounded, color: accent, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          isRegister ? 'Creá tu cuenta' : 'Bienvenido a Slay',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: isDark ? const Color(0xFFFAFAFA) : const Color(0xFF09090B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gestioná tus tareas, categorías y pomodoros con foco.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.isRegister,
    required this.accent,
    required this.isDark,
    required this.onSelect,
  });

  final bool isRegister;
  final Color accent;
  final bool isDark;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFE4E4E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF27272A) : const Color(0xFFD4D4D8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth - 4) / 2;
          return Stack(
            children: [
              Align(
                alignment: isRegister ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: tabWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF27272A) : Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onSelect(false),
                      child: Center(
                        child: Text(
                          'Iniciar sesión',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: !isRegister ? FontWeight.w700 : FontWeight.w500,
                            color: !isRegister
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onSelect(true),
                      child: Center(
                        child: Text(
                          'Registrarse',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isRegister ? FontWeight.w700 : FontWeight.w500,
                            color: isRegister
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.isDark,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.keyboardType = TextInputType.text,
    this.autofillHints,
    this.onSubmitted,
    this.validator,
    this.suffixIcon,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final bool isDark;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181B) : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              textInputAction: textInputAction,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              onFieldSubmitted: onSubmitted,
              validator: validator,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                ),
                prefixIcon: Icon(
                  icon,
                  size: 20,
                  color: isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                ),
                suffixIcon: suffixIcon,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.text,
    required this.loading,
    required this.accent,
    required this.isDark,
    required this.onPressed,
  });

  final String text;
  final bool loading;
  final Color accent;
  final bool isDark;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1E1E24), const Color(0xFF121215)]
                : [const Color(0xFF27272A), const Color(0xFF09090B)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFF18181B),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (loading)
                ShimmerLoader(size: 20, strokeWidth: 2.2, color: accent)
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                  ],
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        accent.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({
    required this.accent,
    required this.isDark,
    required this.onContinue,
  });

  final Color accent;
  final bool isDark;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supabase no está configurado (--dart-define). Podés probar Slay con la base de datos local.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onContinue,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continuar sin cuenta (demo local)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}