// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fishfresh/widgets/onboarding_page.dart';
import '../login.dart';
import '../signup.dart';
import 'package:fishfresh/services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  late final AnimationController _spinCtrl;

  int _index = 0;

  final List<OnboardingPage> _pages = const [
    OnboardingPage(
      imagePath: 'assets/images/scan.png',
      title: 'Snap & Scan',
      subtitle: 'Take a photo—our AI checks the fish\'s freshness instantly.',
      bgColor: Colors.white,
    ),
    OnboardingPage(
      imagePath: 'assets/images/freshness.png',
      title: 'Freshness Score',
      subtitle: 'Get clear results and safety tips right away.',
      bgColor: Color.fromARGB(255, 52, 159, 208),
    ),
    OnboardingPage(
      imagePath: 'assets/images/market.png',
      title: 'Track & Learn',
      subtitle: 'Save scans, spot patterns, and make smarter seafood choices.',
      bgColor: Color.fromARGB(255, 11, 152, 107),
    ),
    // Final page uses a dark background so the white panel content pops
    OnboardingPage(
      imagePath: 'assets/images/logo0.png',
      title: '',
      subtitle: '',
      bgColor: Color(0xFF0B0B0B),
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

Future<void> _finishAndGo(Widget screen) async {
  await StorageService().setSeenOnboarding(); // <-- rename here
  if (!mounted) return;
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
}

  Color _contrast(Color bg) =>
      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black;

  Color _arcColor(Color bg) =>
      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white70 : Colors.black54;

  @override
  Widget build(BuildContext context) {
    final bg = _pages[_index].bgColor;
    final textColor = _contrast(bg);
    final progress = (_index + 1) / _pages.length;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Pages
            PageView.builder(
              controller: _controller,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _pages[i],
            ),

            // Skip (hidden on last page)
            if (!_isLast)
              Positioned(
                top: 16,
                right: 16,
                child: TextButton(
                  onPressed: () => _finishAndGo(const LoginScreen()),
                  child: Text('Skip', style: TextStyle(color: textColor)),
                ),
              ),

            // Line progress (hidden on last page to match the clean footer)
            if (!_isLast)
              Positioned(
                left: 24,
                right: 24,
                bottom: 140,
                child: _LineProgress(
                  value: progress,
                  trackColor: textColor == Colors.white ? Colors.white24 : Colors.black26,
                  fillColor: textColor,
                ),
              ),

            // Bottom controls: next button OR last-page panel
            Positioned(
              left: 24,
              right: 24,
              bottom: 36,
              child: _isLast
                  ? _LastPagePanel(
                      onLogin: () => _finishAndGo(const LoginScreen()),
                      onCreate: () => _finishAndGo(const SignUpScreen()),
                    )
                  : Center(
                      child: _NextButton(
                        spinCtrl: _spinCtrl,
                        baseColor: _pages[_index].bgColor,
                        arcColor: _arcColor(_pages[_index].bgColor),
                        onTap: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 520),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------- Widgets -------------------- */

class _LineProgress extends StatelessWidget {
  const _LineProgress({
    required this.value,
    required this.trackColor,
    required this.fillColor,
  });

  final double value; // 0..1
  final Color trackColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final full = constraints.maxWidth;
          final w = full * value.clamp(0.0, 1.0);
          return Stack(
            children: [
              Container(
                width: full,
                height: 6,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                width: w,
                height: 6,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({
    required this.spinCtrl,
    required this.baseColor,
    required this.arcColor,
    required this.onTap,
  });

  final AnimationController spinCtrl;
  final Color baseColor;
  final Color arcColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark;
    final arrowColor = isDark ? Colors.white : Colors.black;

    // Visible ring color that always contrasts with the page background
    final borderColor =
        (isDark ? Colors.white : Colors.black).withOpacity(0.38);

    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // orbiting arcs (unchanged)
          RotationTransition(
            turns: spinCtrl,
            child: CustomPaint(
              size: const Size(78, 78),
              painter: _ArcPainter(color: arcColor, stroke: 3),
            ),
          ),

          // Center circular button with a visible border/ring
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: baseColor,
              border: Border.all(color: borderColor, width: 2.5),
        boxShadow: [
  BoxShadow(
    // was: Colors.white.withOpacity(0.06) / Colors.black.withOpacity(0.08)
    color: isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08),
    blurRadius: 10,
    spreadRadius: 1,
  ),
],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Icon(Icons.arrow_forward, color: arrowColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.color, this.stroke = 3});
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide / 2) - 3;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    const sweep = math.pi / 6;
    canvas.drawArc(rect, -math.pi / 3, sweep, false, paint);
    canvas.drawArc(rect, math.pi * 2 / 3, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.color != color || old.stroke != stroke;
}

/* ---------- Final page panel (matches your screenshot) ---------- */

class _LastPagePanel extends StatelessWidget {
  const _LastPagePanel({required this.onLogin, required this.onCreate});
  final VoidCallback onLogin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    // Copy you can change anytime
    const headline = 'Easy for\nBeginners,\nPowerful for All';
    const support =
        'Effortless freshness checks for everyone:\nScan in seconds and make smarter fish choices.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline
        const Text(
          headline,
          style: TextStyle(
            fontSize: 36, // large, but still mobile-friendly
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Subcopy with small "arrow" bullet for flair (optional)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 2.0, right: 8.0),
              child: Icon(Icons.north_east, size: 16, color: Colors.white70),
            ),
            Expanded(
              child: Text(
                support,
                style: TextStyle(fontSize: 14.5, height: 1.45, color: Colors.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Divider
        Container(height: 1, color: Colors.white12),
        const SizedBox(height: 16),

        // CTAs
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onLogin,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.white24, width: 1.2),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  backgroundColor: const Color(0x1AFFFFFF), // subtle filled dark
                ),
                child: const Text('LOG IN'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton(
                onPressed: onCreate,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: const Text('CREATE ACCOUNT'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
