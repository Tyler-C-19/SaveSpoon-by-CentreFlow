import 'package:flutter/material.dart';

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'SaveSpoon',
      style: theme.textTheme.displaySmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }
}
