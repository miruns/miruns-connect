import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/service_providers.dart';
import '../../../../../../../../../../../../core/theme/app_theme.dart';

// ─── NavMenuScope ─────────────────────────────────────────────────────────────

/// InheritedWidget that provides the "open menu" callback to descendant
/// widgets so they can embed a [NavMenuButton] in their own headers.
class NavMenuScope extends InheritedWidget {
  const NavMenuScope({
    required this.onOpenMenu,
    required super.child,
    super.key,
  });

  final VoidCallback onOpenMenu;

  static NavMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavMenuScope>();

  static NavMenuScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No NavMenuScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(NavMenuScope oldWidget) => false;
}

// ─── NavMenuButton ────────────────────────────────────────────────────────────

/// Hamburger menu button intended to be placed inside screen headers.
///
/// Reads the [NavMenuScope] from the tree to trigger the navigation sheet.
/// Shows a pulsating attention dot when health sensors need attention.
class NavMenuButton extends ConsumerWidget {
  const NavMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = NavMenuScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final available = ref.watch(healthAvailableProvider).valueOrNull;
    final granted = ref.watch(healthPermissionStatusProvider).valueOrNull;
    final needsAttention =
        available != null && granted != null && !(available && granted);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        scope.onOpenMenu();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.5)),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.menu_rounded, size: 18, color: AppTheme.fog),
            if (needsAttention)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.amber,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
