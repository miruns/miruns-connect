import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/service_providers.dart';
import '../../../../../../../../../../../core/theme/app_theme.dart';
import '../shared/widgets/nav_menu_button.dart';
import '../sport/widgets/active_workout_banner.dart';

/// Root scaffold that provides navigation menu access to child screens.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the active workout to show/hide the banner.
    final hasActiveWorkout = ref.watch(
      activeWorkoutProvider.select((n) => n.isActive),
    );

    return Scaffold(
      extendBody: true,
      body: NavMenuScope(
        onOpenMenu: () => _showNavSheet(context),
        child: Column(
          children: [
            // Persistent workout banner — visible on every tab
            if (hasActiveWorkout)
              SafeArea(bottom: false, child: const ActiveWorkoutBanner()),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }

  void _showNavSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) => _FullNavSheet(
        routerContext: context,
        currentIndex: navigationShell.currentIndex,
        onTabTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

// ─── Nav item metadata ────────────────────────────────────────────────────────

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.numeral,
    this.isMoreTab = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Roman numeral shown as a subtle chapter marker on active tab.
  final String numeral;

  /// When true the tab opens the overflow sheet instead of navigating.
  final bool isMoreTab;
}

const List<_NavItem> _navItems = [
  _NavItem(
    icon: Icons.directions_run_outlined,
    activeIcon: Icons.directions_run_rounded,
    label: 'Sport',
    numeral: 'I',
  ),
  _NavItem(
    icon: Icons.sensors_outlined,
    activeIcon: Icons.sensors_rounded,
    label: 'EEG',
    numeral: 'II',
  ),
  _NavItem(
    icon: Icons.insights_outlined,
    activeIcon: Icons.insights,
    label: 'Patterns',
    numeral: 'III',
  ),
  _NavItem(
    icon: Icons.edit_note_rounded,
    activeIcon: Icons.edit_note_rounded,
    label: 'Capture',
    numeral: 'IV',
  ),
  _NavItem(
    icon: Icons.grid_view_outlined,
    activeIcon: Icons.grid_view_rounded,
    label: 'More',
    numeral: '···',
    isMoreTab: true,
  ),
];

// ─── More-sheet destination model ─────────────────────────────────────────────

class _MoreDestination {
  const _MoreDestination({
    required this.icon,
    required this.label,
    required this.route,
    this.description,
  });
  final IconData icon;
  final String label;
  final String route;
  final String? description;
}

/// Destinations surfaced in the More overflow sheet.
/// Add new features here first; graduate them to [_navItems] when they earn
/// a permanent spot in the primary navigation.
const List<_MoreDestination> _moreDestinations = [
  _MoreDestination(
    icon: Icons.auto_stories_outlined,
    label: 'Journal',
    route: '/journal',
    description: 'Body blog, daily entries',
  ),
  _MoreDestination(
    icon: Icons.auto_awesome_rounded,
    label: 'AI Services',
    route: '/ai-settings',
    description: 'Choose your AI provider & API keys',
  ),
  _MoreDestination(
    icon: Icons.sensors_rounded,
    label: 'Sensors',
    route: '/sensors',
    description: 'Sensor status & data sources',
  ),
  _MoreDestination(
    icon: Icons.psychology_alt,
    label: 'Signal Sources',
    route: '/sources',
    description: 'BLE signal hardware (EEG, EMG)',
  ),
  _MoreDestination(
    icon: Icons.tune_rounded,
    label: 'Environment',
    route: '/environment',
    description: 'Environment & preferences',
  ),
  _MoreDestination(
    icon: Icons.bug_report_outlined,
    label: 'Debug',
    route: '/debug',
    description: 'Developer panel',
  ),
];

// ─── Full navigation sheet ────────────────────────────────────────────────────

class _FullNavSheet extends ConsumerStatefulWidget {
  const _FullNavSheet({
    required this.routerContext,
    required this.currentIndex,
    required this.onTabTap,
  });

  final BuildContext routerContext;
  final int currentIndex;
  final ValueChanged<int> onTabTap;

  @override
  ConsumerState<_FullNavSheet> createState() => _FullNavSheetState();
}

class _FullNavSheetState extends ConsumerState<_FullNavSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mainItems = _navItems.where((i) => !i.isMoreTab).toList();
    final q = _query.toLowerCase().trim();

    final filteredNav = q.isEmpty
        ? mainItems
        : mainItems.where((i) => i.label.toLowerCase().contains(q)).toList();

    final filteredMore = q.isEmpty
        ? _moreDestinations
        : _moreDestinations
              .where(
                (d) =>
                    d.label.toLowerCase().contains(q) ||
                    (d.description?.toLowerCase().contains(q) ?? false),
              )
              .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.deepSea,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(top: BorderSide(color: AppTheme.shimmer, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ────────────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.shimmer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Search field ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.moonbeam,
                  fontFamily: 'Inter',
                ),
                cursorColor: AppTheme.glow,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: AppTheme.fog.withValues(alpha: 0.55),
                    fontFamily: 'Inter',
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.search_rounded,
                      color: AppTheme.fog.withValues(alpha: 0.65),
                      size: 20,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.close_rounded,
                              color: AppTheme.fog.withValues(alpha: 0.65),
                              size: 18,
                            ),
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(),
                  filled: true,
                  fillColor: AppTheme.tidePool,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppTheme.shimmer, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppTheme.glow, width: 1.5),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),

            // ── Filtered results (searching) ───────────────────────────────
            if (q.isNotEmpty) ...[
              if (filteredNav.isEmpty && filteredMore.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  child: Text(
                    'No results for "$_query"',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.fog.withValues(alpha: 0.55),
                      fontFamily: 'Inter',
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ...List.generate(filteredNav.length, (i) {
                        final item = filteredNav[i];
                        final originalIndex = mainItems.indexOf(item);
                        return _buildNavRow(
                          context,
                          item,
                          originalIndex,
                          originalIndex == widget.currentIndex,
                        );
                      }),
                      ...filteredMore.map(
                        (dest) => _MoreTile(
                          destination: dest,
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.routerContext.push(dest.route);
                          },
                          badge: dest.route == '/sensors'
                              ? _buildSensorBadgeDot(ref)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              // ── Normal view (scrollable) ───────────────────────────────
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    // Tabs section label
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                      child: Row(
                        children: [
                          Text(
                            'NAVIGATE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.fog,
                              letterSpacing: 0.4,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Main tabs
                    ...List.generate(mainItems.length, (i) {
                      return _buildNavRow(
                        context,
                        mainItems[i],
                        i,
                        i == widget.currentIndex,
                      );
                    }),

                    // Divider
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Divider(
                        color: AppTheme.shimmer.withValues(alpha: 0.20),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // More section label
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Row(
                        children: [
                          Text(
                            'MORE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.fog,
                              letterSpacing: 0.4,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Sensor guidance
                    _SensorGuidanceBanner(ref: ref),

                    // More destinations
                    ..._moreDestinations.map(
                      (dest) => _MoreTile(
                        destination: dest,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.routerContext.push(dest.route);
                        },
                        badge: dest.route == '/sensors'
                            ? _buildSensorBadgeDot(ref)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavRow(
    BuildContext context,
    _NavItem item,
    int index,
    bool isActive,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onTabTap(index);
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.glow.withValues(alpha: 0.10)
                    : AppTheme.tidePool,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isActive
                      ? AppTheme.glow.withValues(alpha: 0.50)
                      : AppTheme.shimmer,
                  width: 1,
                ),
              ),
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                size: 17,
                color: isActive ? AppTheme.glow : AppTheme.fog,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? AppTheme.moonbeam : AppTheme.fog,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.glow.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.glow.withValues(alpha: 0.30),
                    width: 1,
                  ),
                ),
                child: Text(
                  item.numeral,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.glow,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppTheme.fog.withValues(alpha: 0.40),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.destination, required this.onTap, this.badge});

  final _MoreDestination destination;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.tidePool,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.shimmer, width: 1),
              ),
              child: Icon(destination.icon, size: 17, color: AppTheme.fog),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.moonbeam,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (destination.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      destination.description!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.fog,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badge != null) ...[badge!, const SizedBox(width: 8)],
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppTheme.fog.withValues(alpha: 0.50),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sensor attention badge & guidance widgets ───────────────────────────────────

/// Helper — builds a small pulsating dot for the Sensors tile in the More
/// sheet. Returns [SizedBox.shrink] when everything is healthy.
Widget _buildSensorBadgeDot(WidgetRef ref) {
  final available = ref.watch(healthAvailableProvider).valueOrNull;
  final granted = ref.watch(healthPermissionStatusProvider).valueOrNull;

  if (available == null || granted == null) return const SizedBox.shrink();
  if (available && granted) return const SizedBox.shrink();

  final color = !available ? AppTheme.fog : AppTheme.amber;

  return _PulseDot(color: color, size: 8, needsAttention: !granted);
}

/// Inline guidance banner shown at the top of the More sheet when sensors are
/// not fully healthy. Guides the user towards the Sensors screen.
class _SensorGuidanceBanner extends StatelessWidget {
  const _SensorGuidanceBanner({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(healthAvailableProvider).valueOrNull;
    final granted = ref.watch(healthPermissionStatusProvider).valueOrNull;

    // All good or still loading — no banner.
    if (available == null && granted == null) return const SizedBox.shrink();
    if (available == true && granted == true) return const SizedBox.shrink();

    final String message;
    final Color accent;
    final IconData icon;

    if (available == false) {
      message = 'Health platform unavailable on this device.';
      accent = AppTheme.fog;
      icon = Icons.cloud_off_rounded;
    } else if (granted == false) {
      message = 'Some sensors need attention \u2014 open Sensors to review.';
      accent = AppTheme.amber;
      icon = Icons.warning_amber_rounded;
    } else {
      message = 'Checking sensor status\u2026';
      accent = AppTheme.fog;
      icon = Icons.hourglass_empty_rounded;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withValues(alpha: 0.30), width: 1),
        ),
        child: Row(
          children: [
            _PulseDot(
              color: accent,
              size: 10,
              needsAttention: granted == false,
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsating dot indicator that draws attention when sensors are unhealthy.
class _PulseDot extends StatefulWidget {
  const _PulseDot({
    required this.color,
    this.size = 9,
    this.needsAttention = false,
  });
  final Color color;
  final double size;
  final bool needsAttention;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.needsAttention) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.needsAttention && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.needsAttention && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = widget.needsAttention ? 1.0 + _ctrl.value * 0.35 : 1.0;
        final opacity = widget.needsAttention ? 0.5 + _ctrl.value * 0.5 : 1.0;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.35),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
