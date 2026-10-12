import 'dart:math' as math;

import 'package:digitalkhata/services/splashservises.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Branded loading screen shown while the session and local data are prepared.
class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen>
    with SingleTickerProviderStateMixin {
  final Splashservises _splashservises = Splashservises();
  late final AnimationController _motion;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _pulse = _motion.drive(const _Pulse());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _splashservises.login(context);
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF08111F),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF101E33),
                      Color(0xFF08111F),
                      Color(0xFF111C2C),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -130,
              right: -100,
              child: _GlowOrb(
                size: 310,
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -130,
              child: _GlowOrb(
                size: 350,
                color: const Color(0xFF3C8DCC).withValues(alpha: 0.12),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth < 360
                      ? 12.0
                      : 20.0;
                  final availableWidth =
                      constraints.maxWidth - horizontalPadding * 2;
                  final orbitSize = math.min(
                    availableWidth,
                    math.min(
                      constraints.maxHeight * 0.42,
                      constraints.maxWidth * 0.92,
                    ),
                  );
                  final logoSize = orbitSize * 0.38;

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: constraints.maxHeight < 520 ? 16 : 32,
                            ),
                            Center(
                              // Nothing here rebuilds per frame: the painter
                              // and the scale listen to the controller, and
                              // the blurred logo card is drawn once and reused.
                              child: SizedBox(
                                  width: orbitSize,
                                  height: orbitSize,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.square(orbitSize),
                                          painter: _OrbitPainter(_motion),
                                        ),
                                      ),
                                      ScaleTransition(
                                        scale: _pulse,
                                        child: RepaintBoundary(child: Container(
                                          width: logoSize + 30,
                                          height: logoSize + 30,
                                          padding: const EdgeInsets.all(11),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              34,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.14,
                                              ),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.accent
                                                    .withValues(alpha: 0.16),
                                                blurRadius: 48,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: BrandLogo(size: logoSize),
                                        )),
                                      ),
                                    ],
                                  ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 850),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 14 * (1 - value)),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    AppBrand.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Every account, clear and in control.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.07,
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shield_outlined,
                                          size: 15,
                                          color: AppColors.accent.withValues(
                                            alpha: 0.95,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'PRIVATE  ·  OFFLINE READY',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.76,
                                            ),
                                            fontSize: 10,
                                            letterSpacing: 1,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: 142,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: const LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor: Color(0x334B5B70),
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Preparing your khata',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(
                              height: constraints.maxHeight < 520 ? 16 : 32,
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

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.43;
    final orbitRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      radius * 0.78,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.035)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawArc(
      orbitRect,
      progress * math.pi * 2,
      math.pi * 0.72,
      false,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2,
    );

    final dotAngle = progress * math.pi * 2;
    final dotCenter = Offset(
      center.dx + math.cos(dotAngle) * radius,
      center.dy + math.sin(dotAngle) * radius,
    );
    canvas.drawCircle(dotCenter, 4, Paint()..color = AppColors.accent);

    final secondAngle = -dotAngle * 0.7 + math.pi;
    final secondDot = Offset(
      center.dx + math.cos(secondAngle) * radius * 0.78,
      center.dy + math.sin(secondAngle) * radius * 0.78,
    );
    canvas.drawCircle(secondDot, 3, Paint()..color = const Color(0xFF91BFFF));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

/// Gentle breathing of the logo: one slow in-and-out per orbit.
class _Pulse extends Animatable<double> {
  const _Pulse();

  @override
  double transform(double t) => 1 + math.sin(t * math.pi * 2) * 0.025;
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}
