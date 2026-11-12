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

  /// The message was dismissed before and is shown again on request.
  final bool dismissedEarlier;

  const _DraftCard({
    super.key,
    required this.draft,
    required this.accounts,
    required this.investmentTypes,
    required this.onChanged,
    required this.onDismiss,
    required this.onShowRaw,
    this.onIgnoreMerchant,
    this.dismissedEarlier = false,
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

  static final _actionStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
    minimumSize: const Size(0, 36),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

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
    required bool flagged,
    required ValueChanged<int?> onChanged,
  }) =>
      DropdownButtonFormField<int?>(
        initialValue: value,
        isExpanded: true,
        // Marked in the error colour only: what is wrong is spelled out in a
        // notice across the card, where it isn't cut off at half its width.
        decoration: InputDecoration(
            labelText: label,
            error: flagged ? const SizedBox.shrink() : null,
            isDense: true),
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
            padding: const EdgeInsets.only(top: Space.xs),
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
        : 'None of your accounts ends in ••${parsed.last4} — pick one, or '
            'add its last 4 digits in Accounts';
    final account = _accountById(draft.accountId);
    // A charge quoted in another currency than the account's own needs the
    // converted figure, which only the bank's statement will show.
    final foreign =
        (!parsed.isTransfer || draft.asExpense) && draft.isForeignFor(account);
    final accountSymbol = account?.symbol ?? CurrencyFormat.symbol;

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.md, Space.md),
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
                                fontWeight: FontWeight.w600,
                                fontSize: FontSizes.bodyLarge),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.only(bottom: Space.xxs),
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
                            fontSize: FontSizes.caption,
                            color: mutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  '$sign${parsed.currency == CurrencyFormat.symbol ? formatMoney(parsed.amount) : formatMoneyIn(parsed.currency, parsed.amount)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: FontSizes.bodyLarge,
                      color: amountColor),
                ),
              ],
            ),
            // The first decision on a debit, so it leads the card: what this
            // money was. Investment keeps it out of spending and budgets and
            // files it in the investments ledger instead.
            if (draft.canBeInvestment)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Space.sm, Space.sm, 0, Space.xs),
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
            if (widget.dismissedEarlier)
              _Notice(
                icon: Icons.visibility_off_outlined,
                color: mutedTextColor(context),
                text: 'You dismissed this one before.',
              ),
            if (unmatchedLast4)
              _Notice(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                text: unmatchedText,
              )
            else if (draft.needsSource)
              _Notice(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                text: 'Pick the account you paid from',
              ),
            if (draft.needsDestination)
              _Notice(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                text: parsed.toLast4 != null
                    ? 'None of your accounts ends in ••${parsed.toLast4} — '
                        'pick where it went'
                    : (draft.isCardPayment
                        ? 'Pick the card you paid'
                        : 'Pick the receiving account'),
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
                padding: const EdgeInsets.only(left: Space.xs, top: Space.xs),
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
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Looks like a monthly subscription — also create a '
                        'recurring rule.',
                        style: TextStyle(
                            fontSize: FontSizes.caption,
                            color: mutedTextColor(context)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.only(left: Space.sm),
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
                            flagged: unmatchedLast4,
                            onChanged: (v) {
                              draft.accountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: Space.md),
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
                            flagged: unmatchedLast4 || draft.needsSource,
                            onChanged: (v) {
                              draft.accountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          // A transfer needs the receiving account instead of a
                          // category; its category is fixed at "Transfer".
                          child: draft.recordsTransfer
                              ? _accountDropdown(
                                  label: 'To',
                                  value: draft.toAccountId,
                                  flagged: draft.needsDestination,
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
                padding: const EdgeInsets.only(left: Space.sm, top: Space.sm),
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
                      const SizedBox(width: Space.md),
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
            // The message on the left, the two ways of getting rid of it on
            // the right, on one line: with an icon each, the last one used
            // to drop onto a line of its own.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    style: _actionStyle,
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Message'),
                    onPressed: widget.onShowRaw,
                  ),
                  // Scaled down rather than overflowing at a very large
                  // text size.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onIgnoreMerchant != null)
                          TextButton(
                            style: _actionStyle,
                            onPressed: widget.onIgnoreMerchant,
                            child: const Text('Always ignore'),
                          ),
                        TextButton(
                          style: _actionStyle,
                          onPressed: widget.onDismiss,
                          child: const Text('Dismiss'),
                        ),
                      ],
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
}

/// What an SMS draft is recorded as, picked on its card.
enum _RecordAs { transfer, expense, investment }
