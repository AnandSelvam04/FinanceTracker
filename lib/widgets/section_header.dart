import 'package:flutter/material.dart';

/// A left-aligned heading that labels a group of content on a screen.
///
/// One shared style so every page's section headings match — previously the
/// dashboard and Settings each defined their own private version with different
/// casing, size, and colour. Screens that need different surrounding spacing
/// (e.g. a Settings list with no horizontal padding of its own) pass [padding].
class SectionHeader extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionHeader(this.text,
      {super.key, this.padding = const EdgeInsets.only(bottom: 8)});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
