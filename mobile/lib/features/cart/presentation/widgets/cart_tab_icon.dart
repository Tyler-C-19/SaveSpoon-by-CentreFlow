import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';

class CartTabIcon extends StatefulWidget {
  const CartTabIcon({super.key, required this.icon});

  final IconData icon;

  @override
  State<CartTabIcon> createState() => _CartTabIconState();
}

class _CartTabIconState extends State<CartTabIcon> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CartProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = context.select<CartProvider, int>((cart) => cart.count);
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Icon(widget.icon),
    );
  }
}
