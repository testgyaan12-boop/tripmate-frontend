import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Premium TripMate splash: full-screen scenic road image, gradient scrim,
/// centered brand lockup, Get Started / Login actions.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash_road.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF065F46)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Cinematic scrim: legibility top + bottom, transparent middle.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xB30B1220),
                  Color(0x000B1220),
                  Color(0x000B1220),
                  Color(0xD90B1220),
                ],
                stops: [0.0, 0.35, 0.55, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      _FadeRise(
                        delay: 0,
                        child: _LogoBadge(),
                      ),
                      const SizedBox(height: 20),
                      _FadeRise(
                        delay: 120,
                        child: const Text(
                          'TripMate',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _FadeRise(
                        delay: 220,
                        child: const Text(
                          'Plan Trips Together',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _FadeRise(
                        delay: 300,
                        child: const Text(
                          'Create routes, invite friends, vote places and explore together',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xB3FFFFFF),
                          ),
                        ),
                      ),
                      const Spacer(flex: 4),
                      _FadeRise(
                        delay: 380,
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => context.go('/register'),
                            child: const Text('Get Started'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _FadeRise(
                        delay: 440,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () => context.go('/login'),
                          child: const Text('Login'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient badge: mountain + road + location pin composite mark.
class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x662563EB),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(Icons.terrain, color: Colors.white, size: 46),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFF2563EB), width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 10),
                ],
              ),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFF2563EB),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot fade + rise entrance animation.
class _FadeRise extends StatelessWidget {
  final int delay;
  final Widget child;
  const _FadeRise({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 550 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, value, _) {
        final t = ((value * (550 + delay) - delay) / 550).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
