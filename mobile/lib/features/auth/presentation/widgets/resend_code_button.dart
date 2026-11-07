import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';

class ResendCodeButton extends StatefulWidget {
  const ResendCodeButton({super.key, required this.onResend});

  static const int cooldownSeconds = 60;

  final Future<void> Function() onResend;

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  Timer? _timer;
  int _secondsLeft = ResendCodeButton.cooldownSeconds;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = ResendCodeButton.cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) timer.cancel();
      setState(() => _secondsLeft -= 1);
    });
  }

  Future<void> _resend() async {
    _startCountdown();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onResend();
      messenger.showSnackBar(
        const SnackBar(content: Text('A new code is on its way.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _secondsLeft > 0 ? null : _resend,
      child: Text(
        _secondsLeft > 0 ? 'Resend code in ${_secondsLeft}s' : 'Resend code',
      ),
    );
  }
}
