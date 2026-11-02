import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Main smooth slow entrance controller
  late final AnimationController _entranceController;

  // Slow continuous breathing / floating controller
  late final AnimationController _floatController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _glowAnimation;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Slow, elegant entrance (3.5 seconds)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // Smooth, cinematic scale-in
    _scaleAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // Gradual, soft fade-in
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeInOut),
      ),
    );

    // Glow aura expanding softly
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.20, 1.0, curve: Curves.easeOut),
      ),
    );

    // 2. Slow continuous breathing/floating animation (3.0 seconds per cycle)
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    // Start entrance
    _entranceController.forward();

    // Navigate to Onboarding after 4.8 seconds (calm and relaxed)
    Future.delayed(const Duration(milliseconds: 4800), () {
      _goToOnboarding();
    });
  }

  void _goToOnboarding() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 900),
        pageBuilder: (_, animation, secondaryAnimation) =>
            const OnboardingScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF011A11),
      body: GestureDetector(
        onTap: _goToOnboarding, // Tap anytime to proceed
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── DEEP LUXURY BACKGROUND GRADIENT ─────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, 0.0),
                  radius: 1.2,
                  colors: [
                    Color(0xFF0A5837),
                    Color(0xFF03311F),
                    Color(0xFF011A11),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),

            // ── SLOW CONCENTRIC AURA RINGS ──────────────────────
            AnimatedBuilder(
              animation: _floatController,
              builder: (context, child) {
                final float = _floatController.value;
                return CustomPaint(
                  painter: _SlowAuraPainter(progress: float),
                  size: size,
                );
              },
            ),

            // ── ONLY THE ANIMATED LOGO ───────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceController,
                  _floatController,
                ]),
                builder: (context, child) {
                  // Float offset calculation (subtle smooth vertical float of ~7px)
                  final floatVal = _floatController.value;
                  final floatOffset = math.sin(floatVal * math.pi) * 8.0;

                  // Breathing scale effect (subtle 1.0 to 1.03 scale)
                  final breathScale = 1.0 + (floatVal * 0.035);

                  final currentScale = _scaleAnimation.value * breathScale;
                  final currentOpacity = _fadeAnimation.value.clamp(0.0, 1.0);
                  final currentGlow = _glowAnimation.value;

                  return Transform.translate(
                    offset: Offset(0, floatOffset),
                    child: Transform.scale(
                      scale: currentScale,
                      child: Opacity(
                        opacity: currentOpacity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer pulsing aura halo
                            Container(
                              width: 230 + (floatVal * 20),
                              height: 230 + (floatVal * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF34D399).withValues(
                                  alpha: (0.12 * currentGlow * (0.8 + floatVal * 0.4))
                                      .clamp(0.0, 1.0),
                                ),
                              ),
                            ),

                            // Logo container with white background and rich green shadow
                            Container(
                              width: 195,
                              height: 195,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  // Green emerald glow
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(
                                      alpha: (0.45 * currentGlow).clamp(0.0, 1.0),
                                    ),
                                    blurRadius: 40,
                                    spreadRadius: 8,
                                  ),
                                  // Soft deep shadow
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.30),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/djimpharma_logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlowAuraPainter extends CustomPainter {
  final double progress;

  _SlowAuraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // Slow ambient wave 1
    final radius1 = 135.0 + (progress * 25);
    paint.color = const Color(0xFF34D399).withValues(
      alpha: (0.16 * (1.0 - (progress * 0.5))).clamp(0.0, 1.0),
    );
    canvas.drawCircle(center, radius1, paint);

    // Slow ambient wave 2
    final radius2 = 185.0 + (progress * 35);
    paint.color = const Color(0xFF10B981).withValues(
      alpha: (0.10 * (1.0 - (progress * 0.6))).clamp(0.0, 1.0),
    );
    canvas.drawCircle(center, radius2, paint);
  }

  @override
  bool shouldRepaint(covariant _SlowAuraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
