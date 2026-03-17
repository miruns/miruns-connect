import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// miruns brand theme — neuroscience meets sport.
/// Dark theme is primary. Inter typeface, cyan accent, clean surfaces.
class AppTheme {
  // ─── The Palette ──────────────────────────────────────────────────────────

  /// True black — deepest background.
  static const Color void_ = Color(0xFF000000);

  /// Primary scaffold background.
  static const Color midnight = Color(0xFF0A0A0A);

  /// Surface — elevated container.
  static const Color deepSea = Color(0xFF0D0D0D);

  /// Card — primary card surface.
  static const Color tidePool = Color(0xFF111111);

  /// Elevated — dialogs, sheets, modals.
  static const Color current = Color(0xFF1A1A1A);

  /// Border — structural separator / outline.
  static const Color shimmer = Color(0xFF222222);

  /// Primary accent — light-mode blue.
  static const Color glow = Color(0xFF0070F3);

  /// Dark-mode accent — cyan. Neural activity.
  static const Color cyan = Color(0xFF00E5FF);

  /// Secondary accent — violet.
  static const Color aurora = Color(0xFF7928CA);

  /// Tertiary — soft cyan highlight.
  static const Color starlight = Color(0xFF79FFE1);

  /// Primary text — near white.
  static const Color moonbeam = Color(0xFFEDEDED);

  /// Muted text — secondary content.
  static const Color fog = Color(0xFF888888);

  // Semantic
  static const Color seaGreen = Color(0xFF00B37E);
  static const Color amber = Color(0xFFF59E0B);
  static const Color crimson = Color(0xFFFF4444);

  // ─── Aliases (backward-compat for existing widgets) ───────────────────────
  static const Color primaryColor = glow;
  static const Color secondaryColor = aurora;
  static const Color accentColor = starlight;
  static const Color backgroundColor = midnight;
  static const Color surfaceColor = deepSea;
  static const Color cardColor = tidePool;
  static const Color successColor = seaGreen;
  static const Color warningColor = amber;
  static const Color errorColor = crimson;

  // ─── Geist helper ─────────────────────────────────────────────────────────
  static TextStyle geist({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
    double? height,
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );

  static TextStyle geistMono({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
  );

  // ─── Typography ───────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: geist(
        fontSize: 60,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.0,
        color: moonbeam,
      ),
      displayMedium: geist(
        fontSize: 45,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
        color: moonbeam,
      ),
      displaySmall: geist(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: moonbeam,
      ),
      headlineLarge: geist(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: moonbeam,
      ),
      headlineMedium: geist(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: moonbeam,
      ),
      headlineSmall: geist(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: moonbeam,
      ),
      titleLarge: geist(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: moonbeam,
      ),
      titleMedium: geist(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: moonbeam,
      ),
      titleSmall: geist(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: moonbeam,
      ),
      bodyLarge: geist(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: moonbeam,
      ),
      bodyMedium: geist(fontSize: 14, fontWeight: FontWeight.w400, color: fog),
      bodySmall: geist(fontSize: 12, fontWeight: FontWeight.w400, color: fog),
      labelLarge: geist(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: moonbeam,
      ),
      labelMedium: geist(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: fog,
      ),
      labelSmall: geist(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        color: fog,
      ),
    );
  }

  // ─── Dark Theme — Pure Black ───────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: glow,
        onPrimary: Color(0xFFF5F5F5),
        primaryContainer: Color(0xFF001A3D),
        onPrimaryContainer: glow,
        secondary: aurora,
        onSecondary: Color(0xFFF5F5F5),
        secondaryContainer: Color(0xFF1A0A30),
        onSecondaryContainer: aurora,
        tertiary: starlight,
        onTertiary: void_,
        surface: deepSea,
        onSurface: moonbeam,
        surfaceContainerHighest: current,
        surfaceContainerLow: tidePool,
        error: crimson,
        onError: moonbeam,
        outline: shimmer,
        outlineVariant: Color(0xFF171717),
      ),
      scaffoldBackgroundColor: midnight,
      textTheme: _buildTextTheme(),
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        foregroundColor: moonbeam,
        titleTextStyle: geist(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: moonbeam,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: fog, size: 22),
        actionsIconTheme: const IconThemeData(color: fog, size: 22),
      ),
      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: shimmer, width: 1),
        ),
        color: tidePool,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      // ── Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: glow,
          foregroundColor: const Color(0xFFF5F5F5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: geist(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: moonbeam,
          side: const BorderSide(color: shimmer, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: geist(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: glow,
          textStyle: geist(fontSize: 15, fontWeight: FontWeight.w500),
          shape: const StadiumBorder(),
        ),
      ),
      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tidePool,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: shimmer, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: shimmer, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: glow, width: 1.5),
        ),
        hintStyle: geist(color: fog, fontSize: 14),
        labelStyle: geist(color: fog, fontSize: 14),
        prefixIconColor: fog,
        suffixIconColor: fog,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
      ),
      // ── Dividers ──
      dividerTheme: const DividerThemeData(
        color: shimmer,
        thickness: 0.5,
        space: 0,
      ),
      // ── Icons ──
      iconTheme: const IconThemeData(color: fog, size: 22),
      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: tidePool,
        side: const BorderSide(color: shimmer, width: 1),
        shape: const StadiumBorder(),
        labelStyle: geist(fontSize: 13, color: moonbeam),
        selectedColor: glow.withValues(alpha: 0.15),
      ),
      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: current,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: geist(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: moonbeam,
          letterSpacing: -0.2,
        ),
      ),
      // ── Bottom sheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: current,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      // ── Slider ──
      sliderTheme: const SliderThemeData(
        activeTrackColor: glow,
        thumbColor: moonbeam,
        inactiveTrackColor: shimmer,
        overlayColor: Color(0x220070F3),
      ),
      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? moonbeam : fog,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? glow : shimmer,
        ),
      ),
      // ── Progress indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: glow,
        linearTrackColor: shimmer,
      ),
      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: current,
        contentTextStyle: geist(color: moonbeam, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Light Theme ──────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = _buildTextTheme().apply(
      bodyColor: const Color(0xFF111111),
      displayColor: const Color(0xFF111111),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF0070F3),
        secondary: const Color(0xFF7928CA),
        surface: Colors.white,
        error: errorColor,
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      textTheme: base,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF111111),
        titleTextStyle: geist(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF111111),
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE5E5E5), width: 1),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: geist(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
