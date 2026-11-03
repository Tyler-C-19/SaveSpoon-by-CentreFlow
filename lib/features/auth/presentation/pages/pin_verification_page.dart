import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';

/// ============================================================================
/// PAGE: PinVerificationPage
/// PURPOSE: 6-digit email OTP verification screen for user verification & password resets.
/// ============================================================================
class PinVerificationPage extends StatefulWidget {
  final String email;

  const PinVerificationPage({
    super.key,
    this.email = 'your email',
  });

  @override
  State<PinVerificationPage> createState() => _PinVerificationPageState();
}

class _PinVerificationPageState extends State<PinVerificationPage> {
  // ---------------------------------------------------------------------------
  // CONSTANTS & CONTROLLERS
  // ---------------------------------------------------------------------------
  static const int _pinLength = 6;
  final List<TextEditingController> _controllers =
      List.generate(_pinLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_pinLength, (_) => FocusNode());

  // Resend OTP countdown timer (60 seconds)
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PIN HANDLING & BUSINESS LOGIC
  // ---------------------------------------------------------------------------

  /// Starts the 60-second cooldown timer before user can re-request OTP
  void _startCountdown() {
    setState(() => _resendCountdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  /// Concatenates all 6 box values into a single PIN string
  String get _currentPin => _controllers.map((c) => c.text).join();

  /// Logic for handling single digit typing, pasting, and auto-focusing next/previous box
  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Pasting full 6-digit code
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _pinLength; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final nextIndex = digits.length < _pinLength ? digits.length : _pinLength - 1;
      _focusNodes[nextIndex].requestFocus();
      return;
    }

    // Auto-focus next box on input, or previous on backspace
    if (value.isNotEmpty && index < _pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  /// LOGIC TO IMPLEMENT:
  /// 1. Call AuthRepository.verifyOtp(email, pin).
  /// 2. If valid: activate account or issue reset token.
  /// 3. Route user to Home (if logging in/signing up) or PasswordResetPage (if forgot password).
  void _handleVerify() {
    final pin = _currentPin;
    if (pin.length < _pinLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the PIN'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    debugPrint('=== [PIN VERIFIED] ===');
    debugPrint('Email: ${widget.email}');
    debugPrint('Entered PIN: $pin');
    debugPrint('======================');
  }

  /// LOGIC TO IMPLEMENT:
  /// 1. Call backend API: AuthRepository.resendOtp(email).
  /// 2. Show feedback snackbar and restart countdown.
  void _handleResendCode() {
    if (_resendCountdown == 0) {
      _startCountdown();
      debugPrint('=== [PIN RESEND TRIGGERED] ===');
      debugPrint('Resent code to: ${widget.email}');
      debugPrint('==============================');
    }
  }

  // ---------------------------------------------------------------------------
  // UI SECTION
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppColors.border, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- UI: Email Icon Badge ---
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.yellowLight,
                                AppColors.limeLight,
                                AppColors.greenPrimary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.greenPrimary.withValues(alpha: 0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- UI: Title & Target Email Subtitle ---
                      const Text(
                        'Verify PIN Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We have sent a 6-digit verification code to\n${widget.email}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // --- UI: 6 Individual Responsive PIN Digit Boxes ---
                      Row(
                        children: [
                          for (int index = 0; index < _pinLength; index++) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 0.85,
                                child: KeyboardListener(
                                  focusNode: FocusNode(),
                                  onKeyEvent: (event) {
                                    // Handle physical/virtual backspace on empty box
                                    if (event is KeyDownEvent &&
                                        event.logicalKey == LogicalKeyboardKey.backspace &&
                                        _controllers[index].text.isEmpty &&
                                        index > 0) {
                                      _focusNodes[index - 1].requestFocus();
                                    }
                                  },
                                  child: TextFormField(
                                    controller: _controllers[index],
                                    focusNode: _focusNodes[index],
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    maxLength: 1,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      counterText: '',
                                      contentPadding: EdgeInsets.zero,
                                      filled: true,
                                      fillColor: _focusNodes[index].hasFocus
                                          ? AppColors.greenLight.withValues(alpha: 0.15)
                                          : AppColors.inputFill,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppColors.border,
                                          width: 1.2,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                          width: 2.0,
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) => _onDigitChanged(index, value),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 28),

                      // --- UI: Primary Verify Button ---
                      ElevatedButton(
                        onPressed: _handleVerify,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: AppColors.primary,
                        ),
                        child: const Text('Verify PIN'),
                      ),
                      const SizedBox(height: 22),

                      // --- UI: Resend Countdown Timer / Action ---
                      Center(
                        child: _resendCountdown > 0
                            ? Text(
                                "Didn't receive the code? Resend in ${_resendCountdown}s",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : GestureDetector(
                                onTap: _handleResendCode,
                                child: const Text(
                                  'Resend Code',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
