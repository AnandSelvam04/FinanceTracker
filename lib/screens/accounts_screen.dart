import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_format.dart';
import 'add_transfer_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountProvider>().fetchAccounts();
    });
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

    final base = context.read<SettingsProvider>().currencySymbol;
    // Offer the base symbol plus the standard options, de-duplicated.
    final currencyChoices = <String>{base, ...SettingsProvider.currencyOptions}
        .toList();
    final rateController = TextEditingController(
        text: _rate == 1.0 ? '' : _rate.toString());

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
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
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Required' : null,
                      onSaved: (value) => _name = value ?? '',
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: Account.types
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(Account.typeLabel(t))))
                          .toList(),
                      onChanged: (v) => _type = v ?? _type,
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    final newAccount = Account(
                      id: account?.id,
                      name: _name,
                      type: _type,
                      openingBalance: _openingBalance,
                      color: account?.color,
                      currency: _currency,
                      rate: _currency == null ? 1.0 : _rate,
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
          ElevatedButton(
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                        'No accounts yet. Add cash, bank, UPI, or card accounts to track balances.'),
                  ],
                ),
              ),
            );
          }

          // Convert each account to base currency so the total is meaningful
          // even when accounts are held in different currencies.
          final totalBalance = provider.totalBaseBalance();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Balance',
                            style: TextStyle(fontSize: 16)),
                        Text(
                          formatMoney(totalBalance),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: accounts.length,
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final balance = provider.balanceOf(account);
                    return Card(
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child: Icon(_iconForType(account.type),
                              color: Colors.green),
                        ),
                        title: Text(account.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(account.isForeign
                            ? '${Account.typeLabel(account.type)} · ${account.currency}'
                            : Account.typeLabel(account.type)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              balance == null
                                  ? '…'
                                  : formatMoneyIn(account.symbol, balance),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
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
        tooltip: 'Add account',
        onPressed: () => _showAccountDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
