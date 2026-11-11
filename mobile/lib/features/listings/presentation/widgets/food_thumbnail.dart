import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'category_picker.dart';

class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({
    super.key,
    required this.category,
    this.size = 72,
    this.available = true,
  });

  final String? category;
  final double size;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: available ? null : AppColors.field,
        gradient: available
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryPale, AppColors.primarySoft],
              )
            : null,
      ),
      child: Icon(
        categoryIcon(category),
        size: size * 0.45,
        color: available
            ? Theme.of(context).colorScheme.primary
            : AppColors.textMuted,
      ),
    );
  }
}
