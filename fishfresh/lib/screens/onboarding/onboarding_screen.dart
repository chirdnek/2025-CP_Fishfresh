// ignore_for_file: use_build_context_synchronously, sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:fishfresh/widgets/onboarding_page.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:circular_reveal_animation/circular_reveal_animation.dart';
import '../login.dart';
import 'package:fishfresh/services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final PageController _controller = PageController();
  late AnimationController _animationController;
  late Animation<double> _animation;

  bool onLastPage = false;
  int currentIndex = 0;
  int previousIndex = 0;

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
      bgColor: Color(0xFF40C4FF),
    ),
    OnboardingPage(
      imagePath: 'assets/images/market.png',
      title: 'Track & Learn',
      subtitle: 'Save scans, spot patterns, and make smarter seafood choices.',
      bgColor: Color(0xFFE91E63),
    ),
    OnboardingPage(
      imagePath: 'assets/images/logo.png',
      title: 'Fish Fresh',
      subtitle: '',
      bgColor: Color(0xFF009688),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  void _setupAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _goToNextScreen() async {
    final storage = StorageService();
    await storage.setOnboardingSeen();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // PageView with Circular Reveal Animation
          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() {
                previousIndex = currentIndex;
                currentIndex = index;
                onLastPage = index == _pages.length - 1;
              });

              if (index > previousIndex) {
                _animationController.reset();
                _animationController.forward();
              }
            },
            itemBuilder: (context, index) {
              final isForward = currentIndex > previousIndex;
              final isCurrentPage = index == currentIndex;
              final page = _pages[index];

              if (isCurrentPage && isForward) {
                return CircularRevealAnimation(
                  animation: _animation,
                  centerOffset: Offset(screenSize.width - 40, screenSize.height - 40),
                  child: page,
                );
              } else {
                return page;
              }
            },
          ),

          // Skip Button
          Positioned(
            top: 40,
            right: 20,
            child: TextButton(
              onPressed: _goToNextScreen,
              child: const Text("Skip", style: TextStyle(color: Colors.white)),
            ),
          ),

          // Smooth Page Indicator (raised higher)
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: Center(
              child: SmoothPageIndicator(
                controller: _controller,
                count: _pages.length,
                effect: const WormEffect(
                  dotHeight: 10,
                  dotWidth: 10,
                  activeDotColor: Colors.white,
                ),
              ),
            ),
          ),

          // Floating Action Button: Next/Done
     Positioned(
  bottom: 100,
  left: 0,
  right: 0,
  child: Center(
    child: FloatingActionButton(
      backgroundColor: currentIndex == 0
          ? Colors.white // contrast with black background
          : _pages[currentIndex].bgColor,
      onPressed: () {
        if (onLastPage) {
          _goToNextScreen();
        } else {
          _controller.nextPage(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Icon(
        onLastPage ? Icons.done : Icons.arrow_forward,
        color: currentIndex == 0 ? Colors.black : Colors.white, // icon contrast
      ),
      shape: const CircleBorder(), // enforce circular shape
    ),
  ),
),

        ],
      ),
    );
  }
}
