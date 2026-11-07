import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

class OtpInput extends StatelessWidget {
  const OtpInput({super.key, required this.controller});

  static const int length = 6;

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => Row(
            children: List.generate(length, (index) {
              final digit = index < value.text.length ? value.text[index] : '';
              final isCurrent = index == value.text.length;
              return Expanded(
                child: Container(
                  height: 60,
                  margin: EdgeInsets.only(
                    right: index == length - 1 ? 0 : AppSpacing.sm,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.field,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    digit,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(length),
              ],
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
