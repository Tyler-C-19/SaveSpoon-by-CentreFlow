import 'dart:async';

import 'package:flutter/widgets.dart';

// Refreshes when the screen is shown again, when the app resumes,
// and on a timer while the screen is showing.
mixin AutoRefresh<T extends StatefulWidget> on State<T> {
  static const Duration interval = Duration(seconds: 30);

  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  bool? _visible;

  Future<void> autoRefresh();

  bool get _showing =>
      mounted &&
      (_visible ?? false) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_showing) autoRefresh();
      },
    );
    _timer = Timer.periodic(interval, (_) {
      if (_showing) autoRefresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final cameBack = _visible == false && visible;
    _visible = visible;
    if (cameBack) autoRefresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }
}
