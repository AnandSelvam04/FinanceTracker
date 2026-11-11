import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../utils/haptics.dart';
import 'swipe_delete_background.dart';

/// Gives a list row the same swipes everywhere: left to delete, right to
/// edit. The row never leaves on its own — the swipe only starts [onDelete]
/// or [onEdit] (each with whatever confirmation it already has) and the row
/// springs back; the list redraws when the data actually changes.
///
/// The actions are also published to screen readers, which cannot swipe a
/// Dismissible.
class SwipeActions extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SwipeActions({
    required Key super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (onEdit == null && onDelete == null) return child;
    final direction = onEdit != null && onDelete != null
        ? DismissDirection.horizontal
        : onDelete != null
            ? DismissDirection.endToStart
            : DismissDirection.startToEnd;
    return Semantics(
      customSemanticsActions: {
        if (onEdit != null) const CustomSemanticsAction(label: 'Edit'): onEdit!,
        if (onDelete != null)
          const CustomSemanticsAction(label: 'Delete'): onDelete!,
      },
      child: Dismissible(
        key: key!,
        direction: direction,
        background: onEdit != null
            ? const _SwipeEditBackground()
            : const SwipeDeleteBackground(),
        secondaryBackground: onEdit != null && onDelete != null
            ? const SwipeDeleteBackground()
            : null,
        confirmDismiss: (dir) async {
          Haptics.medium();
          if (dir == DismissDirection.startToEnd) {
            onEdit?.call();
          } else {
            onDelete?.call();
          }
          return false;
        },
        child: child,
      ),
    );
  }
}

/// The strip revealed behind a row as it is swiped right to edit.
class _SwipeEditBackground extends StatelessWidget {
  const _SwipeEditBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, color: scheme.onPrimary),
          const SizedBox(width: 8),
          Text('Edit',
              style: TextStyle(
                  color: scheme.onPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
