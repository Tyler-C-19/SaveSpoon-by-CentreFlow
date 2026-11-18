import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

// Stock from 0 to 999, set with − / + or by typing.
class StockEditor extends StatefulWidget {
  const StockEditor({super.key, required this.value, required this.onChanged});

  static const int max = 999;

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  State<StockEditor> createState() => _StockEditorState();
}

class _StockEditorState extends State<StockEditor> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(StockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (int.tryParse(_text.text) != widget.value) {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final typed = int.tryParse(text);
    if (typed != null && typed <= StockEditor.max) {
      widget.onChanged?.call(typed);
    }
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
            icon: const Icon(Icons.remove),
            onPressed: change != null && value > 0
                ? () => change(value - 1)
                : null,
          ),
          SizedBox(
            width: 56,
            child: TextField(
              key: const ValueKey('stock-field'),
              controller: _text,
              enabled: change != null,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
              onChanged: _typed,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.add),
            onPressed: change != null && value < StockEditor.max
                ? () => change(value + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
