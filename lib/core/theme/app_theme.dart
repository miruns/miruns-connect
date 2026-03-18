import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'miruns_colors.dart';

export 'miruns_colors.dart';

/// miruns Geist-aligned design system.
///
/// Follows Vercel's Geist design language: Inter typeface, neutral gray scale,
/// zero-elevation surfaces, 1px borders, 6–8 px radii, functional minimalism.
/// Dark theme is primary.
class AppTheme {
  AppTheme._();

  // ─── Geist Gray Scale (Dark) ──────────────────────────────────────────────

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

  /// Subtle elevated — hover states, tertiary surfaces.
  static const Color gray400 = Color(0xFF333333);

  /// Border — structural separator / outline.
  static const Color shimmer = Color(0xFF222222);

  // ─── Geist Accent Palette ─────────────────────────────────────────────────

  /// Primary accent — Geist Blue.
  static const Color glow = Color(0xFF0070F3);

  /// Dark-mode accent — cyan. Neural activity.
  static const Color cyan = Color(0xFF00E5FF);

  /// Secondary accent — Geist Violet.
  static const Color aurora = Color(0xFF7928CA);

  /// Tertiary — Geist Cyan highlight.
  static const Color starlight = Color(0xFF79FFE1);

  // ─── Geist Text ───────────────────────────────────────────────────────────

  /// Primary text — near white (Geist foreground).
  static const Color moonbeam = Color(0xFFEDEDED);

  /// Muted text — secondary content (Geist gray-700).
  static const Color fog = Color(0xFF888888);

  /// Subtle text — tertiary/placeholder (Geist gray-600).
  static const Color mist = Color(0xFF666666);

  // ─── Semantic ─────────────────────────────────────────────────────────────

  static const Color seaGreen = Color(0xFF50E3C2);
  static const Color amber = Color(0xFFF5A623);
  static const Color crimson = Color(0xFFEE0000);

  // ─── Light-mode Gray Scale ────────────────────────────────────────────────

  static const Color _lightBg = Color(0xFFFAFAFA);
  static const Color _lightSurface = Colors.white;
  static const Color _lightCard = Colors.white;
  static const Color _lightBorder = Color(0xFFEAEAEA);
  static const Color _lightBorderSubtle = Color(0xFFF0F0F0);
  static const Color _lightForeground = Color(0xFF171717);
  static const Color _lightSecondary = Color(0xFF666666);
  static const Color _lightTertiary = Color(0xFF999999);

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

  // ─── Geist Radius ─────────────────────────────────────────────────────────

  static const double radiusSm = 2;
  static const double radiusMd = 4;
  static const double radiusLg = 6;
  static const double radiusXl = 8;

  // ─── Geist Typography ─────────────────────────────────────────────────────

