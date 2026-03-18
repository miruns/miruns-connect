import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../../../../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import 'nav_menu_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppHeader — shared top-bar for all main screens
// ─────────────────────────────────────────────────────────────────────────────

/// Consistent top-bar widget used across all main screens.
///
/// Layout (left → right):
///   [title (+ optional subtitle)]  ‥  [primaryAction]  [theme-toggle]
///
/// • [title] — screen name in Playfair Display.
/// • [subtitle] — optional dim caption line (e.g. "12 of 34 analysed").
/// • [primaryAction] — optional inline widget before the theme icon
///   (e.g. a refresh button, a spinner, or a badge row).
class AppHeader extends ConsumerWidget {
  const AppHeader({
    required this.title,
    this.subtitle,
    this.primaryAction,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    final cs = Theme.of(context).colorScheme;
    final dimColor = dark ? AppTheme.fog : const Color(0xFF999999);
    final titleColor = cs.onSurface;
    final subColor = dark ? AppTheme.mist : const Color(0xFF999999);

    void toggleTheme() {
      final next = switch (themeMode) {
        ThemeMode.system => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.light,
        ThemeMode.light => ThemeMode.system,
      };
      ref.read(themeModeProvider.notifier).setThemeMode(next);
    }

    final themeLabel = switch (themeMode) {
      ThemeMode.dark => 'Dark mode',
      ThemeMode.light => 'Light mode',
      ThemeMode.system => 'System theme',
    };

    final themeIcon = switch (themeMode) {
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Title + subtitle ──────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTheme.geist(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTheme.geist(fontSize: 12, color: subColor),
                  ),
                ],
              ],
            ),
          ),

          // ── Inline primary action (e.g. refresh) ─────────────────────
          if (primaryAction != null) primaryAction!,

          // ── Theme toggle ──────────────────────────────────────────────
          IconButton(
            onPressed: toggleTheme,
            tooltip: themeLabel,
            icon: Icon(themeIcon, color: dimColor, size: 22),
          ),
          // ── Navigation menu ───────────────────────────────────────────
          const NavMenuButton(),
        ],
      ),
    );
  }
}
