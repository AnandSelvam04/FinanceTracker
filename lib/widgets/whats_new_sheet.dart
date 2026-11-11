import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/insets.dart';
import '../utils/whats_new.dart';

/// Shows what changed in this release. Opened once after an update, and from
/// Settings → What's new.
Future<void> showWhatsNewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _WhatsNewSheet(),
  );
}

class _WhatsNewSheet extends StatelessWidget {
  const _WhatsNewSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Padding(
        padding: bottomSheetPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("What's new", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text('Version ${WhatsNew.version}',
                style: TextStyle(fontSize: 13, color: mutedTextColor(context))),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in WhatsNew.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        child: Icon(item.icon,
                            color: scheme.onSecondaryContainer, size: 20),
                      ),
                      title: Text(item.title),
                      subtitle: Text(item.body),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
