// Layout helpers for modal bottom sheets.

import 'package:flutter/material.dart';

/// Comfortable tap-target height for a sheet's primary action button, so
/// Save/Apply stays easy to hit (Material's minimum is 48dp).
const double kSheetActionHeight = 48;

/// Padding for a modal bottom sheet's content.
///
/// The bottom inset has to clear two different things:
///  * `viewInsets.bottom` — the on-screen keyboard, when a field has focus.
///  * `padding.bottom` — the system navigation/gesture bar in edge-to-edge
///    mode. Without it the last control sits under the nav bar and is hard
///    to tap.
///
/// These never double-count: when the keyboard is open it covers the nav bar
/// and Flutter already reports `padding.bottom` as 0.
EdgeInsets bottomSheetPadding(BuildContext context) => EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom +
          16,
    );
