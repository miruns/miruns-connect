import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:miruns_flutter/core/theme/app_theme.dart';

void main() {
  setUpAll(() {
    // Prevent GoogleFonts from making network requests during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AppTheme', () {
    // ── Color constants ──

    // ── Geist-inspired palette ──
    test('primary and accent colors are defined', () {
      // Primary = glow blue
      expect(AppTheme.primaryColor, const Color(0xFF0070F3));
      // Accent = starlight cyan
      expect(AppTheme.accentColor, const Color(0xFF79FFE1));
      expect(AppTheme.successColor, const Color(0xFF00B37E));
      expect(AppTheme.warningColor, const Color(0xFFF59E0B));
      expect(AppTheme.errorColor, const Color(0xFFFF4444));
    });

    test('background and surface colors are defined', () {
      expect(AppTheme.backgroundColor, const Color(0xFF0A0A0A));
      expect(AppTheme.surfaceColor, const Color(0xFF0D0D0D));
      expect(AppTheme.cardColor, const Color(0xFF111111));
    });

    test('secondary color is defined', () {
      // Secondary = aurora violet
      expect(AppTheme.secondaryColor, const Color(0xFF7928CA));
    });
  });
}
