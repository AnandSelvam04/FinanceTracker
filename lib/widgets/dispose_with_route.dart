import 'package:flutter/widgets.dart';

/// Disposes [notifiers] (typically a sheet's or dialog's text controllers)
/// when this widget leaves the tree.
///
/// Wrap the content returned by a `showModalBottomSheet` / `showDialog`
/// builder with it, instead of disposing the controllers once the `show…`
/// future completes. That future completes as soon as the route is popped,
/// while its closing animation is still rendering the text fields — so the
/// fields went on using controllers that had already been disposed. This
/// widget is only unmounted after the route has fully gone.
class DisposeWithRoute extends StatefulWidget {
  final List<ChangeNotifier> notifiers;
  final Widget child;

  const DisposeWithRoute({
    super.key,
    required this.notifiers,
    required this.child,
  });

  @override
  State<DisposeWithRoute> createState() => _DisposeWithRouteState();
}

class _DisposeWithRouteState extends State<DisposeWithRoute> {
  @override
  void dispose() {
    for (final n in widget.notifiers) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
