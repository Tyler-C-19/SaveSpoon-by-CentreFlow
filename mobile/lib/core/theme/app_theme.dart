import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF1B8A3A);
  static const Color primaryPale = Color(0xFFE8F5EA);

  static const Color brand = Color(0xFF28A745);
  static const Color onBrand = Color(0xFFFFFFFF);

  // Must match launch_background.xml.
  static const Color splashBackground = Color(0xFFEAF3DE);

  static const Color page = Color(0xFFFFFFFF);
  static const Color field = Color(0xFFF3F6F4);
  static const Color textMuted = Color(0xFF667085);

  static const Color warningPale = Color(0xFFFFF4E0);
  static const Color onWarning = Color(0xFF7A4B00);

  static const Color primarySoft = Color(0xFFCDE8D3);
  static const Color lowStock = Color(0xFFB42318);
  static const Color lowStockPale = Color(0xFFFEE4E2);
  static const Color sellingFast = Color(0xFFC4320A);
  static const Color sellingFastPale = Color(0xFFFFE6D5);
  static const Color endingSoon = Color(0xFFB54708);
  static const Color endingSoonPale = Color(0xFFFEF0C7);
  static const Color unlisted = Color(0xFFEAECF0);
  static const Color cardShadow = Color(0x1A101828);
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.cardShadow,
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double md = 12;
  static const double lg = 16;
  static const double sheet = 32;
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryPale,
      surface: AppColors.page,
    );

    final fieldShape = UnderlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderSide: BorderSide.none,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
    );
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.page,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 18,
        ),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: fieldShape,
        enabledBorder: fieldShape,
        focusedBorder: fieldShape.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: fieldShape.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: fieldShape.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : AppColors.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : AppColors.textMuted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
