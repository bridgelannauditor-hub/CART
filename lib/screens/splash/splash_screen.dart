import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 1.025,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    _restoreAndNavigate();
  }

  Future<void> _restoreAndNavigate() async {
    final minimumDisplay = Future<void>.delayed(
      const Duration(milliseconds: 500),
    );
    final profile = await AuthService().restoreSession().timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    await minimumDisplay;
    if (!mounted) return;

    if (profile?.id != null) {
      SessionService.loginUser(profile!);
      Navigator.pushNamedAndRemoveUntil(
        context,
        profile.accountType == 'Seller'
            ? AppRoutes.sellerDashboard
            : AppRoutes.home,
        (_) => false,
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F7),
      body: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: SizedBox.expand(
            child: Image.asset(
              'assets/images/splash_vertical.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              semanticLabel: 'C+ART — add art to your cart',
            ),
          ),
        ),
      ),
    );
  }
}
