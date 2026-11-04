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

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashPage.displayTime,
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
  bool _timeUp = false;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_leaveWhenReady);
    _timer = Timer(SplashPage.displayTime, () {
      _timeUp = true;
      _leaveWhenReady();
    });
  }

  void _leaveWhenReady() {
    if (!_timeUp || !mounted || _auth.status == AuthStatus.unknown) return;
    _auth.removeListener(_leaveWhenReady);
    context.go(
      _auth.status == AuthStatus.authenticated
          ? AppRoutes.home
          : AppRoutes.login,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_leaveWhenReady);
    _controller.dispose();
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
        ],
      ),
    );
  }
}
