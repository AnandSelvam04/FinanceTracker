import 'package:flutter/material.dart';

import '../utils/dimens.dart';
import '../utils/insets.dart';

/// Opens a form as a full-screen page (a close button in place of Back),
/// for forms too long for a dialog: in a dialog the keyboard left a few
/// lines of the form visible on a phone.
Future<T?> showFormPage<T>(BuildContext context,
        {required WidgetBuilder builder}) =>
    Navigator.of(context).push<T>(
      MaterialPageRoute(fullscreenDialog: true, builder: builder),
    );

/// The page [showFormPage] shows. Takes the same parts as an [AlertDialog]
/// — a title, the form, and its buttons — so a dialog moves here by
/// changing only its name. The buttons sit under the form, above the
/// keyboard.
class FormPage extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  const FormPage({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: title),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.md, Space.lg, Space.lg),
              child: Center(
                // A readable width on a tablet.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: content,
                ),
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Material(
              elevation: 2,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg,
                    safeBottom(context, extra: Space.sm)),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: Space.sm,
                  children: actions,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
