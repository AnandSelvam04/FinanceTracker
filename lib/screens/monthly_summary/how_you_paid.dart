part of '../monthly_summary_screen.dart';

/// How the period's spending was paid — credit cards, bank, UPI, cash — with
/// the accounts behind each, largest first.
///
/// Replaces a flat per-account list, which showed which card was used but
/// not how much of the month went on cards altogether, against bank, UPI and
/// cash. The Accounts screen shows balances, which are positions rather than
/// periods; this is what answers "how much did I put on my cards".
class _HowYouPaid extends StatelessWidget {
  final List<Expense> rows;
  final int Function(Expense) baseAmountOf;
  const _HowYouPaid({required this.rows, required this.baseAmountOf});

  static Color colorOf(BuildContext context, PayMethod m) {
    final scheme = Theme.of(context).colorScheme;
    return switch (m) {
      PayMethod.creditCard => scheme.primary,
      PayMethod.bank => scheme.tertiary,
      PayMethod.upi => infoColor(context),
      PayMethod.cash => warningColor(context),
      PayMethod.other => mutedTextColor(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final split = paymentSplit(rows, baseAmountOf, accounts.accountById);
    if (split.isEmpty) return const SizedBox.shrink();
    final total = split.fold<int>(0, (s, m) => s + m.total);
    final muted = mutedTextColor(context);
    String share(int v) => '${(v / total * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('How you paid'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One bar, a segment per method, so the mix reads at a glance.
                Semantics(
                  label: 'Spending by payment method',
                  value: [
                    for (final m in split) '${m.method.label} ${share(m.total)}'
                  ].join(', '),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final m in split)
                            Expanded(
                              // At least a sliver for a tiny share.
                              flex: (m.total * 1000 ~/ total).clamp(8, 1000),
                              child:
                                  ColoredBox(color: colorOf(context, m.method)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in split) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorOf(context, m.method),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(m.method.label,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(share(m.total),
                              style: TextStyle(
                                  fontSize: FontSizes.caption, color: muted)),
                        ),
                        Text(formatMoney(m.total),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  // The accounts behind a method — each card, each bank —
                  // unless the only part is spending with no account.
                  if (m.parts.length > 1 || m.parts.single.accountId != null)
                    for (final p in m.parts)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 20, top: 2, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                accounts.accountById(p.accountId)?.name ??
                                    'No account',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: FontSizes.body,
                                  color: muted,
                                  fontStyle: p.accountId == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            Text(formatMoney(p.total),
                                style: TextStyle(
                                    fontSize: FontSizes.body, color: muted)),
                          ],
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
