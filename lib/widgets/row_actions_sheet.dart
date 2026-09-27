import 'package:flutter/material.dart';

/// What the user picked from a row's action sheet.
enum RowAction { edit, duplicate, delete }

/// The menu a tap on a transaction or investment row opens: Edit, Duplicate
/// (a copy dated today, opened in Add so the date can be changed first) and
/// Delete. Returns the choice, or null when dismissed.
///
/// Callers act on the choice with their own context once the sheet has
/// closed: the sheet's context is gone by then.
Future<RowAction?> showRowActions(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool canDuplicate = true,
  bool canDelete = true,
}) {
  return showModalBottomSheet<RowAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: subtitle == null
                ? null
                : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, RowAction.edit),
          ),
          if (canDuplicate)
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Duplicate'),
              subtitle: const Text('Add a copy — change the date if needed'),
              onTap: () => Navigator.pop(sheetContext, RowAction.duplicate),
            ),
          if (canDelete)
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () => Navigator.pop(sheetContext, RowAction.delete),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
