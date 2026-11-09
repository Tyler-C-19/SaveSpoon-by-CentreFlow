import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../listings/presentation/pages/customer_home_page.dart';
import '../../../seller_profile/presentation/widgets/profile_banner.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.showBrowse = false});

  final bool showBrowse;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (showBrowse) return CustomerHomePage(name: auth.user?.name ?? '');
    return SafeArea(
      child: Column(
        children: [
          if (auth.user?.role == 'vendor') const ProfileBanner(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Welcome back, ${auth.user?.name ?? ''}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Signed in as ${auth.user?.role ?? ''}'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
