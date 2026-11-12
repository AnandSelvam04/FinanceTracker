import 'package:flutter/material.dart';

import '../utils/destinations.dart';

/// A rounded-square icon on a tint of its own colour: the leading badge of
/// the More menu's rows and of the add sheet's options.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const IconBadge({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: destinationFill(context, color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: destinationForeground(context, color)),
    );
  }
}
