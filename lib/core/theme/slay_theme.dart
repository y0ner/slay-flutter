import 'package:flutter/material.dart';

/// Paleta y tema de Slay. Mantiene los nombres y valores exactos
/// de la versión original (Android/Compose) para preservar la
/// identidad visual tras la migración.
class SlayTheme {
  // ── Colores originales (mismos hex que Color.kt) ─────────
  static const Color lightBg = Color(0xFFF5F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1F2937);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightAccent = Color(0xFF10B981); // emerald green
  static const Color lightBorder = Color(0xFFE5E7EB);

  static const Color darkBg = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF27272A);
  static const Color darkTextPrimary = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkAccent = Color(0xFF34D399); // emerald green claro

  // ── ColorSchemes ─────────────────────────────────────────
  static final ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightAccent,
    onPrimary: Colors.white,
    primaryContainer: lightAccent.withValues(alpha: 0.15),
    onPrimaryContainer: lightAccent,
    secondary: lightAccent,
    onSecondary: Colors.white,
    secondaryContainer: lightAccent.withValues(alpha: 0.15),
    onSecondaryContainer: lightAccent,
    tertiary: lightAccent,
    onTertiary: Colors.white,
    error: const Color(0xFFEF4444),
    onError: Colors.white,
    surface: lightSurface,
    onSurface: lightTextPrimary,
    surfaceContainerHighest: lightBg,
    onSurfaceVariant: lightTextSecondary,
    outline: lightBorder,
    shadow: Colors.black,
  );

  static final ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkAccent,
    onPrimary: Colors.black,
    primaryContainer: darkAccent.withValues(alpha: 0.20),
    onPrimaryContainer: darkAccent,
    secondary: darkAccent,
    onSecondary: Colors.black,
    secondaryContainer: darkAccent.withValues(alpha: 0.20),
    onSecondaryContainer: darkAccent,
    tertiary: darkAccent,
    onTertiary: Colors.black,
    error: const Color(0xFFF87171),
    onError: Colors.black,
    surface: darkSurface,
    onSurface: darkTextPrimary,
    surfaceContainerHighest: darkBg,
    onSurfaceVariant: darkTextSecondary,
    outline: Colors.transparent,
    shadow: Colors.black,
  );

  static ThemeData get light => _build(lightScheme);
  static ThemeData get dark => _build(darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.brightness == Brightness.dark ? darkBg : lightBg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(
          scheme.brightness == Brightness.dark ? Colors.black : Colors.white,
        ),
        side: BorderSide(color: scheme.outline, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

/// Gradiente vertical del fondo — idéntico al de la app original.
LinearGradient slayBackgroundGradient(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? const [SlayTheme.darkBg, SlayTheme.darkSurface]
        : const [SlayTheme.lightBg, SlayTheme.lightSurface],
  );
}
