import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/investment_provider.dart';
import '../models/investment.dart';
import '../utils/currency_format.dart';

class AddInvestmentScreen extends StatefulWidget {
  /// Pre-selects a type so "add another contribution" from a type's detail
  /// screen lands on the right instrument without extra taps.
  final String? initialType;

  const AddInvestmentScreen({super.key, this.initialType});

  @override
  State<AddInvestmentScreen> createState() => _AddInvestmentScreenState();
}

class _AddInvestmentScreenState extends State<AddInvestmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _customTypeController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  late String _selectedType;
  bool _isSaving = false;

  final List<String> _types = Investment.builtInTypes;

  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    // If the caller passed a built-in type, start on it; a custom type starts
    // on "Other" with the value prefilled so it round-trips.
    final initial = widget.initialType;
    if (initial != null && _types.contains(initial)) {
      _selectedType = initial;
    } else if (initial != null && initial.isNotEmpty) {
      _selectedType = Investment.otherType;
      _customTypeController.text = initial;
    } else {
      _selectedType = 'Stocks';
    }
  }

  /// The type the form will actually save (resolving the custom-type box).
  String get _resolvedType => _selectedType == Investment.otherType
      ? _customTypeController.text.trim()
      : _selectedType;

  /// A sensible default name when the user leaves the name blank, e.g.
  /// "Silver Jul 2026", so each contribution is self-describing without
  /// forcing the user to name it.
  String _defaultName() {
    final type = _resolvedType.isEmpty ? 'Investment' : _resolvedType;
    return '$type ${_monthAbbr[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

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
                decoration: InputDecoration(
                  labelText: '${l.accountName} (${l.optional})',
                  hintText: _defaultName(),
                ),
                // Name is optional: blank falls back to an auto-generated
                // label like "Silver Jul 2026".
              ),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: l.amount),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => value!.isEmpty ? l.enterAmount : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('${l.date}: ${l.dateWithDay(_selectedDate)}'),
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
              // When "Other" is picked, let the user name their own type
              // (e.g. NPS, PPF, REIT, Crypto) instead of hard-coding every one.
              if (_selectedType == Investment.otherType)
                TextFormField(
                  controller: _customTypeController,
                  decoration:
                      InputDecoration(labelText: l.enterInvestmentType),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) =>
                      (_selectedType == Investment.otherType &&
                              (value == null || value.trim().isEmpty))
                          ? l.enterTypeOrPick
                          : null,
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSaving = true);
                          final type = _resolvedType;
                          final enteredName = _nameController.text.trim();
                          final investment = Investment(
                            name: enteredName.isEmpty
                                ? _defaultName()
                                : enteredName,
                            amount: rupeesToMinor(
                                double.parse(_amountController.text)),
                            date: _selectedDate,
                            type: type,
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
                                  SnackBar(
                                      content:
                                          Text(l.errorWithDetails('$e'))));
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
