import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import '../../services/push_service.dart';
import '../../widgets/account_warning_dialog.dart';
import '../auth/account_suspended_screen.dart';
import '../../repositories/admin_repository.dart';

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
    try {
      final profile = await AuthService().restoreSession().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      await minimumDisplay;
      if (!mounted) return;

      if (profile?.id != null) {
        final suspension = await AuthService().suspensionReason();
        if (!mounted) return;
        if (suspension != null) {
          await AuthService().logout();
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => AccountSuspendedScreen(reason: suspension),
            ),
            (_) => false,
          );
          return;
        }
        await showPendingAccountWarnings(context);
        if (!mounted) return;
        SessionService.loginUser(profile!);
        final isAdmin = await AdminRepository().isAdmin();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          isAdmin
              ? AppRoutes.adminDashboard
              : profile.accountType == 'Seller'
              ? AppRoutes.sellerDashboard
              : AppRoutes.home,
          (_) => false,
        );
        return;
      }

      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while restoring the startup session'),
        ),
      );
      await minimumDisplay;
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    } finally {
      // Let a tapped push notification open its screen now that start-up
      // navigation is finished.
      PushService.instance.markAppReady();
    }
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
