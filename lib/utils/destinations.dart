import 'package:flutter/material.dart';

import 'dashboard_layout.dart';

/// How one destination looks wherever it is offered: the same icon and the
/// same colour in the More menu, on a home shortcut and in search results.
///
/// The menu and the shortcuts used to keep a colour list each, so Cards was
/// one blue under More and another on Home, and Reports, Accounts and the
/// Calendar changed hue between the two.
class Destination {
  final IconData icon;
  final Color color;
  const Destination(this.icon, this.color);
}

/// The hues destinations are drawn from. Mid-tone shades that hold contrast
/// as an icon on a tint of themselves (see [destinationFill]) in light mode,
/// and once lightened by [destinationForeground] in dark mode.
class DestinationColors {
  DestinationColors._();

  static const blue = Color(0xFF1E6FD9);
  static const cyan = Color(0xFF00838F);
  static const teal = Color(0xFF00897B);
  static const green = Color(0xFF43A047);
  static const orange = Color(0xFFEF6C00);
  static const deepOrange = Color(0xFFD84315);
  static const pink = Color(0xFFD81B60);
  static const purple = Color(0xFF6A3DE8);
  static const violet = Color(0xFF7E57C2);
  static const indigo = Color(0xFF3949AB);
  static const slate = Color(0xFF546E7A);
}

/// Every screen reached from the More menu or a home shortcut.
class Destinations {
  Destinations._();

  static const reports = Destination(Icons.summarize, DestinationColors.indigo);
  static const cashflow =
      Destination(Icons.stacked_bar_chart, DestinationColors.cyan);
  static const trends = Destination(Icons.show_chart, DestinationColors.blue);
  static const calendar =
      Destination(Icons.calendar_month, DestinationColors.deepOrange);
  static const accounts =
      Destination(Icons.account_balance, DestinationColors.slate);
  static const cards = Destination(Icons.credit_card, DestinationColors.blue);
  static const categories =
      Destination(Icons.category_outlined, DestinationColors.violet);
  static const loans =
      Destination(Icons.handshake_outlined, DestinationColors.orange);
  static const tags = Destination(Icons.sell_outlined, DestinationColors.cyan);
  static const goals =
      Destination(Icons.flag_outlined, DestinationColors.green);
  static const recurring = Destination(Icons.repeat, DestinationColors.pink);
  static const investments =
      Destination(Icons.trending_up, DestinationColors.teal);
  static const sms = Destination(Icons.sms, DestinationColors.purple);
  static const backup = Destination(Icons.cloud, DestinationColors.indigo);
  static const customiseHome =
      Destination(Icons.dashboard_customize_outlined, DestinationColors.violet);
  static const settings = Destination(Icons.settings, DestinationColors.slate);
  static const budgets = Destination(
      Icons.account_balance_wallet_outlined, DestinationColors.green);
  static const help = Destination(Icons.help_outline, DestinationColors.blue);

  /// The look of each home shortcut, by its [DashboardLayout] id.
  static const shortcuts = <String, Destination>{
    DashboardLayout.investments: investments,
    DashboardLayout.cards: cards,
    DashboardLayout.sms: sms,
    DashboardLayout.reports: reports,
    DashboardLayout.accounts: accounts,
    DashboardLayout.goals: goals,
    DashboardLayout.calendar: calendar,
    DashboardLayout.loans: loans,
    DashboardLayout.recurring: recurring,
    DashboardLayout.cashflow: cashflow,
  };
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// [color] as an icon or label: itself in light mode, lightened in dark mode
/// so it stays legible on a dark surface.
Color destinationForeground(BuildContext context, Color color) =>
    _isDark(context) ? Color.lerp(color, Colors.white, 0.4)! : color;

/// A soft tint of [color] to sit behind [destinationForeground].
Color destinationFill(BuildContext context, Color color) =>
    color.withValues(alpha: _isDark(context) ? 0.24 : 0.14);
