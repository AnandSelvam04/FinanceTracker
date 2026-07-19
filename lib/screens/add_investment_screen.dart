import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/investment_provider.dart';
import '../models/investment.dart';
import '../utils/currency_format.dart';

class AddInvestmentScreen extends StatefulWidget {
  const AddInvestmentScreen({super.key});

  @override
  State<AddInvestmentScreen> createState() => _AddInvestmentScreenState();
}

class _AddInvestmentScreenState extends State<AddInvestmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedType = 'Stocks';
  bool _isSaving = false;

  final List<String> _types = [
    'Stocks',
    'Mutual Funds',
    'Bonds',
    'FD',
    'Gold',
    'Silver',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.addInvestment)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: l.accountName),
                validator: (value) =>
                    value!.isEmpty ? 'Enter investment name' : null,
              ),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: l.amount),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => value!.isEmpty ? 'Enter amount' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                      '${l.date}: ${_selectedDate.toLocal().toIso8601String().substring(0, 10)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                      }
                    },
                    child: Text(l.selectDate),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: InputDecoration(labelText: l.accountType),
                items: _types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedType = value!),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSaving = true);
                          final investment = Investment(
                            name: _nameController.text,
                            amount: rupeesToMinor(
                                double.parse(_amountController.text)),
                            date: _selectedDate,
                            type: _selectedType,
                          );
                          final provider = context.read<InvestmentProvider>();
                          try {
                            await provider.addInvestment(investment);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l.investmentAdded)),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed: $e')));
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        }
                      },
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(l.addInvestment),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
