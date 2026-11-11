import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class QuantityStepper extends StatefulWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _text.text != '${widget.value}') {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _commit() {
    final change = widget.onChanged;
    final typed = int.tryParse(_text.text);
    if (change == null || typed == widget.value) {
      _text.text = '${widget.value}';
      return;
    }
    if (typed == null || typed < 1 || typed > widget.max) {
      _text.text = '${widget.value}';
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Enter a number from 1 to ${widget.max}.')),
        );
      return;
    }
    change(typed);
  }

  @override
  Widget build(BuildContext context) {
    final change = widget.onChanged;
    final value = widget.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Less',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 18),
            onPressed: change != null && value > 1
                ? () => change(value - 1)
                : null,
          ),
          SizedBox(
            width: 44,
            child: TextField(
              key: const ValueKey('quantity-field'),
              controller: _text,
              focusNode: _focus,
              enabled: change != null,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
              onTap: () => _text.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _text.text.length,
              ),
              onSubmitted: (_) => _focus.unfocus(),
              onTapOutside: (_) => _focus.unfocus(),
            ),
          ),
          IconButton(
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            onPressed: change != null && value < widget.max
                ? () => change(value + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
