import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_lock.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// First-run set-up: a welcome, then the three things the app needs to be
/// useful from the first transaction — the currency, an account to spend
/// from, and whether to read bank SMS and lock the app.
///
/// Every step is optional: Skip (or Get started with nothing filled in)
/// leaves the defaults, and all of it can be changed later in Settings.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  const OnboardingScreen({super.key, this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 4;

  final PageController _controller = PageController();
  final _accountName = TextEditingController();
  final _openingBalance = TextEditingController();
  int _page = 0;
  String _accountType = 'bank';
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _accountName.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  void _leave() {
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// The balance typed on the account step, or null when it can't be read.
  /// Blank counts as zero.
  int? get _balanceMinor {
    final text = _openingBalance.text.trim();
    if (text.isEmpty) return 0;
    if (validateAmountField(text, allowZero: true) != null) return null;
    return parseMinor(text);
  }

  /// Saves the account typed on the account step (when a name was given) and
  /// makes it the default for new transactions, then leaves.
  Future<void> _finish() async {
    if (_saving) return;
    final name = _accountName.text.trim();
    if (name.isNotEmpty) {
      final balance = _balanceMinor;
      if (balance == null) {
        // Back to the step with the problem rather than dropping the account.
        _controller.animateToPage(2,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Check the current balance — it is not a number.')));
        return;
      }
      setState(() => _saving = true);
      final accounts = context.read<AccountProvider>();
      final settings = context.read<SettingsProvider>();
      try {
        final id = await accounts.addAccount(
            Account(name: name, type: _accountType, openingBalance: balance));
        await settings.setDefaultAccountId(id);
      } catch (e, st) {
        // Set-up must never trap the user: the account can be added later.
        AppLogger.error('Could not save the first account', e, st);
      }
      if (!mounted) return;
    }
    _leave();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  // Skips the set-up; nothing typed so far is saved.
                  onPressed: isLast ? null : _leave,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _StepPage(
                    icon: Icons.account_balance_wallet,
                    title: 'Welcome to Finance Tracker',
                    description:
                        'Spending, accounts, credit cards, budgets and '
                        'investments in one place — stored on this phone, '
                        'not on a server.\n\nThree quick questions and you '
                        'are ready.',
                  ),
                  _StepPage(
                    icon: Icons.currency_exchange,
                    title: 'Your currency',
                    description: 'Amounts are shown in it. Accounts in another '
                        'currency can be added later.',
                    child: _CurrencyChoice(),
                  ),
                  _StepPage(
                    icon: Icons.account_balance,
                    title: 'Your main account',
                    description:
                        'Where most of your spending comes from. Leave the '
                        'name blank to add accounts later.',
                    child: _AccountForm(
                      name: _accountName,
                      balance: _openingBalance,
                      type: _accountType,
                      onTypeChanged: (t) => setState(() => _accountType = t),
                    ),
                  ),
                  const _StepPage(
                    icon: Icons.tune,
                    title: 'Make it yours',
                    description: 'Both are off unless you turn them on, and '
                        'can be changed any time in Settings.',
                    child: _OptionSwitches(),
                  ),
                ],
              ),
            ),
            _PageDots(count: _pageCount, active: _page),
            const SizedBox(height: Space.lg),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xl),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _next,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  ),
                  child: Text(isLast ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One step: a brand badge, a title, a line of explanation and (on the set-up
/// steps) the controls. Scrolls, so the keyboard and large text never clip it.
class _StepPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? child;
  const _StepPage({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The welcome step has room for the large hero badge; the steps with
    // controls use a smaller one so the controls stay above the fold.
    final badge = child == null ? 140.0 : 84.0;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  gradient: brandGradient(context),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon,
                    size: badge * 0.48, color: onBrandGradient(context)),
              ),
              SizedBox(height: child == null ? 40 : 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: Space.md),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: FontSizes.bodyLarge,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (child != null) ...[
                const SizedBox(height: Space.xl),
                child!,
                const SizedBox(height: Space.lg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The base currency, applied as soon as it is tapped.
class _CurrencyChoice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in SettingsProvider.currencyOptions)
          ChoiceChip(
            label: Text(c, style: const TextStyle(fontSize: FontSizes.title)),
            selected: settings.currencySymbol == c,
            showCheckmark: false,
            onSelected: (_) => settings.setCurrencySymbol(c),
          ),
      ],
    );
  }
}

class _AccountForm extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController balance;
  final String type;
  final ValueChanged<String> onTypeChanged;
  const _AccountForm({
    required this.name,
    required this.balance,
    required this.type,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<SettingsProvider>().currencySymbol;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: 'bank',
                  label: Text('Bank'),
                  icon: Icon(Icons.account_balance_outlined)),
              ButtonSegment(
                  value: 'cash',
                  label: Text('Cash'),
                  icon: Icon(Icons.payments_outlined)),
            ],
            selected: {type},
            onSelectionChanged: (s) => onTypeChanged(s.first),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Account name',
            hintText: type == 'cash' ? 'e.g. Wallet' : 'e.g. HDFC Savings',
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: balance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Current balance (optional)',
            prefixText: '$symbol ',
          ),
        ),
      ],
    );
  }
}

class _OptionSwitches extends StatelessWidget {
  const _OptionSwitches();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.sms_outlined),
            title: const Text('Find transactions in bank SMS'),
            subtitle: const Text(
                'Read on this phone only, and nothing is recorded until '
                'you confirm it'),
            value: settings.smsImportEnabled,
            onChanged: settings.setSmsImportEnabled,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('App lock'),
            subtitle: const Text('Ask for your fingerprint or PIN to open'),
            value: settings.appLockEnabled,
            onChanged: (on) => setAppLockChecked(context, on),
          ),
        ],
      ),
    );
  }
}

/// Animated page indicator: the active dot stretches into a pill.
class _PageDots extends StatelessWidget {
  final int count;
  final int active;
  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: Space.xs),
            width: i == active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
          ),
      ],
    );
  }
}
