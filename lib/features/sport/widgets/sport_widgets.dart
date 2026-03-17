import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';

/// Circular HR zone indicator with animated fill and glow effect.
class HrZoneRing extends StatelessWidget {
  final int currentHr;
  final HrZone zone;
  final int maxHr;
  final double size;

  const HrZoneRing({
    super.key,
    required this.currentHr,
    required this.zone,
    required this.maxHr,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentHr / maxHr).clamp(0.0, 1.0);
    final zoneColor = Color(int.parse(zone.color));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: progress,
              color: zoneColor,
              bgColor: zoneColor.withValues(alpha: 0.15),
              strokeWidth: size * 0.08,
            ),
          ),
          // Center text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$currentHr',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w700,
                  color: zoneColor,
                  height: 1.0,
                ),
              ),
              Text(
                'bpm',
                style: TextStyle(fontSize: size * 0.10, color: AppTheme.fog),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: zoneColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Z${zone.zone} ${zone.name}',
                  style: TextStyle(
                    fontSize: size * 0.09,
                    fontWeight: FontWeight.w600,
                    color: zoneColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background arc
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = bgColor,
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Compact metric tile showing a value with label.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? accentColor;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.glow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppTheme.fog),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.fog,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Brain state indicator showing EEG metrics as compact bars.
class BrainStateIndicator extends StatelessWidget {
  final double attention;
  final double relaxation;
  final double mentalFatigue;
  final double cognitiveLoad;

  const BrainStateIndicator({
    super.key,
    required this.attention,
    required this.relaxation,
    required this.mentalFatigue,
    required this.cognitiveLoad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology, size: 16, color: AppTheme.aurora),
              SizedBox(width: 6),
              Text(
                'Brain State',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.aurora,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BarRow(label: 'Focus', value: attention, color: AppTheme.glow),
          const SizedBox(height: 6),
          _BarRow(label: 'Calm', value: relaxation, color: AppTheme.seaGreen),
          const SizedBox(height: 6),
          _BarRow(
            label: 'Fatigue',
            value: mentalFatigue,
            color: AppTheme.amber,
          ),
          const SizedBox(height: 6),
          _BarRow(label: 'Load', value: cognitiveLoad, color: AppTheme.crimson),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.fog),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Live insight card shown during workout.
class InsightCard extends StatelessWidget {
  final String message;
  final String label;
  final Color? accentColor;

  const InsightCard({
    super.key,
    required this.message,
    required this.label,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.current,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (accentColor ?? AppTheme.glow).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (accentColor ?? AppTheme.cyan).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accentColor ?? AppTheme.cyan,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.moonbeam,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Workout type selector with icon-first cards.
class WorkoutTypeSelector extends StatelessWidget {
  final WorkoutType? selected;
  final ValueChanged<WorkoutType> onSelect;

  const WorkoutTypeSelector({super.key, this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: WorkoutType.values.map((type) {
        final isSelected = type == selected;
        return GestureDetector(
          onTap: () => onSelect(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.cyan.withValues(alpha: 0.10)
                  : AppTheme.tidePool,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppTheme.cyan
                    : AppTheme.shimmer.withValues(alpha: 0.3),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type.icon,
                  size: 26,
                  color: isSelected ? AppTheme.cyan : AppTheme.fog,
                ),
                const SizedBox(height: 4),
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppTheme.cyan : AppTheme.fog,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Slider with emoji feedback for post-workout rating.
class FeedbackSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String lowLabel;
  final String highLabel;
  final Color color;

  const FeedbackSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.lowLabel = '1',
    this.highLabel = '10',
    this.color = AppTheme.glow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$value / 10',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              lowLabel,
              style: const TextStyle(fontSize: 11, color: AppTheme.fog),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: color,
                  inactiveTrackColor: color.withValues(alpha: 0.15),
                  thumbColor: color,
                  overlayColor: color.withValues(alpha: 0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: value.toDouble(),
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
            ),
            Text(
              highLabel,
              style: const TextStyle(fontSize: 11, color: AppTheme.fog),
            ),
          ],
        ),
      ],
    );
  }
}
