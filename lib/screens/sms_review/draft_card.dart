part of '../sms_review_screen.dart';

class _DraftCard extends StatefulWidget {
  final SmsDraft draft;
  final List<Account> accounts;
  final List<String> investmentTypes;
  final VoidCallback onChanged;
  final VoidCallback onDismiss;
  final VoidCallback onShowRaw;

  /// Null hides "Always ignore" (a transfer names no merchant to ignore).
  final VoidCallback? onIgnoreMerchant;

  const _DraftCard({
    super.key,
    required this.draft,
    required this.accounts,
    required this.investmentTypes,
    required this.onChanged,
    required this.onDismiss,
    required this.onShowRaw,
    this.onIgnoreMerchant,
  });

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  /// Whether the user picked "Other" in the investment-type box and is now
  /// typing a value. The dropdown otherwise shows a recalled/preset value
  /// directly.
  bool _investTypeOther = false;

  final _customInvestType = TextEditingController();

  /// The amount in the account's currency, for a foreign charge.
  final _convertedAmount = TextEditingController();

  static const _paymentModes = [
    'Cash', 'Credit Card', 'Debit Card', 'UPI', 'Other', //
  ];

  @override
  void dispose() {
    _customInvestType.dispose();
    _convertedAmount.dispose();
    // The description field's controller belongs to its Autocomplete, which
    // disposes it — nothing to dispose here.
    super.dispose();
  }

