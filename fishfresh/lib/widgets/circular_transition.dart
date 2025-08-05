import 'package:flutter/material.dart';

class CircularRevealRoute extends PageRouteBuilder {
  final Widget page;
  final Offset? center; // Optional center override

  CircularRevealRoute({
    required this.page,
    this.center,
  }) : super(
          transitionDuration: const Duration(milliseconds: 700),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            );

            return AnimatedBuilder(
              animation: curvedAnimation,
              builder: (context, child) {
                return ClipPath(
                  clipper: CircleRevealClipper(
                    revealPercent: curvedAnimation.value,
                    center: center,
                  ),
                  child: child,
                );
              },
              child: child,
            );
          },
        );
}

class CircleRevealClipper extends CustomClipper<Path> {
  final double revealPercent;
  final Offset? center;

  CircleRevealClipper({
    required this.revealPercent,
    this.center,
  });

  @override
  Path getClip(Size size) {
    final Offset epicenter = center ?? Offset(size.width / 2, size.height / 2);
    final double radius = revealPercent * size.longestSide * 1.2;

    return Path()
      ..addOval(Rect.fromCircle(center: epicenter, radius: radius));
  }

  @override
  bool shouldReclip(covariant CircleRevealClipper oldClipper) {
    return revealPercent != oldClipper.revealPercent ||
        center != oldClipper.center;
  }
}
