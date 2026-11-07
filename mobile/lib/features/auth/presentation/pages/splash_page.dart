import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/brand_header.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const Duration displayTime = Duration(milliseconds: 3400);
  static const Key logoKey = Key('splash-logo');
  static const Key sheetKey = Key('splash-sheet');

  static const double startScale = 1.5;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Just before the logo starts moving towards the login layout.
  static const double _decisionPoint = 0.56;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashPage.displayTime,
  );
  late final AnimationController _fadeOut = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _circle = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.26, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _logoIn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.18, 0.4, curve: Curves.easeOutBack),
  );
  late final Animation<double> _taglineIn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.34, 0.47, curve: Curves.easeOut),
  );
  late final Animation<double> _taglineOut = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.56, 0.64, curve: Curves.easeIn),
  );
  late final Animation<double> _moveToHeader = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 1, curve: Curves.easeInOutCubic),
  );
  late final Animation<Offset> _sheetIn =
      Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.6, 1, curve: Curves.easeInOutCubic),
        ),
      );

  Timer? _timer;
  late final AuthProvider _auth = context.read<AuthProvider>();
  bool _started = false;
  bool _animationsOff = false;
  bool _timeUp = false;
  bool _leaving = false;

  bool get _atDecisionPoint =>
      _animationsOff ? _timeUp : _controller.value >= _decisionPoint;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_decide);
    _controller.addListener(_decide);
  }

  void _decide() {
    if (_leaving || !mounted || !_atDecisionPoint) return;
    switch (_auth.status) {
      case AuthStatus.unknown:
        _controller.stop();
      case AuthStatus.authenticated:
        _goHome();
      case AuthStatus.unauthenticated:
        _continueToLogin();
    }
  }

  void _goHome() {
    _leaving = true;
    _controller.stop();
    final home = AppRoutes.homeFor(_auth.user!.role);
    if (_animationsOff) return context.go(home);
    _fadeOut.forward().whenComplete(() {
      if (mounted) context.go(home);
    });
  }

  void _continueToLogin() {
    if (_controller.isCompleted) {
      _leaving = true;
      context.go(AppRoutes.login, extra: AppRoutes.splash);
    } else if (_animationsOff) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _animationsOff = MediaQuery.disableAnimationsOf(context);
    if (_animationsOff) {
      _controller.value = _decisionPoint;
      _timer = Timer(SplashPage.displayTime, () {
        _timeUp = true;
        _decide();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_decide);
    _controller.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final circleSize =
        2 * math.sqrt(size.width * size.width + size.height * size.height);
    final travel = BrandHeader.logoCentreY(context) - size.height / 2;

    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: Stack(
        alignment: Alignment.center,
        children: [
          OverflowBox(
            maxWidth: circleSize,
            maxHeight: circleSize,
            child: ScaleTransition(
              scale: _circle,
              child: SizedBox.square(
                dimension: circleSize,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final settle =
                  SplashPage.startScale -
                  (SplashPage.startScale - 1) * _moveToHeader.value;
              return Transform.translate(
                offset: Offset(0, travel * _moveToHeader.value),
                child: Transform.scale(
                  scale: _logoIn.value * settle,
                  child: child,
                ),
              );
            },
            child: BrandHeader.logo(key: SplashPage.logoKey),
          ),
          // Above the logo so its square background stays hidden.
          Positioned.fill(
            top: BrandHeader.logoCentreY(context) + BrandHeader.height / 2,
            child: AnimatedBuilder(
              animation: _auth,
              builder: (context, child) =>
                  _auth.status == AuthStatus.authenticated
                  ? const SizedBox.shrink()
                  : child!,
              child: SlideTransition(
                position: _sheetIn,
                child: const KeyedSubtree(
                  key: SplashPage.sheetKey,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.page,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadius.sheet),
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: NeverScrollableScrollPhysics(),
                      child: IgnorePointer(child: LoginSheet()),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: const Offset(0, 170),
              child: Opacity(
                opacity: (_taglineIn.value * (1 - _taglineOut.value)).clamp(
                  0.0,
                  1.0,
                ),
                child: child,
              ),
            ),
            child: Text(
              'Save food. Save money.',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: AppColors.onBrand),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _fadeOut,
                child: const ColoredBox(color: AppColors.page),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
