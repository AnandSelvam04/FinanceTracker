import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../models/category_rule.dart';
import '../models/expense.dart';
import '../models/tx_template.dart';
import '../services/category_rules.dart';
import '../services/db_service.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_scanner.dart';
import '../services/receipt_store.dart';
import '../services/voice_expense_parser.dart';
import '../utils/app_colors.dart';
import '../utils/app_logger.dart';
import '../utils/category_store.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_choice_chip.dart' show isSameCategory;
import '../widgets/amount_calculator_bar.dart';
import '../widgets/category_picker.dart';
import '../widgets/date_field_row.dart';
import '../widgets/spend_account_picker.dart';
import '../widgets/voice_capture_sheet.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';
import '../utils/error_message.dart';

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

  /// Opens with this account (a credit card, say) chosen, for adding a spend
  /// an SMS alert missed.
  final int? initialAccountId;

  const AddExpenseScreen({
    super.key,
    this.autoStart = AddExpenseAction.none,
    this.duplicateOf,
    this.initialAccountId,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountFocus = FocusNode();
  DateTime _selectedDate = DateTime.now();
  String _selectedPaymentMode = 'Cash';
  String _txType = DbConstants.txExpense;
  int? _accountId;
  bool _isSaving = false;
  bool _isScanning = false;

  /// The scanned (or attached) bill photo, kept with the transaction when it
  /// is saved. A temporary path until then.
  String? _receiptPhoto;
  bool _saveAsTemplate = false;

  /// The auto-categorise rule that chose the category, while the category is
  /// still its choice. A category the user picks clears it.
  CategoryRule? _rule;
  List<String> _frequentExpenseCategories = const [];
  List<String> _frequentIncomeCategories = const [];

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
      // A refund is stored negative; its copy starts as a spend of that size.
      _amountController.text = minorToEditString(copy.amount.abs());
      _descriptionController.text = copy.description;
      _noteController.text = copy.note ?? '';
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
    _cleanState = _formState;
    for (final c in [
      _amountController,
      _descriptionController,
      _noteController
    ]) {
      c.addListener(_onEdited);
    }
    _descriptionController.addListener(_applyRule);
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
      final initial = widget.initialAccountId;
      if (copy == null &&
          initial != null &&
          provider.accountById(initial) != null) {
        setState(() => _selectAccount(initial));
      } else if (copy == null &&
          defaultId != null &&
          context.read<AccountProvider>().accountById(defaultId) != null) {
        setState(() => _selectAccount(defaultId));
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
    _noteController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  bool get _isIncome => _txType == DbConstants.txIncome;

  /// Whether the category on show is still the one [_rule] chose.
  bool get _filedByRule =>
      _rule != null &&
      isSameCategory(_categoryController.text, _rule!.category);

  /// Files the transaction by the first rule matching its description, as it
  /// is typed (or filled in by a scan). Never replaces a category the user
  /// picked, or one a copy or voice entry brought in; and takes back one it
  /// set itself once the description no longer matches.
  void _applyRule() {
    final current = _categoryController.text.trim();
    if (current.isNotEmpty && !_filedByRule) return;
    final rule = CategoryRuleStore.instance
        .firstMatch(_descriptionController.text, _txType);
    if (rule?.id == _rule?.id && (rule == null || _filedByRule)) return;
    final hadRule = _rule != null;
    setState(() {
      _rule = rule;
      if (rule != null) {
        _categoryController.text = rule.category;
      } else if (hadRule) {
        _categoryController.clear();
      }
    });
  }

  /// The payment mode an account of [type] implies, or null when it doesn't
  /// pin one down (a bank account may be a debit card, UPI, or a transfer).
  static String? _paymentModeFor(String? type) => switch (type) {
        'cash' => 'Cash',
        'credit_card' => 'Credit Card',
        'upi' => 'UPI',
        _ => null,
      };

  /// Selects [id] as the account and lines the payment mode up with it, so
  /// choosing a credit card no longer leaves the expense filed as "Cash".
  void _selectAccount(int? id) {
    _accountId = id;
    final mode =
        _paymentModeFor(context.read<AccountProvider>().accountById(id)?.type);
    if (mode != null) _selectedPaymentMode = mode;
  }

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

  /// Recent categories first, then the user's own and the built-in ones, de-duplicated
  /// ignoring case — so a past "food" entry and the built-in "Food" show as
  /// one chip, not two.
  List<String> get _suggestions {
    final frequent =
        _isIncome ? _frequentIncomeCategories : _frequentExpenseCategories;
    // The user's own categories, then the built-in ones they kept.
    final offered = CategoryStore.instance.offered(_txType);
    final seen = <String>{};
    return [
      for (final c in [...frequent, ...offered])
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

  /// The description to save: what was typed, or the category when blank.
  String get _resolvedDescription {
    final typed = _descriptionController.text.trim();
    return typed.isEmpty ? _resolvedCategory : typed;
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
    ({ParsedReceipt receipt, String imagePath})? result;
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
    setState(() => _receiptPhoto = result!.imagePath);
    _applyReceipt(result.receipt, messenger);
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
    final accounts = accountProvider.pickable([_accountId]);
    final categorySuggestions = _suggestions;
    // The amount is stored in the chosen account's currency, so label it with
    // that currency — a USD account showed "₹", inviting a rupee figure that
    // was then booked as dollars.
    final amountSymbol = accountProvider.accountById(_accountId)?.symbol ??
        CurrencyFormat.symbol;

    // Leaving with something typed in (a scanned receipt, say) asks first.
    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard() || !context.mounted) return;
        _cleanState = _formState;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.duplicateOf != null
                ? (_isIncome ? 'Duplicate income' : 'Duplicate expense')
                : (_isIncome ? 'Add income' : 'Add expense'))),
        // The form scrolls; the save button stays put beneath it (and above
        // the keyboard, as the body shrinks to make room for it). At the end
        // of the form it was a scroll away on every entry.
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.lg),
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
                              _rule = null;
                            });
                            _applyRule();
                          },
                        ),
                      ),
                      const SizedBox(height: Space.lg),
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
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5),
                                    )
                                  : const Icon(Icons.document_scanner_outlined),
                              label: Text(
                                  _isScanning ? 'Scanning…' : 'Scan receipt'),
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isScanning ? null : _addByVoice,
                              icon: const Icon(Icons.mic_none),
                              label: const Text('Speak'),
                            ),
                          ),
                        ],
                      ),
                      if (_receiptPhoto != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.md),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(Radii.sm),
                                child: Image.file(File(_receiptPhoto!),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.receipt_long,
                                        size: 40)),
                              ),
                              const SizedBox(width: Space.md),
                              const Expanded(
                                  child: Text(
                                      'Receipt photo will be kept with this '
                                      'transaction')),
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Don\'t keep the photo',
                                onPressed: () =>
                                    setState(() => _receiptPhoto = null),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: Space.lg),
                      // The amount is the focal input, so it is enlarged and carries
                      // the configured currency symbol as a prefix.
                      TextFormField(
                        controller: _amountController,
                        focusNode: _amountFocus,
                        // The keyboard is up for the amount straight away; not
                        // when a scan or voice capture opens over the form.
                        autofocus: widget.autoStart == AddExpenseAction.none,
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: '$amountSymbol ',
                          prefixStyle: TextStyle(
                            fontSize: FontSizes.display,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        style: const TextStyle(
                            fontSize: FontSizes.display,
                            fontWeight: FontWeight.bold),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        validator: validateAmountField,
                      ),
                      const SizedBox(height: Space.sm),
                      AmountCalculatorBar(controller: _amountController),
                      const SizedBox(height: Space.md),
                      TextFormField(
                        controller: _descriptionController,
                        // Optional: a blank description saves as the category, so a
                        // quick "250, Food" entry needs no extra typing.
                        decoration: const InputDecoration(
                            labelText: 'Description (optional)'),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: Space.xs),
                      DateFieldRow(
                        date: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        onChanged: (d) => setState(() => _selectedDate = d),
                      ),
                      const SizedBox(height: Space.xs),
                      const SizedBox(height: Space.sm),
                      // Picked, not typed: a typo in a free-text field used to start
                      // a second category. "More" lists them all and adds new ones.
                      FormField<String>(
                        validator: (_) =>
                            _categoryController.text.trim().isEmpty
                                ? (_isIncome
                                    ? 'Choose a source'
                                    : 'Choose a category')
                                : null,
                        builder: (field) => CategoryPickerField(
                          type: _txType,
                          value: _categoryController.text,
                          suggestions: categorySuggestions,
                          errorText: field.errorText,
                          onChanged: (c) {
                            setState(() {
                              _categoryController.text = c;
                              // Picked by hand: no longer the rule's choice.
                              if (!_filedByRule) _rule = null;
                            });
                            field.didChange(c);
                            if (field.hasError) field.validate();
                          },
                        ),
                      ),
                      if (_filedByRule)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Row(
                            children: [
                              Icon(Icons.auto_fix_high,
                                  size: 16, color: mutedTextColor(context)),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                child: Text(
                                  'Set by your rule: ${_rule!.condition}'
                                  '${_rule!.tag == null ? '' : ' · adds #${_rule!.tag}'}',
                                  style: TextStyle(
                                      fontSize: FontSizes.caption,
                                      color: mutedTextColor(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!_isIncome) ...[
                        const SizedBox(height: Space.lg),
                        Text('Payment mode',
                            style: TextStyle(
                                fontSize: FontSizes.caption,
                                color: mutedTextColor(context))),
                        const SizedBox(height: Space.sm),
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
                              onSelected: (_) => setState(() {
                                _selectedPaymentMode = p;
                                // "Credit Card" asks which card; leaving it drops a
                                // card account the spend no longer went on.
                                _accountId = SpendAccountPicker.accountForMode(
                                    p, _accountId, accounts,
                                    fallbackId: context
                                        .read<SettingsProvider>()
                                        .defaultAccountId);
                              }),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: Space.xs),
                      ],
                      if (accounts.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        SpendAccountPicker(
                          accounts: accounts,
                          accountId: _accountId,
                          // Income has no payment mode, so no card row.
                          paymentMode:
                              _isIncome ? 'Other' : _selectedPaymentMode,
                          onChanged: (id, mode) => setState(() {
                            _accountId = id;
                            if (!_isIncome) _selectedPaymentMode = mode;
                          }),
                        ),
                      ],
                      const SizedBox(height: Space.sm),
                      TextFormField(
                        controller: _noteController,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'e.g. split with Ravi, warranty till 2028',
                          helperText:
                              'Add #tags to group spending, e.g. #goa-trip',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Save as quick-add template'),
                        value: _saveAsTemplate,
                        onChanged: (v) =>
                            setState(() => _saveAsTemplate = v ?? false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg,
                  safeBottom(context, extra: Space.md)),
              child: Row(
                children: [
                  // Several receipts in a row: save this one and start the
                  // next, keeping the date, type and account.
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed:
                            _isSaving ? null : () => _save(addAnother: true),
                        child: const Text('Save & add another',
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            _isSaving ? null : () => _save(addAnother: false),
                        child: _isSaving
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : Text(_isIncome ? 'Add income' : 'Add expense'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the form. With [addAnother] the form stays open and clears for
  /// the next transaction, keeping its date, type and account; otherwise it
  /// closes. Either way the message offers Undo.
  Future<void> _save({required bool addAnother}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    String? attachment;
    if (_receiptPhoto != null) {
      try {
        attachment = await ReceiptStore.save(_receiptPhoto!);
      } catch (e, st) {
        AppLogger.error('Could not keep the receipt photo', e, st);
      }
    }
    if (!mounted) return;
    final amount = parseMinor(_amountController.text)!;
    final expense = Expense(
      attachment: attachment,
      description: _resolvedDescription,
      amount: amount,
      date: _selectedDate,
      category: _resolvedCategory,
      paymentMode: _isIncome ? 'Other' : _selectedPaymentMode,
      type: _txType,
      accountId: _accountId,
      note: CategoryRules.noteWithTag(
          _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          _filedByRule ? _rule!.tag : null),
    );
    final provider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final templateProvider = context.read<TemplateProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await provider.addExpense(expense);
      await accountProvider.refreshBalances();
      if (_saveAsTemplate) {
        await templateProvider.addTemplate(TxTemplate(
          name: _resolvedDescription,
          description: _resolvedDescription,
          amount: amount,
          category: _resolvedCategory,
          type: _txType,
          accountId: _accountId,
          paymentMode: _isIncome ? null : _selectedPaymentMode,
        ));
      }
      unawaited(HapticFeedback.lightImpact());
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${_isIncome ? 'Income' : 'Expense'} added: ${formatMoney(amount)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await provider.deleteExpense(id);
            await accountProvider.refreshBalances();
          },
        ),
      ));
      if (!mounted) return;
      if (addAnother) {
        setState(() {
          _amountController.clear();
          _descriptionController.clear();
          _noteController.clear();
          _receiptPhoto = null;
          _saveAsTemplate = false;
          _formKey.currentState!.reset();
        });
        _cleanState = _formState;
        _amountFocus.requestFocus();
      } else {
        _cleanState = _formState;
        Navigator.pop(context);
      }
    } catch (e, st) {
      messenger.showSnackBar(SnackBar(
        content: Text(friendlyError("Couldn't save the transaction", e, st)),
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// What the user has typed, to tell whether leaving would lose anything.
  String get _formState => [
        _amountController.text.trim(),
        _descriptionController.text.trim(),
        _noteController.text.trim(),
        _receiptPhoto ?? '',
      ].join('\u0000');

  /// [_formState] as the form opened (a duplicate arrives filled in) or as
  /// last saved.
  late String _cleanState;

  bool get _isDirty => _formState != _cleanState;

  bool _wasDirty = false;

  /// Rebuilds when typing first makes the form unsaved (or clears it), so
  /// Back knows whether to ask.
  void _onEdited() {
    if (_isDirty != _wasDirty && mounted) {
      setState(() => _wasDirty = _isDirty);
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this transaction?'),
        content: const Text('What you have entered will not be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return discard == true;
  }
}
