import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../../../../../../core/theme/app_theme.dart';

/// Full-screen welcome / splash screen with animated miruns brand logo.
/// Shown on every cold start before entering the main app.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────

  /// Master entrance: drives logo fade-in + scale.
  late final AnimationController _entrance;

  /// Continuous breathing pulse on the rings.
  late final AnimationController _breathe;

  /// Tagline reveal (staggered after logo).
  late final AnimationController _tagline;

  /// Button slide-up.
  late final AnimationController _button;

  /// Gradient line reveal.
  late final AnimationController _line;

  // ── Derived animations ─────────────────────────────────────────────────

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _buttonSlide;
  late final Animation<double> _buttonOpacity;
  late final Animation<double> _lineWidth;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _tagline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _button = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Logo: gentle scale from 0.8→1.0 with ease-out.
    _logoScale = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Tagline fades in.
    _taglineOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _tagline, curve: Curves.easeOut));

    // Button slides up from below.
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _button, curve: Curves.easeOutCubic));
    _buttonOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _button, curve: Curves.easeOut));

    // Gradient line width.
    _lineWidth = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _line, curve: Curves.easeOutCubic));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _entrance.forward();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _line.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _tagline.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _button.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _breathe.dispose();
    _tagline.dispose();
    _button.dispose();
    _line.dispose();
    super.dispose();
  }

  void _enter() {
    HapticFeedback.lightImpact();
    context.go('/sport');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.midnight,
        body: Stack(
          children: [
            // ── Subtle radial gradient background ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _breathe,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _BackgroundPainter(breathe: _breathe.value),
                  );
                },
              ),
            ),

            // ── Main content ──
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // ── Animated logo ──
                  AnimatedBuilder(
                    animation: Listenable.merge([_entrance, _breathe]),
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: _BrandOrb(breathe: _breathe.value),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 48),

                  // ── Wordmark ──
                  AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Text(
                          'miruns',
                          style: AppTheme.geist(
                            fontSize: 52,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -1.0,
                            color: AppTheme.moonbeam,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // ── Gradient accent line ──
                  AnimatedBuilder(
                    animation: _line,
                    builder: (context, _) {
                      return Container(
                        width: 48 * _lineWidth.value,
                        height: 1,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.glow, AppTheme.cyan],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // ── Tagline ──
                  AnimatedBuilder(
                    animation: _tagline,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _taglineOpacity.value,
                        child: Text(
                          'Neuroscience meets sport.',
                          style: AppTheme.geist(
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0.5,
                            color: AppTheme.fog,
                          ),
                        ),
                      );
                    },
                  ),

                  const Spacer(flex: 4),

                  // ── Enter button ──
                  AnimatedBuilder(
                    animation: _button,
                    builder: (context, _) {
                      return SlideTransition(
                        position: _buttonSlide,
                        child: Opacity(
                          opacity: _buttonOpacity.value,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _enter,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppTheme.midnight,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  textStyle: AppTheme.geist(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                child: const Text('Enter'),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Version / footer ──
                  AnimatedBuilder(
                    animation: _button,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _buttonOpacity.value * 0.5,
                        child: Text(
                          'v1.0',
                          style: AppTheme.geist(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF444444),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Brand Orb — animated logo icon with pulsing rings
// ═════════════════════════════════════════════════════════════════════════════

class _BrandOrb extends StatelessWidget {
  const _BrandOrb({required this.breathe});

  final double breathe;

  @override
  Widget build(BuildContext context) {
    const size = 160.0;
    final accent = AppTheme.cyan;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Transform.scale(
            scale: 1.0 + breathe * 0.08,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: 0.06 + breathe * 0.04),
                  width: 1,
                ),
              ),
            ),
          ),
          // Middle ring
          Transform.scale(
            scale: 1.0 + breathe * 0.04,
            child: Container(
              width: size * 0.72,
              height: size * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: 0.10 + breathe * 0.06),
                  width: 1,
                ),
              ),
            ),
          ),
          // Inner glow circle
          Container(
            width: size * 0.48,
            height: size * 0.48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.06 + breathe * 0.02),
            ),
          ),
          // Logo image
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/miruns-icon-512.png',
              width: 64,
              height: 64,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Background painter — subtle radial gradient that breathes
// ═════════════════════════════════════════════════════════════════════════════

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({required this.breathe});

  final double breathe;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final radius = size.width * (0.6 + breathe * 0.1);

    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          AppTheme.cyan.withValues(alpha: 0.03 + breathe * 0.01),
          AppTheme.glow.withValues(alpha: 0.01),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.breathe != breathe;
}
