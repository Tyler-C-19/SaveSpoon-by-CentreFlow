import 'package:flutter/material.dart';

class AddListingButton extends StatefulWidget {
  const AddListingButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<AddListingButton> createState() => _AddListingButtonState();
}

class _AddListingButtonState extends State<AddListingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _press,
    curve: Curves.easeOut,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 0.9,
  ).animate(_curve);
  late final Animation<double> _turn = Tween<double>(
    begin: 0,
    end: 0.25,
  ).animate(_curve);

  bool _opening = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    if (!MediaQuery.disableAnimationsOf(context)) await _press.forward();
    if (!mounted) return;
    widget.onPressed();
    await _press.reverse();
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) {
        if (!_opening && !MediaQuery.disableAnimationsOf(context)) {
          _press.forward();
        }
      },
      onPointerUp: (_) {
        if (!_opening) _press.reverse();
      },
      onPointerCancel: (_) {
        if (!_opening) _press.reverse();
      },
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, _) => FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              backgroundColor: Color.lerp(
                colors.primary,
                colors.primaryContainer,
                _curve.value,
              ),
              foregroundColor: Color.lerp(
                colors.onPrimary,
                colors.primary,
                _curve.value,
              ),
            ),
            onPressed: _open,
            icon: RotationTransition(
              turns: _turn,
              child: const Icon(Icons.add),
            ),
            label: const Text('Add Listing'),
          ),
        ),
      ),
    );
  }
}
