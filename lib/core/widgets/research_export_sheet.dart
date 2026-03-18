import 'package:flutter/material.dart';

import '../../core/models/capture_entry.dart';
import '../../core/services/research_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/sport/models/workout_session.dart';

/// Shows a bottom sheet letting the user pick an export format and data streams,
/// then exports and shares via the native share sheet.
///
/// Works with both [CaptureEntry] and [WorkoutSession] data.
class ResearchExportSheet extends StatefulWidget {
  final CaptureEntry? capture;
  final WorkoutSession? workout;

  const ResearchExportSheet._({this.capture, this.workout});

  /// Show the export sheet for a capture.
  static Future<void> showForCapture(
    BuildContext context,
    CaptureEntry capture,
  ) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResearchExportSheet._(capture: capture),
  );

  /// Show the export sheet for a workout.
  static Future<void> showForWorkout(
    BuildContext context,
    WorkoutSession workout,
  ) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResearchExportSheet._(workout: workout),
  );

  @override
  State<ResearchExportSheet> createState() => _ResearchExportSheetState();
}

class _ResearchExportSheetState extends State<ResearchExportSheet> {
  final _exportService = ResearchExportService();

  ExportFormat _format = ExportFormat.csv;
  bool _includeEeg = true;
  bool _includeHr = true;
  bool _includeGps = true;
  bool _includeEnvironment = true;
  bool _includeMetadata = true;
  bool _isExporting = false;

  bool get _isCapture => widget.capture != null;
  bool get _hasEeg => _isCapture
      ? widget.capture!.signalSession != null
      : widget.workout!.eegSamples.isNotEmpty;
  bool get _hasHr => _isCapture
      ? widget.capture!.bleHrSession != null
      : widget.workout!.hrSamples.isNotEmpty;
  bool get _hasGps => !_isCapture && widget.workout!.gpsSamples.isNotEmpty;
  bool get _hasEnvironment =>
      _isCapture && widget.capture!.environmentData != null;

  Future<void> _export() async {
    setState(() => _isExporting = true);

    try {
      final options = ExportOptions(
        includeEeg: _includeEeg,
        includeHr: _includeHr,
        includeGps: _includeGps,
        includeEnvironment: _includeEnvironment,
        includeMetadata: _includeMetadata,
      );

      final ExportResult result;
      if (_isCapture) {
        result = await _exportService.exportCapture(
          widget.capture!,
          format: _format,
          options: options,
        );
      } else {
        result = await _exportService.exportWorkout(
          widget.workout!,
          format: _format,
          options: options,
        );
      }

      if (result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.summary),
              backgroundColor: AppTheme.crimson,
            ),
          );
        }
        return;
      }

      await _exportService.shareFiles(result);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.summary),
            backgroundColor: AppTheme.seaGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.crimson,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppTheme.current : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.contrast.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              Icon(Icons.science_rounded, size: 22, color: AppTheme.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Research Export',
                  style: AppTheme.geist(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: c.textStrong,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: c.textSubtle),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Export data in research-grade formats for ML pipelines, '
            'MNE-Python, EEGLAB, or any analysis tool.',
            style: AppTheme.geist(
              fontSize: 12,
              color: c.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Format selector
          Text(
            'FORMAT',
            style: AppTheme.geist(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: c.textSubtle,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: ExportFormat.values.map((f) {
              final selected = f == _format;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: f != ExportFormat.values.last ? 8 : 0,
                  ),
                  child: _FormatChip(
                    format: f,
                    selected: selected,
                    onTap: () => setState(() => _format = f),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Data streams
          Text(
            'DATA STREAMS',
            style: AppTheme.geist(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: c.textSubtle,
            ),
          ),
          const SizedBox(height: 10),

          if (_hasEeg)
            _DataToggle(
              label: 'EEG / Signal Data',
              subtitle: _isCapture
                  ? '${widget.capture!.signalSession!.channelCount} channels · '
                        '${widget.capture!.signalSession!.samples.length} samples · '
                        '${widget.capture!.signalSession!.sampleRateHz.round()} Hz'
                  : '${widget.workout!.eegSamples.length} band-power samples',
              icon: Icons.waves_rounded,
              value: _includeEeg,
              onChanged: (v) => setState(() => _includeEeg = v),
            ),

          if (_hasHr)
            _DataToggle(
              label: 'Heart Rate',
              subtitle: _isCapture
                  ? '${widget.capture!.bleHrSession!.samples.length} BPM samples · '
                        '${widget.capture!.bleHrSession!.rrMs.length} RR intervals'
                  : '${widget.workout!.hrSamples.length} samples',
              icon: Icons.favorite_rounded,
              value: _includeHr,
              onChanged: (v) => setState(() => _includeHr = v),
            ),

          if (_hasGps)
            _DataToggle(
              label: 'GPS Track',
              subtitle: '${widget.workout!.gpsSamples.length} waypoints',
              icon: Icons.route_rounded,
              value: _includeGps,
              onChanged: (v) => setState(() => _includeGps = v),
            ),

          if (_hasEnvironment)
            _DataToggle(
              label: 'Environment',
              subtitle: 'Temperature, AQI, humidity, conditions',
              icon: Icons.air_rounded,
              value: _includeEnvironment,
              onChanged: (v) => setState(() => _includeEnvironment = v),
            ),

          _DataToggle(
            label: 'Metadata',
            subtitle: 'Session info, device details, timestamps',
            icon: Icons.info_outline_rounded,
            value: _includeMetadata,
            onChanged: (v) => setState(() => _includeMetadata = v),
          ),

          const SizedBox(height: 24),

          // Export button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _export,
              icon: _isExporting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: dark ? AppTheme.midnight : Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _isExporting ? 'Exporting…' : 'Export & Share',
                style: AppTheme.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: dark ? AppTheme.midnight : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: dark ? AppTheme.midnight : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Format hint
          Center(
            child: Text(
              _format == ExportFormat.edfPlus
                  ? 'EDF+ files open in MNE-Python, EEGLAB, BrainVision Analyzer'
                  : _format == ExportFormat.csv
                  ? 'CSV files work with pandas, R, Excel, MATLAB, any ML pipeline'
                  : 'JSON files work with BrainFlow, custom scripts, REST APIs',
              textAlign: TextAlign.center,
              style: AppTheme.geist(
                fontSize: 11,
                color: c.textFaint,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable format chip (CSV / EDF+ / JSON).
class _FormatChip extends StatelessWidget {
  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.cyan.withValues(alpha: 0.12) : c.tintFaint,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? AppTheme.cyan.withValues(alpha: 0.5)
                : c.borderSubtle,
          ),
        ),
        child: Column(
          children: [
            Text(
              format.label,
              style: AppTheme.geistMono(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.cyan : c.textBody,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              format.extension,
              style: AppTheme.geist(fontSize: 10, color: c.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// A toggle row for enabling/disabling a data stream in the export.
class _DataToggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DataToggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.miruns;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? AppTheme.cyan : c.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: value ? c.textStrong : c.textMuted,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.geist(fontSize: 11, color: c.textFaint),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppTheme.cyan,
            ),
          ),
        ],
      ),
    );
  }
}
