import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/dashboard_layout.dart';
import '../utils/haptics.dart';
import '../utils/insets.dart';
import '../widgets/section_header.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Lets the user arrange the home screen: drag its sections into order,
/// switch off the ones they never look at, and pick the shortcut buttons.
/// Every change is saved (and shows on Home) as it is made.
class CustomizeHomeScreen extends StatelessWidget {
  const CustomizeHomeScreen({super.key});

  static const _sectionIcons = {
    DashboardLayout.netWorth: Icons.account_balance_outlined,
    DashboardLayout.quickAdd: Icons.bolt_outlined,
    DashboardLayout.figures: Icons.payments_outlined,
    DashboardLayout.insights: Icons.lightbulb_outline,
    DashboardLayout.shortcuts: Icons.apps_outlined,
    DashboardLayout.recent: Icons.receipt_long_outlined,
    DashboardLayout.categories: Icons.bar_chart,
    DashboardLayout.merchants: Icons.storefront_outlined,
    DashboardLayout.trends: Icons.show_chart,
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final order = settings.dashboardOrder;
    final hidden = settings.dashboardHidden;
    final shortcuts = settings.homeShortcuts;
    final full = shortcuts.length >= DashboardLayout.maxShortcuts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customise home'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              Haptics.light();
              await settings.setDashboardLayout(
                  order: DashboardLayout.defaultOrder, hidden: const {});
              await settings.setHomeShortcuts(DashboardLayout.defaultShortcuts);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: scrollPadding(context, all: Space.md),
        children: [
          const SectionHeader('Sections',
              padding:
                  EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, Space.xs)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
            child: Text(
              'Drag to reorder. Switch off what you don\'t use.',
              style: TextStyle(
                  fontSize: FontSizes.body, color: mutedTextColor(context)),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderStart: (_) => Haptics.medium(),
              onReorderItem: (from, to) {
                final next = [...order];
                next.insert(to, next.removeAt(from));
                Haptics.tick();
                settings.setDashboardLayout(order: next, hidden: hidden);
              },
              children: [
                for (var i = 0; i < order.length; i++)
                  _SectionRow(
                    key: ValueKey(order[i]),
                    index: i,
                    icon: _sectionIcons[order[i]]!,
                    label: DashboardLayout.sectionLabels[order[i]]!,
                    locked: DashboardLayout.locked.contains(order[i]),
                    shown: !hidden.contains(order[i]),
                    onShown: (on) {
                      Haptics.light();
                      settings.setDashboardLayout(
                        order: order,
                        hidden: on
                            ? ({...hidden}..remove(order[i]))
                            : {...hidden, order[i]},
                      );
                    },
                  ),
              ],
            ),
          ),
          const SectionHeader('Shortcuts',
              padding:
                  EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, Space.xs)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
            child: Text(
              'Up to ${DashboardLayout.maxShortcuts} buttons, shown in the '
              'order you pick them. ${shortcuts.length} chosen.',
              style: TextStyle(
                  fontSize: FontSizes.body, color: mutedTextColor(context)),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in DashboardLayout.allShortcuts)
                // Import SMS only does anything while SMS reading is on.
                if (id != DashboardLayout.sms || settings.smsImportEnabled)
                  FilterChip(
                    label: Text(DashboardLayout.shortcutLabels[id]!),
                    selected: shortcuts.contains(id),
                    onSelected: shortcuts.contains(id) || !full
                        ? (on) {
                            Haptics.tick();
                            settings.setHomeShortcuts(on
                                ? [...shortcuts, id]
                                : ([...shortcuts]..remove(id)));
                          }
                        : null,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool locked;
  final bool shown;
  final ValueChanged<bool> onShown;

  const _SectionRow({
    super.key,
    required this.index,
    required this.icon,
    required this.label,
    required this.locked,
    required this.shown,
    required this.onShown,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: Space.xs, right: Space.sm),
        leading: ReorderableDragStartListener(
          index: index,
          child: Tooltip(
            message: 'Drag to reorder',
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Icon(Icons.drag_indicator, color: muted),
            ),
          ),
        ),
        title: Row(
          children: [
            Icon(icon, size: 20, color: shown ? null : muted),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: shown ? null : muted)),
            ),
          ],
        ),
        subtitle: locked
            ? const Padding(
                padding: EdgeInsets.only(left: Space.xxl),
                child: Text('Always shown'),
              )
            : null,
        trailing: locked
            ? null
            : Switch(
                value: shown,
                onChanged: onShown,
              ),
      ),
    );
  }
}
