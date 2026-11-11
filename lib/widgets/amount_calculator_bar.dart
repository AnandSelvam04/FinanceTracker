import 'package:flutter/material.dart';

import '../utils/amount_expression.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/haptics.dart';

/// Operator keys for an amount field, with the running result.
///
/// The number keyboard has no + or ×, so a sum ("250+80", "1200/3") could
/// not be typed even though the field works one out. These keys put the
/// operator in at the cursor; the answer shows beside them, and tapping it
/// replaces the sum with the figure.
class AmountCalculatorBar extends StatelessWidget {
  final TextEditingController controller;
  const AmountCalculatorBar({super.key, required this.controller});

  static const _operators = ['+', '−', '×', '÷'];
  static const _names = {
    '+': 'Add',
    '−': 'Subtract',
    '×': 'Multiply',
    '÷': 'Divide',
  };

  void _insert(String op) {
    Haptics.tick();
    final text = controller.text;
    final sel = controller.selection;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(at, end, op),
      selection: TextSelection.collapsed(offset: at + op.length),
    );
  }

  void _resolve(double result) {
    Haptics.light();
    final text = result.toStringAsFixed(2);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final isSum = isAmountExpression(value.text);
        final result = isSum ? evaluateAmountExpression(value.text) : null;
        final usable = result != null && result > 0 && isAmountInRange(result);
        return Row(
          children: [
            for (final op in _operators)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: _names[op]!,
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _insert(op),
                      child: SizedBox(
                        width: 40,
                        height: 36,
                        child: Center(
                          child: Text(
                            op,
                            // Fixed size: these are keys, and four of them
                            // must fit beside the result at any text scale.
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 2),
            Expanded(
              child: !isSum
                  ? Text(
                      'Add up or split here',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: mutedTextColor(context)),
                    )
                  : usable
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Use this amount',
                            label: Text(
                              '= ${result.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () => _resolve(result),
                          ),
                        )
                      : Text(
                          'Finish the sum',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: mutedTextColor(context)),
                        ),
            ),
          ],
        );
      },
    );
  }
}
