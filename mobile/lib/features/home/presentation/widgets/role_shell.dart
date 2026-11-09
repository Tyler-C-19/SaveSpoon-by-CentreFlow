import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';

class RoleTab {
  const RoleTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class RoleShell extends StatelessWidget {
  const RoleShell({super.key, required this.shell, required this.tabs});

  static const List<RoleTab> customerTabs = [
    RoleTab('Home', Icons.home_outlined),
    RoleTab('Search', Icons.search),
    RoleTab('Orders', Icons.receipt_long_outlined),
    RoleTab('Profile', Icons.person_outline),
  ];

  static const List<RoleTab> vendorTabs = [
    RoleTab('Home', Icons.home_outlined),
    RoleTab('Listings', Icons.fastfood_outlined),
    RoleTab('Orders', Icons.receipt_long_outlined),
    RoleTab('Profile', Icons.person_outline),
  ];

  final StatefulNavigationShell shell;
  final List<RoleTab> tabs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBody: true,
      backgroundColor: colorScheme.surface,
      body: shell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Material(
            color: colorScheme.surface,
            elevation: 6,
            shape: StadiumBorder(
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (index) => shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              ),
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(icon: Icon(tab.icon), label: tab.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
