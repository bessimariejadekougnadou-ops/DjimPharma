import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  // ── CONTROLLERS ───────────────────────────────────────────────
  late final AnimationController _backgroundController;
  late final AnimationController _entranceController;
  late final AnimationController _floatController;

  // ── BACKGROUND 3D ANIMATIONS ──────────────────────────────────
  late final Animation<double> _backgroundFloat;
  late final Animation<double> _backgroundScale;

  // ── ENTRANCE ANIMATIONS (WHEN SCREEN OPENS) ───────────────────
  late final Animation<double> _logoEntranceScale;
  late final Animation<double> _logoEntranceFade;
  late final Animation<double> _logoEntranceRotate;
  late final Animation<Offset> _badgeEntranceSlide;
  late final Animation<double> _badgeEntranceFade;
  late final Animation<Offset> _buttonEntranceSlide;
  late final Animation<double> _buttonEntranceFade;

  // ── SLIDER STATE ──────────────────────────────────────────────
  double _dragPosition = 0;
  static const double _sliderHeight = 70;
  static const double _knobSize = 58;

  @override
  void initState() {
    super.initState();

    // 1. Background 3D floating parallax (repeats infinitely)
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: true);

    _backgroundFloat = Tween<double>(begin: -18, end: 18).animate(
      CurvedAnimation(
        parent: _backgroundController,
        curve: Curves.easeInOutSine,
      ),
    );
    _backgroundScale = Tween<double>(begin: 1.09, end: 1.16).animate(
      CurvedAnimation(
        parent: _backgroundController,
        curve: Curves.easeInOutSine,
      ),
    );

    // 2. Entrance animation sequence on page launch (1800ms)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoEntranceScale = Tween<double>(begin: 0.15, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _logoEntranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    _logoEntranceRotate = Tween<double>(begin: -0.12, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.70, curve: Curves.easeOutCubic),
      ),
    );

    _badgeEntranceSlide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
      ),
    );

    _badgeEntranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 0.75, curve: Curves.easeIn),
      ),
    );

    _buttonEntranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
      ),
    );

    _buttonEntranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.40, 0.85, curve: Curves.easeIn),
      ),
    );

    // 3. Continuous 3D floating & pulsing aura for logo
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    // Trigger entrance animation immediately
    _entranceController.forward();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _entranceController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _navigateToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, secondaryAnimation) => const AuthScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final sliderWidth = (size.width - 64).clamp(1.0, double.infinity).toDouble();
    final maxDrag = (sliderWidth - _knobSize - 10).clamp(0.0, double.infinity).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5EE),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 3D PARALLAX BACKGROUND CAPSULES ───────────────────
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              final val = _backgroundController.value;
              final tiltZ = (val - 0.5) * 0.025;
              final tiltY = (val - 0.5) * 0.015;

              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..scale(_backgroundScale.value)
                  ..translate(0.0, _backgroundFloat.value)
                  ..rotateZ(tiltZ)
                  ..rotateY(tiltY),
                child: child,
              );
            },
            child: Image.asset(
              'assets/images/hero_capsules.jpg',
              fit: BoxFit.cover,
              width: size.width,
              height: size.height,
            ),
          ),

          // ── GRADIENT OVERLAY FOR DEPTH ────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0E5C38).withValues(alpha: 0.65),
                    Colors.transparent,
                    const Color(0xFF011E13).withValues(alpha: 0.76),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),

          // ── MAIN UI CONTENT ───────────────────────────────────
          SafeArea(
            child: Stack(
              children: [
                // ── TOP BADGE (ANIMATED SLIDE DOWN) ───────────
                Align(
                  alignment: Alignment.topCenter,
                  child: SlideTransition(
                    position: _badgeEntranceSlide,
                    child: FadeTransition(
                      opacity: _badgeEntranceFade,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                color: Color(0xFF34D399),
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Pharmacie connectée • Togo 🇹🇬',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x4D000000),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── LOGO AU MILIEU (ENTRÉE DYNAMIQUE + FLOTTEUR 3D) ─
                Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _entranceController,
                      _floatController,
                    ]),
                    builder: (context, child) {
                      final floatVal = _floatController.value;

                      // Float motion (vertical oscillation)
                      final floatOffset = math.sin(floatVal * math.pi) * 8.5;

                      // 3D tilt perspective matching physical capsule depth
                      final tiltX = math.sin(floatVal * math.pi) * 0.05;
                      final tiltY = math.cos(floatVal * math.pi) * 0.04;

                      // Subtle breathing scale
                      final breathScale = 1.0 + (floatVal * 0.035);

                      final entranceScale = _logoEntranceScale.value;
                      final entranceFade = _logoEntranceFade.value.clamp(0.0, 1.0);
                      final entranceRotate = _logoEntranceRotate.value;

                      return Transform.translate(
                        offset: Offset(0, floatOffset),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0014)
                            ..rotateX(tiltX)
                            ..rotateY(tiltY)
                            ..rotateZ(entranceRotate)
                            ..scale(entranceScale * breathScale),
                          child: Opacity(
                            opacity: entranceFade,
                            child: SizedBox(
                              width: (size.width * 0.76).clamp(260.0, 350.0),
                              height: (size.width * 0.76).clamp(260.0, 350.0),
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  // ── HALO DE LUMIÈRE BLANCHE ÉTENDU ───────────
                                  Container(
                                    width: (size.width * 0.74).clamp(250.0, 330.0),
                                    height: (size.width * 0.74).clamp(250.0, 330.0),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.white,
                                          Colors.white.withValues(alpha: 0.96),
                                          Colors.white.withValues(alpha: 0.68),
                                          Colors.white.withValues(alpha: 0.28),
                                          Colors.white.withValues(alpha: 0.0),
                                        ],
                                        stops: const [0.0, 0.55, 0.78, 0.90, 1.0],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withValues(alpha: 0.40),
                                          blurRadius: 32,
                                          spreadRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // ── LOGO TRANSPARENT AU CENTRE ───────────────
                                  SizedBox(
                                    width: (size.width * 0.52).clamp(185.0, 240.0),
                                    height: (size.width * 0.52).clamp(185.0, 240.0),
                                    child: Image.asset(
                                      'assets/images/djimpharma_logo.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── BOUTON COMMENCER (ANIMATED SLIDE UP) ──────
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SlideTransition(
                    position: _buttonEntranceSlide,
                    child: FadeTransition(
                      opacity: _buttonEntranceFade,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 24, 32, 30),
                        child: SizedBox(
                          width: sliderWidth,
                          height: _sliderHeight,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF059669),
                                  Color(0xFF10B981),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color.fromARGB(255, 204, 221, 217).withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    SizedBox(width: 54),
                                    Text(
                                      'Commencer',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '>>',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  left: _dragPosition,
                                  child: GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        _dragPosition = (_dragPosition + details.delta.dx)
                                            .clamp(0.0, maxDrag);
                                      });
                                    },
                                    onHorizontalDragEnd: (_) {
                                      if (_dragPosition > maxDrag * 0.6) {
                                        _navigateToAuth();
                                      } else {
                                        setState(() => _dragPosition = 0);
                                      }
                                    },
                                    onTap: _navigateToAuth,
                                    child: Container(
                                      width: _knobSize,
                                      height: _knobSize,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: Color(0xFF047857),
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
