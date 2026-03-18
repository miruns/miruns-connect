import 'package:flutter/material.dart';

/// Semantic color tokens that adapt to light / dark theme.
///
/// Replaces scattered `dark ? Colors.whiteXX : Colors.blackXX` ternaries
/// with a single, centralized, lerpable set of tokens.
///
/// Access via `context.miruns` extension:
/// ```dart
/// final c = context.miruns;
/// Text('Title', style: TextStyle(color: c.textStrong));
/// ```
@immutable
class MirunsColors extends ThemeExtension<MirunsColors> {
  const MirunsColors({
    required this.textStrong,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.textSubtle,
    required this.textFaint,
    required this.divider,
    required this.border,
    required this.borderSubtle,
    required this.tintFaint,
    required this.tintSubtle,
    required this.tintMedium,
    required this.tintStrong,
    required this.contrast,
    required this.contrastReverse,
  });

  /// Titles, headings — strongest foreground.
  final Color textStrong;

  /// Body text — primary readable content.
  final Color textBody;

  /// Labels, supporting text — secondary importance.
  final Color textSecondary;

  /// Captions, metadata — de-emphasized.
  final Color textMuted;

  /// Hints, disabled text, icons — subtle.
  final Color textSubtle;

  /// Barely visible — tertiary info.
  final Color textFaint;

  /// Thin content dividers.
  final Color divider;

  /// Structural borders — card / section edges.
  final Color border;

  /// Near-invisible borders.
  final Color borderSubtle;

  /// 6 % tint — faint background wash.
  final Color tintFaint;

  /// 10 % tint — subtle background.
  final Color tintSubtle;

  /// 15 % tint — overlay / glass effect.
  final Color tintMedium;

  /// 30 % tint — stronger overlay.
  final Color tintStrong;

  /// Full contrast (white in dark, black in light).
  /// Use with `.withValues(alpha:)` for custom opacity.
  final Color contrast;

  /// Reverse contrast (black in dark, white in light).
  final Color contrastReverse;

  // ─── Instances ────────────────────────────────────────────────────────────

  static const dark = MirunsColors(
    textStrong: Color(0xFFEDEDED), // Geist foreground
    textBody: Color(0xFFA1A1A1), // Geist gray-900
    textSecondary: Color(0xFF888888), // Geist gray-700
    textMuted: Color(0xFF666666), // Geist gray-600
    textSubtle: Color(0xFF555555), // Geist gray-500
    textFaint: Color(0xFF444444), // Geist gray-400
    divider: Color(0xFF1F1F1F), // Geist gray-150
    border: Color(0xFF2E2E2E), // Geist gray-250
    borderSubtle: Color(0xFF222222), // Geist gray-200
    tintFaint: Color(0x0FFFFFFF), //   6 %
    tintSubtle: Color(0x1AFFFFFF), //  10 %
    tintMedium: Color(0x26FFFFFF), //  15 %
    tintStrong: Color(0x4DFFFFFF), //  30 %
    contrast: Colors.white,
    contrastReverse: Colors.black,
  );

  static const light = MirunsColors(
    textStrong: Color(0xFF171717), // Geist foreground
    textBody: Color(0xFF3B3B3B), // Geist gray-900
    textSecondary: Color(0xFF666666), // Geist gray-700
    textMuted: Color(0xFF8F8F8F), // Geist gray-600
    textSubtle: Color(0xFFA1A1A1), // Geist gray-500
    textFaint: Color(0xFFCFCFCF), // Geist gray-400
    divider: Color(0xFFEEEEEE), // Geist gray-200
    border: Color(0xFFE5E5E5), // Geist gray-300
    borderSubtle: Color(0xFFEEEEEE), // Geist gray-200
    tintFaint: Color(0x0F000000), //  6 %
    tintSubtle: Color(0x14000000), //  8 %
    tintMedium: Color(0x26000000), // 15 %
    tintStrong: Color(0x4D000000), // 30 %
    contrast: Colors.black,
    contrastReverse: Colors.white,
  );

  // ─── ThemeExtension plumbing ──────────────────────────────────────────────

  @override
  MirunsColors copyWith({
    Color? textStrong,
    Color? textBody,
    Color? textSecondary,
    Color? textMuted,
    Color? textSubtle,
    Color? textFaint,
    Color? divider,
    Color? border,
    Color? borderSubtle,
    Color? tintFaint,
    Color? tintSubtle,
    Color? tintMedium,
    Color? tintStrong,
    Color? contrast,
    Color? contrastReverse,
  }) => MirunsColors(
    textStrong: textStrong ?? this.textStrong,
    textBody: textBody ?? this.textBody,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textSubtle: textSubtle ?? this.textSubtle,
    textFaint: textFaint ?? this.textFaint,
    divider: divider ?? this.divider,
    border: border ?? this.border,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    tintFaint: tintFaint ?? this.tintFaint,
    tintSubtle: tintSubtle ?? this.tintSubtle,
    tintMedium: tintMedium ?? this.tintMedium,
    tintStrong: tintStrong ?? this.tintStrong,
    contrast: contrast ?? this.contrast,
    contrastReverse: contrastReverse ?? this.contrastReverse,
  );

  @override
  MirunsColors lerp(MirunsColors? other, double t) {
    if (other is! MirunsColors) return this;
    return MirunsColors(
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      tintFaint: Color.lerp(tintFaint, other.tintFaint, t)!,
      tintSubtle: Color.lerp(tintSubtle, other.tintSubtle, t)!,
      tintMedium: Color.lerp(tintMedium, other.tintMedium, t)!,
      tintStrong: Color.lerp(tintStrong, other.tintStrong, t)!,
      contrast: Color.lerp(contrast, other.contrast, t)!,
      contrastReverse: Color.lerp(contrastReverse, other.contrastReverse, t)!,
    );
  }
}

/// Quick access: `context.miruns.textStrong`, `context.miruns.divider`, etc.
extension MirunsColorsExtension on BuildContext {
  MirunsColors get miruns => Theme.of(this).extension<MirunsColors>()!;
}
