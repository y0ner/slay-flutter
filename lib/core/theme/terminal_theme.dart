import 'package:flutter/material.dart';

/// Tema de Slay — estilo "terminal cálida" inspirado en tuweb.dev.
///
/// Identidad:
/// - Tipografía monoespaciada (Geist Mono) en TODO el cuerpo.
/// - Pixel font (Geist Pixel) solo para titulares y números destacados.
/// - Día: papel cálido #FDF6EF con tinta marrón; Noche: marrón muy oscuro
///   #17110D con tinta clara. Nada de blanco ni negro puro: todo lleva la
///   misma gota de tierra.
/// - Acento naranja quemado (#C2410C de día, #FC784B de noche).
/// - Bordes de 1px, esquinas cuadradas, cero sombras: la jerarquía es
///   puramente lineal y tipográfica.
class TerminalTheme {
  // ── Modo día: papel cálido + naranja quemado ─────────────
  static const Color dayBg = Color(0xFFFDF6EF);
  static const Color dayFg = Color(0xFF3B2D24);
  static const Color dayMuted = Color(0xFF7A6152);
  static const Color dayLine = Color(0xFFE8D9C8);
  static const Color dayPanel = Color(0xFFF7ECE1);
  static const Color dayAccent = Color(0xFFC2410C);
  static const Color dayHeart = Color(0xFFB91C3C);
  static const Color dayOk = Color(0xFF2F7A3B);
  static const Color dayBuilding = Color(0xFF8A5A00);

  // ── Modo noche: terminal templada (no gris azulado) ──────
  static const Color nightBg = Color(0xFF17110D);
  static const Color nightFg = Color(0xFFF3E7DB);
  static const Color nightMuted = Color(0xFFAD9483);
  static const Color nightLine = Color(0xFF382B21);
  static const Color nightPanel = Color(0xFF1F1813);
  static const Color nightAccent = Color(0xFFFC784B);
  static const Color nightHeart = Color(0xFFF2758C);
  static const Color nightOk = Color(0xFF6FBF7D);
  static const Color nightBuilding = Color(0xFFD9A441);

  // ── Familias tipográficas (registradas en pubspec.yaml) ──
  static const String monoFamily = 'GeistMono';
  static const String pixelFamily = 'GeistPixel';

