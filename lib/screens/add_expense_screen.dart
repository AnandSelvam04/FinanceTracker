import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../models/expense.dart';
import '../models/tx_template.dart';
import '../services/db_service.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_scanner.dart';
import '../services/voice_expense_parser.dart';
import '../utils/app_colors.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_choice_chip.dart';
import '../widgets/date_field_row.dart';
import '../widgets/voice_capture_sheet.dart';

/// An optional capture flow to launch as soon as the screen opens, so the
/// dashboard can offer "Scan receipt" / "Add by voice" as direct shortcuts.
enum AddExpenseAction { none, scan, voice }

class AddExpenseScreen extends StatefulWidget {
  final AddExpenseAction autoStart;

  /// An existing transaction to copy: the form opens filled with its amount,
  /// description, category, type, account, and payment mode, dated today so
  /// the date is the one thing usually changed. Nothing is saved until the
  /// user taps Add.
  final Expense? duplicateOf;

  const AddExpenseScreen({
    super.key,
    this.autoStart = AddExpenseAction.none,
    this.duplicateOf,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedPaymentMode = 'Cash';
  String _txType = DbConstants.txExpense;
  int? _accountId;
  bool _isSaving = false;
  bool _isScanning = false;
  bool _saveAsTemplate = false;
  List<String> _frequentExpenseCategories = const [];
  List<String> _frequentIncomeCategories = const [];

  final List<String> _expenseCategories = const [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Entertainment',
    'Health',
    'Education',
    'Other',
  ];

  final List<String> _incomeCategories = const [
    'Salary',
    'Business',
    'Interest',
    'Dividends',
    'Gift',
    'Refund',
    'Other',
  ];

  final List<String> _paymentModes = [
    'Cash',
    'Credit Card',
    'Debit Card',
    'UPI',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    final copy = widget.duplicateOf;
    if (copy != null) {
      _txType = copy.isIncome ? DbConstants.txIncome : DbConstants.txExpense;
      _amountController.text = minorToEditString(copy.amount);
      _descriptionController.text = copy.description;
      _categoryController.text = copy.category;
      // Only keep an account that still exists: a dropdown whose value
      // matches no item throws. If accounts aren't loaded yet, the check
      // after the first frame covers it.
      final accounts = context.read<AccountProvider>();
      if (accounts.accounts.isEmpty ||
          accounts.accountById(copy.accountId) != null) {
        _accountId = copy.accountId;
      }
      if (_paymentModes.contains(copy.paymentMode)) {
        _selectedPaymentMode = copy.paymentMode;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AccountProvider>();
      if (provider.accounts.isEmpty) {
        await provider.fetchAccounts();
        if (!mounted) return;
      }
      // A copied account that has since been deleted would match no dropdown
      // item; fall back to none.
      if (_accountId != null && provider.accountById(_accountId) == null) {
        setState(() => _accountId = null);
      }
      // Preselect the user's default account, if set and still present —
      // unless this is a copy, which keeps the original's account.
      final defaultId = context.read<SettingsProvider>().defaultAccountId;
      if (copy == null &&
          defaultId != null &&
          context.read<AccountProvider>().accountById(defaultId) != null) {
        setState(() => _accountId = defaultId);
      }
      final expenseFreq =
          await DBService().frequentCategories(DbConstants.txExpense);
      final incomeFreq =
          await DBService().frequentCategories(DbConstants.txIncome);
      if (mounted) {
        setState(() {
          _frequentExpenseCategories = expenseFreq;
          _frequentIncomeCategories = incomeFreq;
        });
      }
      // Launch a requested capture flow once the form (and its category
      // suggestions, which voice matching uses) is ready.
      if (!mounted) return;
      if (widget.autoStart == AddExpenseAction.scan) {
        await _scanReceipt();
      } else if (widget.autoStart == AddExpenseAction.voice) {
        await _addByVoice();
      }
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  bool get _isIncome => _txType == DbConstants.txIncome;

  static IconData _paymentIcon(String mode) {
    switch (mode) {
      case 'Cash':
        return Icons.payments_outlined;
      case 'Credit Card':
        return Icons.credit_card;
      case 'Debit Card':
        return Icons.credit_card_outlined;
      case 'UPI':
        return Icons.qr_code_2;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  /// Recent categories first, then built-in defaults, de-duplicated
  /// ignoring case — so a past "food" entry and the built-in "Food" show as
  /// one chip, not two.
  List<String> get _suggestions {
    final frequent =
        _isIncome ? _frequentIncomeCategories : _frequentExpenseCategories;
    final defaults = _isIncome ? _incomeCategories : _expenseCategories;
    final seen = <String>{};
    return [
      for (final c in [...frequent, ...defaults])
        if (seen.add(c.trim().toLowerCase())) c,
    ];
  }

  /// The category to save: the typed text trimmed, spelled like an existing
  /// suggestion when it names one, so typing "food" files under "Food"
  /// instead of starting a second, separate category.
  String get _resolvedCategory {
    final typed = _categoryController.text.trim();
    for (final c in _suggestions) {
      if (isSameCategory(typed, c)) return c;
    }
    return typed;
  }

  // --- Receipt scanning ------------------------------------------------------

  /// Asks whether to use the camera or the gallery, then runs OCR and pre-fills
  /// the form. Nothing is saved; the user still reviews and taps Add.
  Future<void> _scanReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isScanning = true);
    ParsedReceipt? result;
    try {
      result = await ReceiptScanner.scan(source);
    } catch (e, st) {
      AppLogger.error('Receipt scan failed', e, st);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read the receipt.')),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
    if (!mounted || result == null) return;
    _applyReceipt(result, messenger);
  }

  void _applyReceipt(ParsedReceipt r, ScaffoldMessengerState messenger) {
    if (r.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't find an amount on the receipt. "
              'Enter the details by hand.')));
      return;
    }
    setState(() {
      // A scanned bill is always a spend.
      _txType = DbConstants.txExpense;
      if (r.amountMinor != null) {
        _amountController.text = minorToEditString(r.amountMinor!);
      }
      if (r.merchant != null && r.merchant!.isNotEmpty) {
        _descriptionController.text = r.merchant!;
      }
      if (r.date != null) {
        // Ignore a future date read in error; the picker caps at today anyway.
        if (!r.date!.isAfter(DateTime.now())) _selectedDate = r.date!;
      }
    });
    final filled = <String>[
      if (r.amountMinor != null) 'amount',
      if (r.merchant != null) 'merchant',
      if (r.date != null) 'date',
    ];
    messenger.showSnackBar(SnackBar(
      content: Text('Scanned ${filled.join(', ')}. Review and add.'),
    ));
  }

  // --- Voice entry -----------------------------------------------------------

  /// Opens the mic sheet, interprets the spoken sentence, and pre-fills the
  /// form. Nothing is saved automatically.
  Future<void> _addByVoice() async {
    final transcript = await showVoiceCaptureSheet(context);
    if (!mounted || transcript == null || transcript.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final parsed = VoiceExpenseParser.parse(
      transcript,
      knownCategories: _suggestions,
    );
    if (parsed.isEmpty) {
      messenger.showSnackBar(SnackBar(
          content: Text('Heard "$transcript" but could not read an amount.')));
      return;
    }
    setState(() {
      _txType = parsed.type;
      if (parsed.amountMinor != null) {
        _amountController.text = minorToEditString(parsed.amountMinor!);
      }
      if (parsed.category != null) _categoryController.text = parsed.category!;
      if (parsed.description != null && parsed.description!.isNotEmpty) {
        _descriptionController.text = parsed.description!;
      } else if (_descriptionController.text.isEmpty &&
          parsed.category != null) {
        _descriptionController.text = parsed.category!;
      }
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('Filled from voice. Review and add.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountProvider = context.watch<AccountProvider>();
    final accounts = accountProvider.accounts;
    final categorySuggestions = _suggestions;
    // The amount is stored in the chosen account's currency, so label it with
    // that currency — a USD account showed "₹", inviting a rupee figure that
    // was then booked as dollars.
    final amountSymbol = accountProvider.accountById(_accountId)?.symbol ??
        CurrencyFormat.symbol;

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.duplicateOf != null
              ? (_isIncome ? 'Duplicate Income' : 'Duplicate Expense')
              : (_isIncome ? 'Add Income' : 'Add Expense'))),
      body: SingleChildScrollView(
        padding: scrollPadding(context),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: DbConstants.txExpense,
                      label: const Text('Expense'),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    ButtonSegment(
                      value: DbConstants.txIncome,
                      label: const Text('Income'),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                  selected: {_txType},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _txType = selection.first;
                      _categoryController.clear();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Quick-capture shortcuts: read a bill photo, or dictate the
              // transaction. Both only pre-fill the fields below.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isScanning ? null : _scanReceipt,
                      icon: _isScanning
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Icon(Icons.document_scanner_outlined),
                      label: Text(_isScanning ? 'Scanning…' : 'Scan receipt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isScanning ? null : _addByVoice,
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Speak'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // The amount is the focal input, so it is enlarged and carries
              // the configured currency symbol as a prefix.
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '$amountSymbol ',
                  prefixStyle: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                validator: validateAmountField,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value!.isEmpty ? 'Enter a description' : null,
              ),
              const SizedBox(height: 4),
              DateFieldRow(
                date: _selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                onChanged: (d) => setState(() => _selectedDate = d),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                    labelText: _isIncome ? 'Source' : 'Category'),
                textInputAction: TextInputAction.next,
                validator: (value) => value!.trim().isEmpty
                    ? (_isIncome ? 'Enter a source' : 'Enter a category')
                    : null,
                // Rebuild as the user types so the matching chip below lights
                // up; without it the chips only reflected taps.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: categorySuggestions
                    .map((c) => CategoryChoiceChip(
                          category: c,
                          selected: isSameCategory(_categoryController.text, c),
                          onSelected: () =>
                              setState(() => _categoryController.text = c),
                        ))
                    .toList(),
              ),
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null, child: const Text('None')),
                    ...accounts.map((a) => DropdownMenuItem<int?>(
                        value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              ],
              if (!_isIncome) ...[
                const SizedBox(height: 16),
                Text('Payment mode',
                    style: TextStyle(
                        fontSize: 12, color: mutedTextColor(context))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _paymentModes.map((p) {
                    return ChoiceChip(
                      avatar: Icon(_paymentIcon(p), size: 18),
                      label: Text(p),
                      selected: _selectedPaymentMode == p,
                      // The checkmark replaces the avatar, hiding the icon.
                      showCheckmark: false,
                      onSelected: (_) =>
                          setState(() => _selectedPaymentMode = p),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Save as quick-add template'),
                value: _saveAsTemplate,
                onChanged: (v) => setState(() => _saveAsTemplate = v ?? false),
              ),
              const SizedBox(height: 16),
              // Full width, filled: the screen's one primary action. As an
              // FilledButton in a start-aligned column it shrank to its label
              // at the left edge, and the white saving spinner vanished on its
              // light fill.
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() => _isSaving = true);
                            final expense = Expense(
                              description: _descriptionController.text,
                              amount: rupeesToMinor(
                                  double.parse(_amountController.text)),
                              date: _selectedDate,
                              category: _resolvedCategory,
                              paymentMode:
                                  _isIncome ? 'Other' : _selectedPaymentMode,
                              type: _txType,
                              accountId: _accountId,
                            );
                            final provider = context.read<ExpenseProvider>();
                            final accountProvider =
                                context.read<AccountProvider>();
                            final templateProvider =
                                context.read<TemplateProvider>();
                            try {
                              await provider.addExpense(expense);
                              await accountProvider.refreshBalances();
                              if (_saveAsTemplate) {
                                await templateProvider.addTemplate(TxTemplate(
                                  name: _descriptionController.text,
                                  description: _descriptionController.text,
                                  amount: rupeesToMinor(
                                      double.parse(_amountController.text)),
                                  category: _resolvedCategory,
                                  type: _txType,
                                  accountId: _accountId,
                                ));
                              }
                              HapticFeedback.lightImpact();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(_isIncome
                                          ? 'Income added'
                                          : 'Expense added')),
                                );
                                Navigator.pop(context);
                              }
                            } catch (e, st) {
                              // Show the error in a SnackBar and log
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text('Failed to save: $e'),
                                ));
                              }
                              AppLogger.error('Error saving expense', e, st);
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
                      : Text(_isIncome ? 'Add Income' : 'Add Expense'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
