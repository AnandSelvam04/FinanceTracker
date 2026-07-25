// Layout inset helpers.
//
// The app runs edge-to-edge, so the system navigation/gesture bar overlays the
// bottom of every screen. Nothing is inset automatically: a scrollable's last
// item and a bottom sheet's action button will both happily draw underneath it
// and become hard (or impossible) to tap. These helpers add that inset back.

import 'package:flutter/material.dart';

/// Comfortable tap-target height for a sheet's primary action button, so
/// Save/Apply stays easy to hit (Material's minimum is 48dp).
const double kSheetActionHeight = 48;

/// Room to leave beneath a [FloatingActionButton] so list content can be
/// scrolled out from behind it.
const double kFabScrollRoom = 88;

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

/// Padding for a scrollable screen body, with the system nav-bar inset added
/// underneath so the last item can always be scrolled clear of it.
///
/// [all] is the base inset on every side; use [top] to override just the top.
/// Set [fab] on screens with a floating action button to also leave
/// [kFabScrollRoom] beneath the content.
EdgeInsets scrollPadding(
  BuildContext context, {
  double all = 16,
  double? top,
  bool fab = false,
}) =>
    EdgeInsets.fromLTRB(
      all,
      top ?? all,
      all,
      all + (fab ? kFabScrollRoom : 0) + MediaQuery.paddingOf(context).bottom,
    );

/// Bottom inset that clears the system navigation/gesture bar, plus [extra].
/// For leaving room under content that does not scroll.
double safeBottom(BuildContext context, {double extra = 0}) =>
    MediaQuery.paddingOf(context).bottom + extra;