  static TextStyle geist({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
    double? height,
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing ?? _defaultLetterSpacing(fontSize),
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
    letterSpacing: letterSpacing ?? -0.2,
    color: color,
  );

  /// Geist uses tighter tracking at larger sizes.
  static double _defaultLetterSpacing(double fontSize) {
    if (fontSize >= 32) return -0.8;
    if (fontSize >= 24) return -0.5;
    if (fontSize >= 18) return -0.3;
    if (fontSize >= 14) return -0.15;
    return 0;
  }

  // ─── Text Theme ───────────────────────────────────────────────────────────

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      // Display — hero text
      displayLarge: geist(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: primary,
        height: 1.1,
      ),
      displayMedium: geist(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: primary,
        height: 1.15,
      ),
      displaySmall: geist(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.2,
      ),
      // Headline — section headers
      headlineLarge: geist(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.25,
      ),
      headlineMedium: geist(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.3,
      ),
      headlineSmall: geist(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.35,
      ),
      // Title — card/section titles
      titleLarge: geist(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.4,
      ),
      titleMedium: geist(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: primary,
        height: 1.45,
      ),
      titleSmall: geist(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: primary,
        height: 1.45,
      ),
      // Body — readable content
      bodyLarge: geist(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: primary,
        height: 1.6,
      ),
      bodyMedium: geist(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondary,
        height: 1.6,
      ),
      bodySmall: geist(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: secondary,
        height: 1.55,
      ),
      // Label — buttons, captions, metadata
      labelLarge: geist(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: primary,
        height: 1.4,
      ),
      labelMedium: geist(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
        height: 1.35,
      ),
      labelSmall: geist(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: secondary,
        height: 1.35,
      ),
    );
  }

  // ─── Shared component shape ───────────────────────────────────────────────

  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radiusMd),
  );

  // ─── Dark Theme ───────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    final textTheme = _textTheme(moonbeam, fog);

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
        surfaceContainerHigh: gray400,
        surfaceContainerLow: tidePool,
        surfaceContainer: tidePool,
        error: crimson,
        onError: moonbeam,
        outline: shimmer,
        outlineVariant: Color(0xFF171717),
      ),
      scaffoldBackgroundColor: midnight,
      textTheme: textTheme,

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        foregroundColor: moonbeam,
        titleTextStyle: geist(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: moonbeam,
        ),
        iconTheme: const IconThemeData(color: fog, size: 20),
        actionsIconTheme: const IconThemeData(color: fog, size: 20),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: shimmer, width: 1),
        ),
        color: tidePool,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),

      // ── Elevated Button (primary action) ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: moonbeam,
          foregroundColor: void_,
          disabledBackgroundColor: gray400,
          disabledForegroundColor: mist,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Outlined Button (secondary action) ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: moonbeam,
          side: const BorderSide(color: shimmer, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Text Button (tertiary action) ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fog,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 36),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Filled Button ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: glow,
          foregroundColor: const Color(0xFFF5F5F5),
          disabledBackgroundColor: gray400,
          disabledForegroundColor: mist,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Icon Button ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: fog,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tidePool,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: shimmer, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: shimmer, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: moonbeam, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: crimson, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: crimson, width: 1),
        ),
        hintStyle: geist(color: mist, fontSize: 14),
        labelStyle: geist(color: fog, fontSize: 14),
        errorStyle: geist(color: crimson, fontSize: 12),
        prefixIconColor: fog,
        suffixIconColor: fog,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),

      // ── Dividers ──
      dividerTheme: const DividerThemeData(
        color: shimmer,
        thickness: 1,
        space: 0,
      ),

      // ── Icons ──
      iconTheme: const IconThemeData(color: fog, size: 20),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: tidePool,
        side: const BorderSide(color: shimmer, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        labelStyle: geist(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: moonbeam,
        ),
        selectedColor: glow.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: current,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: shimmer, width: 1),
        ),
        titleTextStyle: geist(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: moonbeam,
        ),
        contentTextStyle: geist(fontSize: 14, color: fog),
      ),

      // ── Bottom sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: deepSea,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Slider ──
      sliderTheme: const SliderThemeData(
        activeTrackColor: moonbeam,
        thumbColor: moonbeam,
        inactiveTrackColor: shimmer,
        overlayColor: Color(0x22EDEDED),
        trackHeight: 2,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? void_ : fog,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? moonbeam : shimmer,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? moonbeam : shimmer,
        ),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? moonbeam : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(void_),
        side: const BorderSide(color: shimmer, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      // ── Radio ──
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? moonbeam : fog,
        ),
      ),

      // ── Progress indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: moonbeam,
        linearTrackColor: shimmer,
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: moonbeam,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: geist(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: void_,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: moonbeam,
        contentTextStyle: geist(color: void_, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        titleTextStyle: geist(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: moonbeam,
        ),
        subtitleTextStyle: geist(fontSize: 13, color: fog),
        leadingAndTrailingTextStyle: geist(fontSize: 13, color: fog),
        iconColor: fog,
      ),

      // ── PopupMenu ──
      popupMenuTheme: PopupMenuThemeData(
        color: current,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: shimmer, width: 1),
        ),
        textStyle: geist(fontSize: 14, color: moonbeam),
      ),

      // ── TabBar ──
      tabBarTheme: TabBarThemeData(
        labelColor: moonbeam,
        unselectedLabelColor: fog,
        indicatorColor: moonbeam,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        unselectedLabelStyle: geist(fontSize: 14, fontWeight: FontWeight.w400),
        dividerColor: shimmer,
        dividerHeight: 1,
      ),

      // ── NavigationBar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: midnight,
        elevation: 0,
        indicatorColor: glow.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: moonbeam,
            );
          }
          return geist(fontSize: 11, fontWeight: FontWeight.w400, color: fog);
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return const IconThemeData(color: moonbeam, size: 20);
          }
          return const IconThemeData(color: fog, size: 20);
        }),
      ),

      // ── BottomNavigationBar ──
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: midnight,
        selectedItemColor: moonbeam,
        unselectedItemColor: fog,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      // ── FloatingActionButton ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: moonbeam,
        foregroundColor: void_,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),

      // ── SearchBar ──
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(tidePool),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: shimmer, width: 1),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          geist(fontSize: 14, color: moonbeam),
        ),
        hintStyle: WidgetStateProperty.all(geist(fontSize: 14, color: mist)),
      ),

      // ── SegmentedButton ──
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? moonbeam
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? void_ : fog,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: shimmer, width: 1),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            geist(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),

      // ── Badge ──
      badgeTheme: const BadgeThemeData(
        backgroundColor: crimson,
        textColor: moonbeam,
      ),

      // ── Semantic Colors ──
      extensions: const <ThemeExtension>[MirunsColors.dark],
    );
  }

  // ─── Light Theme ──────────────────────────────────────────────────────────

  static ThemeData get lightTheme {
    final textTheme = _textTheme(_lightForeground, _lightSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: glow,
        onPrimary: Color(0xFFF5F5F5),
        primaryContainer: Color(0xFFD6E4FF),
        onPrimaryContainer: Color(0xFF001A3D),
        secondary: aurora,
        onSecondary: Color(0xFFF5F5F5),
        secondaryContainer: Color(0xFFF0E6FF),
        onSecondaryContainer: Color(0xFF2E004F),
        tertiary: Color(0xFF067A6F),
        onTertiary: Color(0xFFF5F5F5),
        surface: _lightSurface,
        onSurface: _lightForeground,
        surfaceContainerHighest: Color(0xFFF5F5F5),
        surfaceContainerHigh: Color(0xFFFAFAFA),
        surfaceContainerLow: _lightSurface,
        surfaceContainer: _lightSurface,
        error: Color(0xFFE5484D),
        onError: Color(0xFFF5F5F5),
        outline: _lightBorder,
        outlineVariant: _lightBorderSubtle,
      ),
      scaffoldBackgroundColor: _lightBg,
      textTheme: textTheme,

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        foregroundColor: _lightForeground,
        titleTextStyle: geist(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _lightForeground,
        ),
        iconTheme: const IconThemeData(color: _lightSecondary, size: 20),
        actionsIconTheme: const IconThemeData(color: _lightSecondary, size: 20),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: _lightBorder, width: 1),
        ),
        color: _lightCard,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _lightForeground,
          foregroundColor: _lightSurface,
          disabledBackgroundColor: const Color(0xFFEAEAEA),
          disabledForegroundColor: _lightTertiary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Outlined Button ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightForeground,
          side: const BorderSide(color: _lightBorder, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Text Button ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _lightSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 36),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Filled Button ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: glow,
          foregroundColor: const Color(0xFFF5F5F5),
          disabledBackgroundColor: const Color(0xFFEAEAEA),
          disabledForegroundColor: _lightTertiary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 40),
          shape: _buttonShape,
          textStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Icon Button ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _lightSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: _lightBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: _lightBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: _lightForeground, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1),
        ),
        hintStyle: geist(color: _lightTertiary, fontSize: 14),
        labelStyle: geist(color: _lightSecondary, fontSize: 14),
        errorStyle: geist(color: const Color(0xFFE5484D), fontSize: 12),
        prefixIconColor: _lightSecondary,
        suffixIconColor: _lightSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),

      // ── Dividers ──
      dividerTheme: const DividerThemeData(
        color: _lightBorder,
        thickness: 1,
        space: 0,
      ),

      // ── Icons ──
      iconTheme: const IconThemeData(color: _lightSecondary, size: 20),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurface,
        side: const BorderSide(color: _lightBorder, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        labelStyle: geist(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _lightForeground,
        ),
        selectedColor: glow.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: _lightBorder, width: 1),
        ),
        titleTextStyle: geist(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _lightForeground,
        ),
        contentTextStyle: geist(fontSize: 14, color: _lightSecondary),
      ),

      // ── Bottom sheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Slider ──
      sliderTheme: const SliderThemeData(
        activeTrackColor: _lightForeground,
        thumbColor: _lightForeground,
        inactiveTrackColor: _lightBorder,
        overlayColor: Color(0x11171717),
        trackHeight: 2,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? _lightSurface : _lightTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _lightForeground
              : _lightBorder,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _lightForeground
              : _lightBorder,
        ),
      ),

      // ── Checkbox ──
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _lightForeground
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(_lightSurface),
        side: const BorderSide(color: _lightBorder, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      // ── Radio ──
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _lightForeground
              : _lightTertiary,
        ),
      ),

      // ── Progress indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lightForeground,
        linearTrackColor: _lightBorder,
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _lightForeground,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: geist(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _lightSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // ── Snackbar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightForeground,
        contentTextStyle: geist(color: _lightSurface, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        titleTextStyle: geist(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _lightForeground,
        ),
        subtitleTextStyle: geist(fontSize: 13, color: _lightSecondary),
        leadingAndTrailingTextStyle: geist(
          fontSize: 13,
          color: _lightSecondary,
        ),
        iconColor: _lightSecondary,
      ),

      // ── PopupMenu ──
      popupMenuTheme: PopupMenuThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: _lightBorder, width: 1),
        ),
        textStyle: geist(fontSize: 14, color: _lightForeground),
      ),

      // ── TabBar ──
      tabBarTheme: TabBarThemeData(
        labelColor: _lightForeground,
        unselectedLabelColor: _lightTertiary,
        indicatorColor: _lightForeground,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: geist(fontSize: 14, fontWeight: FontWeight.w500),
        unselectedLabelStyle: geist(fontSize: 14, fontWeight: FontWeight.w400),
        dividerColor: _lightBorder,
        dividerHeight: 1,
      ),

      // ── NavigationBar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        elevation: 0,
        indicatorColor: glow.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _lightForeground,
            );
          }
          return geist(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _lightTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return const IconThemeData(color: _lightForeground, size: 20);
          }
          return const IconThemeData(color: _lightTertiary, size: 20);
        }),
      ),

      // ── BottomNavigationBar ──
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _lightSurface,
        selectedItemColor: _lightForeground,
        unselectedItemColor: _lightTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      // ── FloatingActionButton ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _lightForeground,
        foregroundColor: _lightSurface,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),

      // ── SearchBar ──
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(_lightSurface),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: _lightBorder, width: 1),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          geist(fontSize: 14, color: _lightForeground),
        ),
        hintStyle: WidgetStateProperty.all(
          geist(fontSize: 14, color: _lightTertiary),
        ),
      ),

      // ── SegmentedButton ──
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? _lightForeground
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? _lightSurface
                : _lightSecondary,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: _lightBorder, width: 1),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            geist(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),

      // ── Badge ──
      badgeTheme: const BadgeThemeData(
        backgroundColor: Color(0xFFE5484D),
        textColor: _lightSurface,
      ),

      // ── Semantic Colors ──
      extensions: const <ThemeExtension>[MirunsColors.light],
    );
  }
}
