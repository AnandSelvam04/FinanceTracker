import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_total_card.dart';
import 'add_transfer_screen.dart';
import '../widgets/dispose_with_route.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _type = 'cash';
  int _openingBalance = 0; // minor units
  String? _currency; // null = base currency
  double _rate = 1.0;
  String? _last4;
  int? _statementDay; // credit-card billing cycle
  int? _dueDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountProvider>().fetchAccounts();
    });
  }

  /// Validates a billing-cycle day: blank is allowed, otherwise 1–28 (capped
  /// at 28 so it lands in every month).
  String? _dayValidator(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return (n == null || n < 1 || n > 28) ? 'Enter a day 1–28' : null;
  }

  int? _parseDay(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : int.tryParse(t);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments;
      case 'bank':
        return Icons.account_balance;
      case 'upi':
        return Icons.qr_code;
      case 'credit_card':
        return Icons.credit_card;
      default:
        return Icons.account_balance_wallet;
    }
  }

  Future<void> _showAccountDialog({Account? account}) async {
    _name = account?.name ?? '';
    _type = account?.type ?? 'cash';
    _openingBalance = account?.openingBalance ?? 0;
    _currency = account?.currency;
    _rate = account?.rate ?? 1.0;
    _last4 = account?.last4;
    _statementDay = account?.statementDay;
    _dueDay = account?.dueDay;

    final base = context.read<SettingsProvider>().currencySymbol;
    // Offer the base symbol plus the standard options, de-duplicated.
    final currencyChoices =
        <String>{base, ...SettingsProvider.currencyOptions}.toList();
    final rateController =
        TextEditingController(text: _rate == 1.0 ? '' : _rate.toString());

    // DisposeWithRoute disposes the controller once the dialog has closed.
    await showDialog(
      context: context,
      builder: (context) => DisposeWithRoute(
        notifiers: [rateController],
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final isForeign = _currency != null && _currency != base;
            return AlertDialog(
              title: Text(account == null ? 'Add Account' : 'Edit Account'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Required'
                            : null,
                        onSaved: (value) => _name = value ?? '',
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: Account.types
                            .map((t) => DropdownMenuItem(
                                value: t, child: Text(Account.typeLabel(t))))
                            .toList(),
                        // Rebuild the dialog so the billing-cycle fields show
                        // or hide as the type changes.
                        onChanged: (v) =>
                            setDialogState(() => _type = v ?? _type),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _currency ?? base,
                        decoration:
                            const InputDecoration(labelText: 'Currency'),
                        items: currencyChoices
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c == base ? '$c (base)' : c)))
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          _currency = (v == null || v == base) ? null : v;
                          if (_currency == null) {
                            _rate = 1.0;
                            rateController.text = '';
                          }
                        }),
                      ),
                      if (isForeign)
                        TextFormField(
                          controller: rateController,
                          decoration: InputDecoration(
                            labelText: 'Exchange rate',
                            helperText: '1 $_currency = ? $base',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            if (!isForeign) return null;
                            final r = double.tryParse(value ?? '');
                            return (r == null || r <= 0)
                                ? 'Enter a positive rate'
                                : null;
                          },
                          onSaved: (value) =>
                              _rate = double.tryParse(value ?? '') ?? 1.0,
                        ),
                      TextFormField(
                        initialValue: _openingBalance == 0
                            ? ''
                            : minorToEditString(_openingBalance),
                        decoration: InputDecoration(
                            labelText:
                                'Opening Balance (${_currency ?? base})'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          return double.tryParse(value) == null
                              ? 'Invalid number'
                              : null;
                        },
                        onSaved: (value) =>
                            _openingBalance = parseMinor(value ?? '') ?? 0,
                      ),
                      TextFormField(
                        initialValue: _last4 ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Last 4 digits (optional)',
                          helperText: 'Routes bank SMS alerts to this account',
                          counterText: '',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          return RegExp(r'^\d{4}$').hasMatch(text)
                              ? null
                              : 'Enter exactly 4 digits';
                        },
                        onSaved: (value) {
                          final text = value?.trim() ?? '';
                          _last4 = text.isEmpty ? null : text;
                        },
                      ),
                      // Billing cycle — only meaningful for a credit card.
                      // Setting both a statement day and a due day turns on the
                      // "amount owed" reminder before the payment is due.
                      if (_type == 'credit_card') ...[
                        TextFormField(
                          initialValue: _statementDay?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Statement day (1–28)',
                            helperText: 'Day of month your bill is generated',
                            counterText: '',
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          validator: _dayValidator,
                          onSaved: (v) => _statementDay = _parseDay(v),
                        ),
                        TextFormField(
                          initialValue: _dueDay?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Payment due day (1–28)',
                            helperText: 'Day of month payment is due',
                            counterText: '',
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          validator: _dayValidator,
                          onSaved: (v) => _dueDay = _parseDay(v),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();
                      final isCard = _type == 'credit_card';
                      final newAccount = Account(
                        id: account?.id,
                        name: _name,
                        type: _type,
                        openingBalance: _openingBalance,
                        color: account?.color,
                        currency: _currency,
                        rate: _currency == null ? 1.0 : _rate,
                        last4: _last4,
                        // Billing cycle only applies to credit cards.
                        statementDay: isCard ? _statementDay : null,
                        dueDay: isCard ? _dueDay : null,
                      );
                      final provider = context.read<AccountProvider>();
                      if (account == null) {
                        await provider.addAccount(newAccount);
                      } else {
                        await provider.updateAccount(newAccount);
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                  child: Text(account == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
            'Remove "${account.name}"? Transactions linked to it are kept but lose their account link.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AccountProvider>().deleteAccount(account.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer between accounts',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddTransferScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<AccountProvider>(
        builder: (context, provider, _) {
          final accounts = provider.accounts;
          if (accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message:
                  'Add cash, bank, UPI, or card accounts to track balances.',
              actionLabel: 'Add account',
              onAction: () => _showAccountDialog(),
            );
          }

          // Convert each account to base currency so the total is meaningful
          // even when accounts are held in different currencies.
          final totalBalance = provider.totalBaseBalance();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: HeroTotalCard(
                  label: 'Total balance',
                  // Signed: credit-card balances are negative, and enough of
                  // them can take the total negative too.
                  amount: formatMoneySigned(totalBalance),
                  caption: '${accounts.length} '
                      '${accounts.length == 1 ? 'account' : 'accounts'}',
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: accounts.length,
                  padding: scrollPadding(context, all: 12, fab: true),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final balance = provider.balanceOf(account);
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        // The account's own colour when one was picked, as a
                        // tint like the category avatars; the theme's
                        // secondary container otherwise.
                        leading: Builder(builder: (context) {
                          final scheme = Theme.of(context).colorScheme;
                          final own = account.color == null
                              ? null
                              : Color(account.color!);
                          final dark =
                              Theme.of(context).brightness == Brightness.dark;
                          return CircleAvatar(
                            backgroundColor: own == null
                                ? scheme.secondaryContainer
                                : own.withValues(alpha: dark ? 0.28 : 0.15),
                            child: Icon(_iconForType(account.type),
                                color: own ?? scheme.onSecondaryContainer),
                          );
                        }),
                        title: Text(account.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          Account.typeLabel(account.type),
                          if (account.isForeign) account.currency!,
                          // Visible at a glance so it is obvious which
                          // accounts SMS import can route to.
                          if (account.last4 != null) '••${account.last4}',
                          // Surfaces that a card has a billing cycle set.
                          if (account.hasBillingCycle) 'Due ${account.dueDay}',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              balance == null
                                  ? '…'
                                  : formatMoneySignedIn(
                                      account.symbol, balance),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: balance != null && balance < 0
                                      ? expenseColor(context)
                                      : null),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Delete account',
                              onPressed: () => _confirmDelete(account),
                            ),
                          ],
                        ),
                        onTap: () => _showAccountDialog(account: account),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Account',
        onPressed: () => _showAccountDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
