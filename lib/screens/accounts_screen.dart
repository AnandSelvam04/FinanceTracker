import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_provider.dart';
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
  double _openingBalance = 0;

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

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account == null ? 'Add Account' : 'Edit Account'),
        content: Form(
          key: _formKey,
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
              TextFormField(
                initialValue: _openingBalance == 0
                    ? ''
                    : _openingBalance.toStringAsFixed(2),
                decoration:
                    const InputDecoration(labelText: 'Opening Balance'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  return double.tryParse(value) == null
                      ? 'Invalid number'
                      : null;
                },
                onSaved: (value) =>
                    _openingBalance = double.tryParse(value ?? '') ?? 0,
              ),
            ],
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

          final totalBalance = accounts.fold(
              0.0, (sum, a) => sum + (provider.balanceOf(a) ?? 0));

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
                          '₹${totalBalance.toStringAsFixed(2)}',
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
                        subtitle: Text(Account.typeLabel(account.type)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              balance == null
                                  ? '…'
                                  : '₹${balance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
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
        child: const Icon(Icons.add),
        onPressed: () => _showAccountDialog(),
      ),
    );
  }
}
