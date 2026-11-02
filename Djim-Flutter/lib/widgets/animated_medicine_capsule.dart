import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MedicineColorTheme {
  purplePink, // Exactly like the user's reference image
  djimPharmaEmerald, // Branded DjimPharma green
}

class AnimatedMedicineCapsule extends StatefulWidget {
  const AnimatedMedicineCapsule({
    super.key,
    this.isLogin = true,
    this.theme = MedicineColorTheme.purplePink,
    this.size = 140.0,
  });

  final bool isLogin;
  final MedicineColorTheme theme;
  final double size;

  @override
  State<AnimatedMedicineCapsule> createState() =>
      _AnimatedMedicineCapsuleState();
}

class _AnimatedMedicineCapsuleState extends State<AnimatedMedicineCapsule>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final AnimationController _switchController;

  @override
  void initState() {
    super.initState();

    // 1. Continuous smooth floating (breathing up & down)
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    // 2. Subtle shine / sparkle shimmer
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // 3. Switch trigger when transitioning between login & register
    _switchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedMedicineCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLogin != widget.isLogin) {
      _switchController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    _switchController.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.theme) {
      case MedicineColorTheme.purplePink:
        return const Color(0xFFDA70D6);
      case MedicineColorTheme.djimPharmaEmerald:
        return const Color(0xFF047857);
    }
  }

  Color get _lightAccentColor {
    switch (widget.theme) {
      case MedicineColorTheme.purplePink:
        return const Color(0xFFF0ABFC);
      case MedicineColorTheme.djimPharmaEmerald:
        return const Color(0xFF10B981);
    }
  }

  Color get _darkOutlineColor {
    switch (widget.theme) {
      case MedicineColorTheme.purplePink:
        return const Color(0xFF0F172A);
      case MedicineColorTheme.djimPharmaEmerald:
        return const Color(0xFF064E3B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _pulseController,
        _switchController,
      ]),
      builder: (context, _) {
        final floatProgress = _floatController.value;
        final pulseProgress = _pulseController.value;
        final switchProgress = _switchController.value;

        // Smooth floating physics
        final capsuleY = math.sin(floatProgress * math.pi) * 8.0;
        final pillY = math.sin((floatProgress + 0.35) * math.pi) * 6.0;
        final capsuleTilt = (math.sin(floatProgress * math.pi) - 0.5) * 0.06;

        // Transition pop on tab switch
        final switchPop = math.sin(switchProgress * math.pi) * 12.0;
        final switchScale = 1.0 + (math.sin(switchProgress * math.pi) * 0.08);

        return Transform.scale(
          scale: switchScale,
          child: SizedBox(
            width: widget.size * 1.3,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 1. Soft glowing background aura
                Positioned(
                  bottom: widget.size * 0.1,
                  child: Container(
                    width: widget.size * 0.9,
                    height: widget.size * 0.22,
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(
                        alpha: 0.12 + (0.08 * pulseProgress),
                      ),
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(
                          widget.size * 0.45,
                          widget.size * 0.11,
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Custom Painted Capsule & Round Pill
                CustomPaint(
                  size: Size(widget.size * 1.3, widget.size),
                  painter: _MedicinePainter(
                    accentColor: _accentColor,
                    lightAccentColor: _lightAccentColor,
                    outlineColor: _darkOutlineColor,
                    capsuleY: capsuleY - switchPop,
                    pillY: pillY - (switchPop * 0.5),
                    capsuleTilt: capsuleTilt,
                    shimmerProgress: pulseProgress,
                    isRegister: !widget.isLogin,
                  ),
                ),

                // 3. Cute sparkling stars floating around (especially on register)
                Positioned(
                  top: 8 + (capsuleY * 0.5),
                  right: 12,
                  child: Transform.rotate(
                    angle: pulseProgress * 0.5,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 20 + (pulseProgress * 4),
                      color: _accentColor.withValues(
                        alpha: 0.6 + (0.4 * pulseProgress),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24 - (pillY * 0.5),
                  left: 8,
                  child: Transform.rotate(
                    angle: -pulseProgress * 0.4,
                    child: Icon(
                      Icons.star_rounded,
                      size: 16 + (pulseProgress * 3),
                      color: _lightAccentColor.withValues(
                        alpha: 0.5 + (0.3 * pulseProgress),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MedicinePainter extends CustomPainter {
  const _MedicinePainter({
    required this.accentColor,
    required this.lightAccentColor,
    required this.outlineColor,
    required this.capsuleY,
    required this.pillY,
    required this.capsuleTilt,
    required this.shimmerProgress,
    required this.isRegister,
  });

  final Color accentColor;
  final Color lightAccentColor;
  final Color outlineColor;
  final double capsuleY;
  final double pillY;
  final double capsuleTilt;
  final double shimmerProgress;
  final bool isRegister;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.height * 0.038;
    final strokePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Center coordinates
    final cx = size.width * 0.42;
    final cy = size.height * 0.50 + capsuleY;

    // ── 1. BACKGROUND SHADOW BLOB (As seen in the reference image) ──
    final blobPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final blobPath = Path()
      ..moveTo(cx - size.height * 0.28, cy + size.height * 0.12)
      ..quadraticBezierTo(
        cx - size.height * 0.36,
        cy + size.height * 0.28,
        cx - size.height * 0.18,
        cy + size.height * 0.36,
      )
      ..close();
    canvas.drawPath(blobPath, blobPaint);

    // ── 2. STANDING CAPSULE (GÉLULE) ───────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(capsuleTilt);

    final capWidth = size.height * 0.42;
    final capHeight = size.height * 0.82;
    final capRadius = capWidth / 2;

    final capsuleRect = Rect.fromCenter(
      center: Offset.zero,
      width: capWidth,
      height: capHeight,
    );
    final capsuleRRect = RRect.fromRectAndRadius(
      capsuleRect,
      Radius.circular(capRadius),
    );

    // A. Fill Bottom Half (White)
    canvas.save();
    canvas.clipRRect(capsuleRRect);
    canvas.drawRect(capsuleRect, whitePaint);

    // B. Fill Top Half (Accent Pink/Violet or Emerald)
    final topRect = Rect.fromLTWH(
      -capWidth / 2,
      -capHeight / 2,
      capWidth,
      capHeight / 2,
    );
    final topPaint = Paint()
      ..shader = LinearGradient(
        colors: [lightAccentColor, accentColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(topRect);
    canvas.drawRect(topRect, topPaint);

    // C. Cute curved shine highlight on top left (as in reference image!)
    final shinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8
      ..strokeCap = StrokeCap.round;

    final shinePath = Path();
    final shineArcRect = Rect.fromCircle(
      center: Offset(-capWidth * 0.10, -capHeight * 0.26),
      radius: capRadius * 0.55,
    );
    shinePath.addArc(shineArcRect, math.pi * 1.05, math.pi * 0.45);
    canvas.drawPath(shinePath, shinePaint);

    canvas.restore(); // Exit clip

    // D. Dividing middle line
    canvas.drawLine(
      Offset(-capWidth / 2, 0),
      Offset(capWidth / 2, 0),
      strokePaint,
    );

    // E. Outer Capsule Outline
    canvas.drawRRect(capsuleRRect, strokePaint);

    canvas.restore(); // Exit capsule transform

    // ── 3. ROUND PILL (COMPRIMÉ AVEC BANDE) ─────────────────────────
    final pillCx = size.width * 0.70;
    final pillCy = size.height * 0.62 + pillY;
    final pillRadius = size.height * 0.25;

    // A. Pill White Base
    canvas.drawCircle(Offset(pillCx, pillCy), pillRadius, whitePaint);

    // B. Vertical Stripe down the pill (As in reference image)
    canvas.save();
    final pillPath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(pillCx, pillCy),
        radius: pillRadius,
      ));
    canvas.clipPath(pillPath);

    final stripeWidth = pillRadius * 0.38;
    final stripeRect = Rect.fromCenter(
      center: Offset(pillCx, pillCy),
      width: stripeWidth,
      height: pillRadius * 2,
    );
    final stripePaint = Paint()
      ..shader = LinearGradient(
        colors: [lightAccentColor, accentColor],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(stripeRect);

    canvas.drawRect(stripeRect, stripePaint);

    // Stripe outline edges inside the pill
    final stripeBorderPaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawLine(
      Offset(pillCx - (stripeWidth / 2), pillCy - pillRadius),
      Offset(pillCx - (stripeWidth / 2), pillCy + pillRadius),
      stripeBorderPaint,
    );
    canvas.drawLine(
      Offset(pillCx + (stripeWidth / 2), pillCy - pillRadius),
      Offset(pillCx + (stripeWidth / 2), pillCy + pillRadius),
      stripeBorderPaint,
    );

    canvas.restore(); // Exit pill clip

    // C. Pill Outer Border
    canvas.drawCircle(Offset(pillCx, pillCy), pillRadius, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _MedicinePainter oldDelegate) {
    return oldDelegate.capsuleY != capsuleY ||
        oldDelegate.pillY != pillY ||
        oldDelegate.capsuleTilt != capsuleTilt ||
        oldDelegate.shimmerProgress != shimmerProgress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isRegister != isRegister;
  }
}