  Widget _accountDropdown({
    required String label,
    required int? value,
    required String? errorText,
    required ValueChanged<int?> onChanged,
  }) =>
      DropdownButtonFormField<int?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, errorText: errorText, isDense: true),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('None')),
          ...widget.accounts.map((a) => DropdownMenuItem<int?>(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      );

  /// A dropdown of [options] that reveals a text box when "Other" is picked, so
  /// the user can name a category or an investment type not on the list. The
  /// chosen or typed value is written back through [onValue].
  Widget _pickerWithOther({
    required String label,
    required String current,
    required List<String> options,
    required bool isOther,
    required TextEditingController controller,
    required ValueChanged<bool> onOtherChanged,
    required ValueChanged<String> onValue,
  }) {
    // While typing a custom value the dropdown reads "Other"; otherwise it
    // shows the current value, added to the list if it isn't already there
    // (a category recalled from history the user once typed).
    final items = <String>{...options, if (!isOther) current};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: isOther ? _kOther : current,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: items
              .map((c) => DropdownMenuItem(
                  value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            if (v == _kOther) {
              onOtherChanged(true);
              onValue(controller.text.trim());
            } else {
              onOtherChanged(false);
              onValue(v);
            }
          },
        ),
        if (isOther)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: 'Enter ${label.toLowerCase()}', isDense: true),
              onChanged: (t) => onValue(t.trim()),
            ),
          ),
      ],
    );
  }

  Account? _accountById(int? id) {
    for (final a in widget.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final parsed = draft.parsed;
    // A transfer is neither a gain nor a loss, so it gets neither colour; nor
    // does money being invested, which is still yours.
    final spent = parsed.isExpense || draft.asExpense;
    final amountColor = draft.recordsTransfer || draft.asInvestment
        ? null
        : (spent ? expenseColor(context) : incomeColor(context));
    final sign = draft.asInvestment
        ? '−'
        : (draft.recordsTransfer ? '' : (spent ? '−' : '+'));
    // A message that named an account we could not resolve is the case most
    // likely to be filed wrongly, so it is called out rather than left to be
    // noticed in the dropdown. An investment is paid from an account too.
    final unmatchedLast4 = parsed.last4 != null && draft.accountId == null;
    final unmatchedText = draft.sameLast4Count > 1
        ? '${draft.sameLast4Count} accounts end in ••${parsed.last4} — pick one'
        : 'No account with ••${parsed.last4}';
    final account = _accountById(draft.accountId);
    // A charge quoted in another currency than the account's own needs the
    // converted figure, which only the bank's statement will show.
    final foreign =
        (!parsed.isTransfer || draft.asExpense) && draft.isForeignFor(account);
    final accountSymbol = account?.symbol ?? CurrencyFormat.symbol;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: draft.selected,
                  onChanged: (v) {
                    draft.selected = v ?? false;
                    widget.onChanged();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Editable: the parsed merchant/sender is only a guess,
                      // so the user can give the row a name they recognise
                      // before it is posted. When this row is being recorded as
                      // an investment the field also suggests the holdings you
                      // already track under the chosen type — so a mutual fund
                      // added before (e.g. "Nifty 50") is picked from the list
                      // instead of retyped, matching the Add Investment screen.
                      Autocomplete<String>(
                        initialValue: TextEditingValue(text: draft.description),
                        optionsBuilder: (value) {
                          if (!draft.asInvestment) {
                            return const Iterable<String>.empty();
                          }
                          final names = context
                              .read<InvestmentProvider>()
                              .usedNames(type: draft.investmentType);
                          final query = value.text.trim().toLowerCase();
                          if (query.isEmpty) return names;
                          return names
                              .where((n) => n.toLowerCase().contains(query));
                        },
                        onSelected: (v) {
                          draft.description = v;
                          widget.onChanged();
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onSubmitted) {
                          // The Autocomplete owns and disposes this controller.
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.only(bottom: 2),
                              hintText: 'Description',
                            ),
                            onChanged: (v) => draft.description = v,
                            onSubmitted: (_) => onSubmitted(),
                          );
                        },
                      ),
                      Text(
                        '${formatShortDate(parsed.date)} · ${parsed.sender}'
                        '${parsed.last4 != null ? ' · ••${parsed.last4}' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: mutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$sign${parsed.currency == CurrencyFormat.symbol ? formatMoney(parsed.amount) : formatMoneyIn(parsed.currency, parsed.amount)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: amountColor),
                ),
              ],
            ),
            // The first decision on a debit, so it leads the card: what this
            // money was. Investment keeps it out of spending and budgets and
            // files it in the investments ledger instead.
            if (draft.canBeInvestment)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
                child: SizedBox(
                  width: double.infinity,
                  // A transfer can also be money sent to someone else — family,
                  // a friend — which is spending, so it gets all three.
                  child: SegmentedButton<_RecordAs>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    segments: [
                      if (parsed.isTransfer)
                        const ButtonSegment(
                            value: _RecordAs.transfer,
                            label: Text('Transfer'),
                            icon: Icon(Icons.swap_horiz, size: 16)),
                      if (!parsed.isTransfer || draft.canBeExpense)
                        const ButtonSegment(
                            value: _RecordAs.expense,
                            label: Text('Expense'),
                            icon: Icon(Icons.remove_circle_outline, size: 16)),
                      const ButtonSegment(
                          value: _RecordAs.investment,
                          label: Text('Investment'),
                          icon: Icon(Icons.trending_up, size: 16)),
                    ],
                    selected: {
                      draft.asInvestment
                          ? _RecordAs.investment
                          : (draft.recordsTransfer
                              ? _RecordAs.transfer
                              : _RecordAs.expense)
                    },
                    onSelectionChanged: (s) {
                      setState(() {
                        draft.asInvestment = s.first == _RecordAs.investment;
                        if (draft.canBeExpense) {
                          draft.setAsExpense(s.first == _RecordAs.expense);
                        }
                        // Switching by hand: start from the type the name
                        // suggests rather than always "Stocks".
                        if (draft.asInvestment &&
                            draft.investmentSuggestion ==
                                InvestmentSuggestion.none) {
                          draft.investmentType = InvestmentMerchants.guessType(
                                  draft.parsed.description) ??
                              draft.investmentType;
                        }
                      });
                      widget.onChanged();
                    },
                  ),
                ),
              ),
            if (draft.duplicateOf != null)
              _Notice(
                icon: Icons.content_copy,
                color: warningColor(context),
                text: 'Looks like "${draft.duplicateOf!.description}", which '
                    'you already entered. Left unchecked.',
              ),
            if (draft.isCardPayment)
              _Notice(
                icon: Icons.credit_score,
                color: transferColor(context),
                text: 'A credit card bill payment — recorded as a transfer '
                    'from your bank to the card, so it isn\'t counted as '
                    'spending or income.',
              )
            else if (draft.recordsTransfer)
              _Notice(
                icon: Icons.swap_horiz,
                color: transferColor(context),
                text: 'Money moved between your accounts — recorded as a '
                    'transfer, so it is not counted as spending. Sent to '
                    'someone else? Switch to Expense.',
              )
            else if (parsed.isTransfer &&
                draft.asExpense &&
                !draft.asInvestment)
              _Notice(
                icon: Icons.person_outline,
                color: mutedTextColor(context),
                text: 'Sent to an account that isn\'t yours — recorded as '
                    'spending. Switch to Transfer if it\'s one of your own.',
              ),
            if (draft.isRefund)
              _Notice(
                icon: Icons.assignment_return,
                color: incomeColor(context),
                text: 'A refund — taken off ${draft.category}\'s spending '
                    'rather than counted as income.',
              ),
            if (foreign)
              _Notice(
                icon: Icons.currency_exchange,
                color: warningColor(context),
                text: 'Charged in ${parsed.currency}. Enter what it cost in '
                    '$accountSymbol — it\'s on your statement.',
              ),
            if (draft.asInvestment)
              _Notice(
                icon: draft.investmentSuggestion ==
                        InvestmentSuggestion.remembered
                    ? Icons.history
                    : Icons.trending_up,
                color: mutedTextColor(context),
                text: switch (draft.investmentSuggestion) {
                  InvestmentSuggestion.remembered =>
                    'Imported as an investment last time — added to '
                        '${draft.investmentType}, not counted as spending.',
                  InvestmentSuggestion.guessed =>
                    'Looks like an investment (${draft.investmentType}) from '
                        'the merchant name — not counted as spending. Switch '
                        'to Expense if it isn\'t.',
                  InvestmentSuggestion.none =>
                    'Added to your investments, not counted as spending.',
                },
              ),
            if (draft.recalledCategory != null && !draft.asInvestment)
              _Notice(
                icon: Icons.history,
                color: mutedTextColor(context),
                text: 'Filed as ${draft.recalledCategory} last time.',
              )
            else if (draft.guessedCategory != null &&
                !draft.asInvestment &&
                draft.category == draft.guessedCategory)
              _Notice(
                icon: Icons.lightbulb_outline,
                color: mutedTextColor(context),
                text: 'Category guessed from the merchant name.',
              ),
            // Offered only when the history says this charge repeats monthly and
            // the draft is still a plain expense (an investment isn't modelled
            // as a recurring rule).
            if (draft.recurringSuggested &&
                parsed.isExpense &&
                !draft.asInvestment)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: draft.createRecurring,
                        onChanged: (v) {
                          setState(() => draft.createRecurring = v ?? false);
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Looks like a monthly subscription — also create a '
                        'recurring rule.',
                        style: TextStyle(
                            fontSize: 12, color: mutedTextColor(context)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: draft.asInvestment
                  // An investment has no category: the account it was paid
                  // from (whose balance it leaves) and the instrument instead.
                  ? Row(
                      // Keyed apart from the expense row of the same shape, so
                      // switching never hands the category dropdown's state to
                      // the investment-type one.
                      key: const ValueKey('investment-fields'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _accountDropdown(
                            label: 'Paid from',
                            value: draft.accountId,
                            errorText: unmatchedLast4 ? unmatchedText : null,
                            onChanged: (v) {
                              draft.accountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _pickerWithOther(
                            label: 'Investment type',
                            current: draft.investmentType,
                            options: widget.investmentTypes,
                            isOther: _investTypeOther,
                            controller: _customInvestType,
                            onOtherChanged: (v) =>
                                setState(() => _investTypeOther = v),
                            onValue: (v) {
                              draft.investmentType = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _accountDropdown(
                            label: draft.recordsTransfer ? 'From' : 'Account',
                            value: draft.accountId,
                            errorText: unmatchedLast4
                                ? unmatchedText
                                : (draft.needsSource
                                    ? 'Pick the account you paid from'
                                    : null),
                            onChanged: (v) {
                              draft.accountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          // A transfer needs the receiving account instead of a
                          // category; its category is fixed at "Transfer".
                          child: draft.recordsTransfer
                              ? _accountDropdown(
                                  label: 'To',
                                  value: draft.toAccountId,
                                  errorText: draft.needsDestination
                                      ? (parsed.toLast4 != null
                                          ? 'No account with ••${parsed.toLast4}'
                                          : (draft.isCardPayment
                                              ? 'Pick the card you paid'
                                              : 'Pick the receiving account'))
                                      : null,
                                  onChanged: (v) {
                                    draft.toAccountId = v;
                                    widget.onChanged();
                                  },
                                )
                              // The same picker as Add Expense, so an import
                              // files under the user's own categories.
                              : CategoryPickerTile(
                                  type: draft.usesExpenseCategories
                                      ? DbConstants.txExpense
                                      : DbConstants.txIncome,
                                  label: 'Category',
                                  dense: true,
                                  value: draft.category,
                                  onChanged: (v) {
                                    draft.category = v;
                                    widget.onChanged();
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
            if (foreign || (draft.usesExpenseCategories && !draft.asInvestment))
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (foreign)
                      Expanded(
                        child: TextField(
                          controller: _convertedAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Amount in $accountSymbol',
                            isDense: true,
                            errorText:
                                draft.needsAmountFor(account) && draft.selected
                                    ? 'Required'
                                    : null,
                          ),
                          onChanged: (t) {
                            final minor = parseMinor(t.trim());
                            draft.amountOverride =
                                minor != null && minor > 0 ? minor : null;
                            // Entering the amount is what the unticked row
                            // was waiting for.
                            if (draft.amountOverride != null) {
                              draft.selected = true;
                            }
                            widget.onChanged();
                          },
                        ),
                      ),
                    if (foreign &&
                        draft.usesExpenseCategories &&
                        !draft.asInvestment)
                      const SizedBox(width: 12),
                    if (draft.usesExpenseCategories && !draft.asInvestment)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _paymentModes.contains(draft.paymentMode)
                                  ? draft.paymentMode
                                  : 'Other',
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Payment mode', isDense: true),
                          items: [
                            for (final m in _paymentModes)
                              DropdownMenuItem(value: m, child: Text(m)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            draft.paymentMode = v;
                            widget.onChanged();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('Message'),
                  onPressed: widget.onShowRaw,
                ),
                if (widget.onIgnoreMerchant != null)
                  TextButton.icon(
                    icon: const Icon(Icons.block, size: 16),
                    label: const Text('Always ignore'),
                    onPressed: widget.onIgnoreMerchant,
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Dismiss'),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What an SMS draft is recorded as, picked on its card.
enum _RecordAs { transfer, expense, investment }