  // ── ColorSchemes ─────────────────────────────────────────
  static final ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: dayAccent,
    onPrimary: dayBg,
    primaryContainer: dayPanel,
    onPrimaryContainer: dayAccent,
    secondary: dayAccent,
    onSecondary: dayBg,
    secondaryContainer: dayPanel,
    onSecondaryContainer: dayAccent,
    tertiary: dayOk,
    onTertiary: dayBg,
    error: dayHeart,
    onError: dayBg,
    surface: dayPanel,
    onSurface: dayFg,
    surfaceContainerHighest: dayPanel,
    onSurfaceVariant: dayMuted,
    outline: dayLine,
    outlineVariant: dayLine,
    shadow: Colors.transparent,
  );

  static final ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: nightAccent,
    onPrimary: nightBg,
    primaryContainer: nightPanel,
    onPrimaryContainer: nightAccent,
    secondary: nightAccent,
    onSecondary: nightBg,
    secondaryContainer: nightPanel,
    onSecondaryContainer: nightAccent,
    tertiary: nightOk,
    onTertiary: nightBg,
    error: nightHeart,
    onError: nightBg,
    surface: nightPanel,
    onSurface: nightFg,
    surfaceContainerHighest: nightPanel,
    onSurfaceVariant: nightMuted,
    outline: nightLine,
    outlineVariant: nightLine,
    shadow: Colors.transparent,
  );

  static ThemeData get light => _build(lightScheme);
  static ThemeData get dark => _build(darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final fg = isDark ? nightFg : dayFg;
    final muted = isDark ? nightMuted : dayMuted;
    final line = isDark ? nightLine : dayLine;
    final panel = isDark ? nightPanel : dayPanel;
    final accent = isDark ? nightAccent : dayAccent;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? nightBg : dayBg,

      // ── Tipografía base: monoespaciada en todo ───────────
      textTheme: _buildTextTheme(isDark, fg, muted, accent),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: fg,
        titleTextStyle: TextStyle(
          fontFamily: pixelFamily,
          fontSize: 20,
          color: fg,
          fontWeight: FontWeight.w400,
        ),
        iconTheme: IconThemeData(color: fg),
      ),

      // Cero elevación en todo: bordes, no sombras.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: panel,
        foregroundColor: accent,
        elevation: 0,
        highlightElevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: accent, width: 1.2),
        ),
      ),

      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: line, width: 1),
        ),
      ),

      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),

      // ── Inputs: cuadrados, borde 1px, monoespaciados ─────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? nightBg : dayBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.25),
        selectionHandleColor: accent,
      ),

      // ── Botón primario: sólido naranja, cuadrado ─────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? nightBg : dayBg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: monoFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── Botón secundario: outline, cuadrado ──────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: line, width: 1),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: monoFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontFamily: monoFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: muted),
      ),

      // ── Checkbox: cuadrado de la casa ────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(isDark ? nightBg : dayBg),
        side: BorderSide(color: muted, width: 1.4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? nightBg : dayBg)
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : (isDark ? nightLine : dayLine),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: panel,
        side: BorderSide(color: line),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: TextStyle(color: fg, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? nightFg : dayFg,
        contentTextStyle: TextStyle(
          fontFamily: monoFamily,
          color: isDark ? nightBg : dayBg,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: line, width: 1),
        ),
        titleTextStyle: TextStyle(
          fontFamily: pixelFamily,
          fontSize: 18,
          color: fg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: monoFamily,
          fontSize: 14,
          color: fg,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: nightPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.zero),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: monoFamily,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? accent : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? accent : muted,
          );
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: line,
        circularTrackColor: line,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(4),
        thumbColor: WidgetStateProperty.all(accent.withValues(alpha: 0.4)),
        radius: Radius.zero,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontFamily: monoFamily,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: monoFamily,
          fontSize: 12.5,
          color: muted,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          fontFamily: monoFamily,
          fontSize: 12,
          color: isDark ? nightBg : dayBg,
        ),
        decoration: BoxDecoration(color: fg),
      ),
    );
  }

  /// Escala tipográfica de la casa: todo monoespaciada, los titulares en
  /// pixel font. Interlineado abierto porque la mono es densa.
  static TextTheme _buildTextTheme(
    bool isDark,
    Color fg,
    Color muted,
    Color accent,
  ) {
    final mono = TextStyle(fontFamily: monoFamily, color: fg);
    return TextTheme(
      // Titulares grandes: Geist Pixel.
      displaySmall: TextStyle(
        fontFamily: pixelFamily,
        fontSize: 30,
        height: 1.15,
        color: fg,
        fontWeight: FontWeight.w400,
      ),
      headlineMedium: TextStyle(
        fontFamily: pixelFamily,
        fontSize: 26,
        height: 1.15,
        color: fg,
        fontWeight: FontWeight.w400,
      ),
      headlineSmall: TextStyle(
        fontFamily: pixelFamily,
        fontSize: 22,
        height: 1.15,
        color: fg,
        fontWeight: FontWeight.w400,
      ),
      titleLarge: mono.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      titleMedium: mono.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: mono.copyWith(fontSize: 16, height: 1.65),
      bodyMedium: mono.copyWith(fontSize: 14, height: 1.6),
      bodySmall: mono.copyWith(fontSize: 12.5, height: 1.5, color: muted),
      labelLarge: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: mono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      labelSmall: mono.copyWith(fontSize: 11, color: muted),
    );
  }

  /// Color de acento según el modo (para widgets que lo necesitan suelto).
  static Color accentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightAccent : dayAccent;

  /// Color de línea según el modo.
  static Color lineOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightLine : dayLine;

  /// Color de panel según el modo.
  static Color panelOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightPanel : dayPanel;

  /// Color muted según el modo.
  static Color mutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightMuted : dayMuted;

  /// Color de texto principal según el modo.
  static Color fgOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightFg : dayFg;

  /// Color de éxito (verde) según el modo.
  static Color okOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightOk : dayOk;

  /// Color ámbar de "construyendo" según el modo.
  static Color buildingOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightBuilding : dayBuilding;

  /// Color de fondo según el modo.
  static Color bgOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightBg : dayBg;
}
