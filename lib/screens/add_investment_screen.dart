import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../models/investment.dart';
import '../models/recurring_rule.dart';
import '../services/recurring_service.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../utils/date_format.dart';

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
  bool _repeatMonthly = false;

  /// Whether this entry takes money back out of the holding (a withdrawal /
  /// redemption) rather than adding to it. A withdrawal is stored as a negative
  /// amount so the type's running total falls.
  bool _isWithdrawal = false;

  /// Built-in types plus any custom types the user has already used, with
  /// "Other" always last. Built via [_buildTypes] in initState.
  late final List<String> _types;

  static const List<String> _monthAbbr = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Merges the built-in types with the user's previously entered custom types
  /// so a type only has to be typed once — after that it appears in the
  /// dropdown and can simply be picked.
  List<String> _buildTypes() {
    final base = Investment.builtInTypes
        .where((t) => t != Investment.otherType)
        .toList();
    for (final t in context.read<InvestmentProvider>().usedTypes()) {
      if (t.isNotEmpty && !base.contains(t)) base.add(t);
    }
    base.add(Investment.otherType);
    return base;
  }

  @override
  void initState() {
    super.initState();
    _types = _buildTypes();
    // If the caller passed a known type (built-in or a previously used custom
    // one), start on it; an unknown type starts on "Other" with the value
    // prefilled so it round-trips.
    final initial = widget.initialType;
    if (initial != null &&
        initial != Investment.otherType &&
        _types.contains(initial)) {
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
    final kind = _isWithdrawal ? 'Withdrawal ' : '';
    return '$type $kind${_monthAbbr[_selectedDate.month - 1]} ${_selectedDate.year}';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add Investment')),
      body: SingleChildScrollView(
        padding: scrollPadding(context),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contribution adds to the holding; withdrawal takes money back
              // out and is stored as a negative amount, so the type's total
              // falls (e.g. redeeming part of a mutual fund).
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Contribution'),
                      icon: Icon(Icons.add, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Withdrawal'),
                      icon: Icon(Icons.remove, size: 16),
                    ),
                  ],
                  selected: {_isWithdrawal},
                  onSelectionChanged: (s) => setState(() {
                    _isWithdrawal = s.first;
                    // A withdrawal that repeats is a separate feature; keep the
                    // recurring toggle to contributions (SIPs).
                    if (_isWithdrawal) _repeatMonthly = false;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: _defaultName(),
                ),
                // Name is optional: blank falls back to an auto-generated
                // label like "Silver Jul 2026".
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: _isWithdrawal ? 'Amount to withdraw' : 'Amount',
                  prefixText: '${CurrencyFormat.symbol} ',
                  prefixStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Always a positive magnitude here; the Contribution/Withdrawal
                // toggle decides the sign on save.
                validator: (value) => validateAmountField(value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Date: ${formatDateWithDay(_selectedDate)}'),
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
                    child: const Text('Select Date'),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
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
                      const InputDecoration(labelText: 'Enter investment type'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) =>
                      (_selectedType == Investment.otherType &&
                              (value == null || value.trim().isEmpty))
                          ? 'Enter a type or pick one above'
                          : null,
                ),
              // Only a contribution can repeat as a SIP; a withdrawal is a
              // one-off correction/redemption.
              if (!_isWithdrawal)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repeat monthly (SIP)'),
                  subtitle: const Text(
                      'Automatically log this contribution every month'),
                  value: _repeatMonthly,
                  onChanged: (v) => setState(() => _repeatMonthly = v),
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSaving = true);
                          final type = _resolvedType;
                          final enteredName = _nameController.text.trim();
                          // The field holds a positive magnitude; a withdrawal
                          // is stored negative so the type total drops.
                          final magnitude = rupeesToMinor(
                              double.parse(_amountController.text));
                          final signedAmount =
                              _isWithdrawal ? -magnitude : magnitude;
                          final investment = Investment(
                            name: enteredName.isEmpty
                                ? _defaultName()
                                : enteredName,
                            amount: signedAmount,
                            date: _selectedDate,
                            type: type,
                          );
                          final provider = context.read<InvestmentProvider>();
                          final recurring = context.read<RecurringProvider>();
                          try {
                            await provider.addInvestment(investment);
                            if (_repeatMonthly) {
                              // Anchor to the chosen day-of-month and advance
                              // one month with the same clamping the service
                              // uses when posting, so a 31st start lands on the
                              // last day of a short month instead of overflowing
                              // into the next one (DateTime(y, 2, 31) → Mar 3).
                              final anchorDay = _selectedDate.day;
                              final next = RecurringService.nextDate(
                                  _selectedDate,
                                  DbConstants.freqMonthly,
                                  anchorDay);
                              // A blank name falls back to the instrument type,
                              // not the month-stamped default — otherwise every
                              // future contribution would carry the first
                              // month's label (e.g. "Silver Jul 2026").
                              final ruleName = enteredName.isEmpty
                                  ? (type.isEmpty ? 'Investment' : type)
                                  : enteredName;
                              await recurring.addRule(RecurringRule(
                                description: ruleName,
                                amount: investment.amount,
                                category: type,
                                frequency: DbConstants.freqMonthly,
                                nextDue: next,
                                anchorDay: anchorDay,
                                isInvestment: true,
                              ));
                            }
                            HapticFeedback.lightImpact();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(_isWithdrawal
                                        ? 'Withdrawal recorded'
                                        : 'Investment added')),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')));
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        }
                      },
                child: _isSaving
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(_isWithdrawal
                        ? 'Record Withdrawal'
                        : 'Add Investment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
