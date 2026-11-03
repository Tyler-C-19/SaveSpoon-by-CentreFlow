import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/google_sso_button.dart';
import 'pin_verification_page.dart';
import 'sign_up_page.dart';

/// ============================================================================
/// PAGE: LoginPage
/// PURPOSE: Initial landing screen for user authentication (students & sellers).
/// ============================================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ---------------------------------------------------------------------------
  // CONTROLLERS & FORM STATE
  // ---------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    // Clean up text controllers when widget is unmounted
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUSINESS / AUTH LOGIC SECTION
  // ---------------------------------------------------------------------------

  /// LOGIC TO IMPLEMENT:
  /// 1. Call AuthRepository.loginWithEmail(identifier, password).
  /// 2. If backend requires 2FA / OTP, navigate to PinVerificationPage.
  /// 3. If token received directly, persist session and navigate to Role-based Home.
  void _handleLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      final identifier = _identifierController.text.trim();
      debugPrint('=== [LOGIN CREDENTIALS] ===');
      debugPrint('Username or Email: $identifier');
      debugPrint('Password: ${_passwordController.text}');
      debugPrint('===========================');

      // Temporary flow: Direct to OTP PIN verification page
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PinVerificationPage(email: identifier),
        ),
      );
    }
  }

  /// LOGIC TO IMPLEMENT:
  /// 1. Trigger GoogleSignIn plugin authentication.
  /// 2. Exchange Google auth credential with backend API.
  /// 3. Determine if user needs profile completion or route to Home.
  void _handleGoogleSso() {
    debugPrint('=== [LOGIN WITH SSO] ===');
    debugPrint('Provider: Google');
    debugPrint('========================');
  }

  /// LOGIC TO IMPLEMENT:
  /// 1. Call backend API to request a password reset OTP for the entered identifier.
  /// 2. Route user to PIN verification, then to PasswordResetPage.
  void _handleForgotPassword() {
    final identifier = _identifierController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PinVerificationPage(
          email: identifier.isNotEmpty ? identifier : 'your registered email',
        ),
      ),
    );
  }

  /// Navigate to Sign Up screen
  void _navigateToSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SignUpPage(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI SECTION
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- UI: App Logo Badge ---
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
                              Icons.restaurant,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- UI: Header & Subtitle ---
                        Text(
                          'Welcome to ${AppConstants.appName}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to continue to your account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // --- UI: Username / Email Input ---
                        CustomTextField(
                          controller: _identifierController,
                          label: 'Username or Email',
                          hintText: 'Enter your username or email',
                          prefixIcon: Icons.person_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your username or email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // --- UI: Password Input ---
                        CustomTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hintText: 'Enter your password',
                          prefixIcon: Icons.lock_outline,
                          isPassword: true,
                          obscureText: _obscurePassword,
                          onToggleVisibility: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),

                        // --- UI: Forgot Password Link ---
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- UI: Primary Login Action Button ---
                        ElevatedButton(
                          onPressed: _handleLogin,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: AppColors.primary,
                          ),
                          child: const Text('Login'),
                        ),
                        const SizedBox(height: 20),

                        // --- UI: SSO Divider ---
                        Row(
                          children: [
                            const Expanded(child: Divider(color: AppColors.border)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'or continue with',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: AppColors.border)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // --- UI: Google SSO Button ---
                        GoogleSsoButton(
                          onPressed: _handleGoogleSso,
                        ),
                        const SizedBox(height: 24),

                        // --- UI: Sign Up Navigation Footer ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: _navigateToSignUp,
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
