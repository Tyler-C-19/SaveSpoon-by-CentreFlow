import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brand_title.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/widgets/cart_tab_icon.dart';

class RoleTab {
  const RoleTab(this.label, this.icon, {this.isCart = false});

  final String label;
  final IconData icon;
  final bool isCart;
}

class RoleShell extends StatelessWidget {
  const RoleShell({super.key, required this.shell, required this.tabs});

  static const List<RoleTab> customerTabs = [
    RoleTab('Home', Icons.home_outlined),
    RoleTab('Search', Icons.search),
    RoleTab('Cart', Icons.shopping_cart_outlined, isCart: true),
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: const BrandTitle(),
      ),
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
              onDestinationSelected: (index) {
                if (tabs[index].isCart) context.read<CartProvider>().refresh();
                shell.goBranch(
                  index,
                  initialLocation: index == shell.currentIndex,
                );
              },
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: tab.isCart
                        ? CartTabIcon(icon: tab.icon)
                        : Icon(tab.icon),
                    label: tab.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
