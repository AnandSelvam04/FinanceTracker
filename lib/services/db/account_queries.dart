part of '../db_service.dart';

/// Accounts and the figures computed from them: balances, flows, net worth,
/// shared credit limits and card EMI plans.
extension AccountQueries on DBService {
  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert(DbConstants.tableAccounts, account.toMap());
  }

  Future<List<Account>> getAccounts() async {
    final db = await database;
    final maps =
        await db.query(DbConstants.tableAccounts, orderBy: DbConstants.colName);
    return maps.map((map) => Account.fromMap(map)).toList();
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    return await db.transaction((txn) async {
      final n = await txn.update(DbConstants.tableAccounts, account.toMap(),
          where: '${DbConstants.colId} = ?', whereArgs: [account.id]);
      if (account.id != null) {
        if (account.sharedLimitWith != null) {
          // This card now draws on another card's limit, so any card that
          // drew on its limit follows it there.
          await _handOverSharedLimit(txn, account.id!,
              to: account.sharedLimitWith);
        } else if (account.type != 'credit_card') {
          // No longer a card: the cards that shared its limit keep it
          // between them.
          await _handOverSharedLimit(txn, account.id!,
              limit: account.creditLimit);
        }
      }
      return n;
    });
  }

  /// Moves the cards that share card [id]'s credit limit on, once [id] stops
  /// holding it: onto card [to] when given, else the first of them takes the
  /// limit over (with [limit] as its value unless it has one of its own) and
  /// the rest share it from there. Keeps a Visa + RuPay pair working when one
  /// of the two is deleted or re-linked.
  static Future<void> _handOverSharedLimit(Transaction txn, int id,
      {int? to, int? limit}) async {
    // Only cards: an EMI's loan account points at its own card for good.
    final members = await txn.query(DbConstants.tableAccounts,
        where: '${DbConstants.colSharedLimitWith} = ? AND '
            '${DbConstants.colId} != ? AND '
            "${DbConstants.colType} = 'credit_card'",
        whereArgs: [id, id],
        orderBy: DbConstants.colId);
    if (members.isEmpty) return;
    var holder = to;
    if (holder == null) {
      final first = members.first;
      holder = first[DbConstants.colId] as int;
      await txn.update(
        DbConstants.tableAccounts,
        {
          DbConstants.colSharedLimitWith: null,
          DbConstants.colCreditLimit:
              first[DbConstants.colCreditLimit] ?? limit,
        },
        where: '${DbConstants.colId} = ?',
        whereArgs: [holder],
      );
    }
    await txn.update(
      DbConstants.tableAccounts,
      {DbConstants.colSharedLimitWith: holder},
      where: '${DbConstants.colSharedLimitWith} = ? AND '
          '${DbConstants.colId} != ? AND '
          "${DbConstants.colType} = 'credit_card'",
      whereArgs: [id, holder],
    );
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    // Detach the account from transactions, recurring rules, and templates
    // in one transaction so nothing keeps a dangling reference to (or keeps
    // posting into) a deleted account.
    return await db.transaction((txn) async {
      await txn.update(
        DbConstants.tableExpenses,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableExpenses,
        {DbConstants.colToAccountId: null},
        where: '${DbConstants.colToAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableRecurringRules,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableTemplates,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableInvestments,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      // An EMI plan goes with its card or its loan account; its loan stays
      // (the debt is real) but no longer draws on a card that is gone.
      await txn.delete(DbConstants.tableEmiPlans,
          where: '${DbConstants.colEmiCardId} = ? OR '
              '${DbConstants.colEmiLoanId} = ?',
          whereArgs: [id, id]);
      await txn.update(
          DbConstants.tableAccounts, {DbConstants.colSharedLimitWith: null},
          where: '${DbConstants.colSharedLimitWith} = ? AND '
              "${DbConstants.colType} != 'credit_card'",
          whereArgs: [id]);
      // Cards that shared this one's limit keep it between them.
      final gone = await txn.query(DbConstants.tableAccounts,
          columns: [DbConstants.colCreditLimit],
          where: '${DbConstants.colId} = ?',
          whereArgs: [id]);
      await _handOverSharedLimit(txn, id,
          limit: gone.isEmpty
              ? null
              : (gone.first[DbConstants.colCreditLimit] as num?)?.toInt());
      return await txn.delete(DbConstants.tableAccounts,
          where: '${DbConstants.colId} = ?', whereArgs: [id]);
    });
  }

  /// Money into and out of each account, in its own currency: income and
  /// transfers in, against expenses and transfers out (investments paid
  /// from it count as out). For loans and money lent, where "in" and "out"
  /// are what was repaid and what was borrowed or lent.
  Future<Map<int, ({int inflow, int outflow})>> getAccountInOut() async {
    final db = await database;
    final inflow = <int, int>{}, outflow = <int, int>{};
    final rows = await db.rawQuery(
        'SELECT ${DbConstants.colAccountId} AS id, ${DbConstants.colType} AS t, '
        'SUM(${DbConstants.colAmount}) AS amt FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colAccountId} IS NOT NULL GROUP BY id, t');
    for (final r in rows) {
      final id = r['id'] as int;
      final amt = ((r['amt'] ?? 0) as num).round();
      if (r['t'] == DbConstants.txIncome) {
        inflow[id] = (inflow[id] ?? 0) + amt;
      } else {
        outflow[id] = (outflow[id] ?? 0) + amt;
      }
    }
    final ins = await db.rawQuery(
        'SELECT ${DbConstants.colToAccountId} AS id, '
        'SUM(COALESCE(${DbConstants.colToAmount}, ${DbConstants.colAmount})) '
        'AS amt FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colType} = ? AND '
        '${DbConstants.colToAccountId} IS NOT NULL GROUP BY id',
        [DbConstants.txTransfer]);
    for (final r in ins) {
      final id = r['id'] as int;
      inflow[id] = (inflow[id] ?? 0) + ((r['amt'] ?? 0) as num).round();
    }
    final inv = await db.rawQuery('SELECT ${DbConstants.colAccountId} AS id, '
        'SUM(${DbConstants.colAmount}) AS amt '
        'FROM ${DbConstants.tableInvestments} '
        'WHERE ${DbConstants.colAccountId} IS NOT NULL GROUP BY id');
    for (final r in inv) {
      final id = r['id'] as int;
      outflow[id] = (outflow[id] ?? 0) + ((r['amt'] ?? 0) as num).round();
    }
    return {
      for (final id in {...inflow.keys, ...outflow.keys})
        id: (inflow: inflow[id] ?? 0, outflow: outflow[id] ?? 0)
    };
  }

  Future<void> clearAccounts() async {
    final db = await database;
    await db.delete(DbConstants.tableAccounts);
  }

  /// Balance = opening + net flows, in the account's own currency.
  /// Computed in SQL so it covers all years, not just those loaded into
  /// ExpenseProvider. Prefer [getAccountFlows] when refreshing every account.
  Future<int> getAccountBalance(Account account) async {
    final flows = await getAccountFlows();
    return account.openingBalance + (flows[account.id] ?? 0);
  }

  /// Net worth (base-currency minor units) at the end of each of the last
  /// [months] months, oldest first. Net worth = account opening balances +
  /// cumulative (income − expense) + cumulative investments, as of each month
  /// end, with every account's flows converted at its exchange rate so the
  /// trend agrees with the headline figure. Same-currency transfers cancel;
  /// cross-currency transfers move value at the rates captured on the row.
  ///
  /// Three grouped queries + accumulation in Dart, instead of one query per
  /// month per flow type.
  Future<List<NetWorthPoint>> netWorthSeries(int months,
      {DateTime? now}) async {
    final db = await database;
    final today = now ?? DateTime.now();

    final accounts = await getAccounts();
    final rateById = {for (final a in accounts) a.id!: a.rate};
    double rateOf(Object? accountId) =>
        accountId == null ? 1.0 : (rateById[accountId] ?? 1.0);
    // Deleting an account nulls accountId/toAccountId on the rows that
    // referenced it. For a transfer that means one leg now points nowhere:
    // the money did not actually move into or out of anything we still track,
    // so that leg must not affect net worth. Counting it (at rate 1.0, no
    // less) made the trend diverge permanently from the account balances,
    // which exclude these rows outright — see getAccountFlows.
    bool isLiveAccount(Object? accountId) =>
        accountId != null && rateById.containsKey(accountId);
    final opening = accounts.fold<int>(
        0, (sum, a) => sum + toBaseMinor(a.openingBalance, a.rate));

    // ISO-8601 dates sort lexicographically, so substr(date, 1, 7) is the
    // row's YYYY-MM month key.
    final txRows = await db.rawQuery(
        'SELECT substr(${DbConstants.colDate}, 1, 7) AS ym, '
        '${DbConstants.colType} AS type, '
        '${DbConstants.colAccountId} AS accountId, '
        '${DbConstants.colToAccountId} AS toAccountId, '
        'SUM(${DbConstants.colAmount}) AS amt, '
        'SUM(COALESCE(${DbConstants.colToAmount}, ${DbConstants.colAmount})) AS toAmt '
        'FROM ${DbConstants.tableExpenses} '
        'GROUP BY ym, type, accountId, toAccountId');
    final invRows =
        await db.rawQuery('SELECT substr(${DbConstants.colDate}, 1, 7) AS ym, '
            '${DbConstants.colAccountId} AS accountId, '
            'SUM(${DbConstants.colAmount}) AS amt '
            'FROM ${DbConstants.tableInvestments} GROUP BY ym, accountId');

    // Net base-currency change per month.
    final deltaByMonth = <String, double>{};
    void addDelta(Object? ym, double value) {
      if (ym is! String) return;
      deltaByMonth[ym] = (deltaByMonth[ym] ?? 0) + value;
    }

    for (final row in txRows) {
      final amt = ((row['amt'] ?? 0) as num).toDouble();
      final toAmt = ((row['toAmt'] ?? 0) as num).toDouble();
      switch (row['type']) {
        // Income and expenses only move net worth through an account's
        // balance: rows with no (live) account aren't in any balance on the
        // Net worth card, so counting them here made the trend's latest point
        // disagree with the headline figure right above it.
        case DbConstants.txIncome:
          if (isLiveAccount(row['accountId'])) {
            addDelta(row['ym'], amt * rateOf(row['accountId']));
          }
        case DbConstants.txExpense:
          if (isLiveAccount(row['accountId'])) {
            addDelta(row['ym'], -amt * rateOf(row['accountId']));
          }
        case DbConstants.txTransfer:
          var delta = 0.0;
          if (isLiveAccount(row['accountId'])) {
            delta -= amt * rateOf(row['accountId']);
          }
          if (isLiveAccount(row['toAccountId'])) {
            delta += toAmt * rateOf(row['toAccountId']);
          }
          addDelta(row['ym'], delta);
      }
    }
    for (final row in invRows) {
      final amt = ((row['amt'] ?? 0) as num).toDouble();
      // The holding grows by what was invested; the account it was paid from
      // shrinks by the same (a card's owed balance grows), so buying with
      // your own money leaves net worth where it was.
      var delta = amt;
      if (isLiveAccount(row['accountId'])) {
        delta -= amt * rateOf(row['accountId']);
      }
      addDelta(row['ym'], delta);
    }

    String ymKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

    // Accumulate every month's delta oldest-first; emit the running value at
    // each of the requested month ends.
    final sortedMonths = deltaByMonth.keys.toList()..sort();
    final series = <NetWorthPoint>[];
    var running = opening.toDouble();
    var next = 0;
    for (int i = months - 1; i >= 0; i--) {
      final monthStart = DateTime(today.year, today.month - i, 1);
      final key = ymKey(monthStart);
      while (next < sortedMonths.length &&
          sortedMonths[next].compareTo(key) <= 0) {
        running += deltaByMonth[sortedMonths[next]]!;
        next++;
      }
      series.add(NetWorthPoint(month: monthStart, value: running.round()));
    }
    return series;
  }

  /// Net transaction flow per account (minor units, in each account's own
  /// currency): income − expenses − outgoing transfers + incoming transfers.
  /// One pass over the table instead of four queries per account. Incoming
  /// cross-currency transfers credit the destination-side amount.
  Future<Map<int, int>> getAccountFlows() async {
    final db = await database;
    final flows = <int, double>{};

    final outRows =
        await db.rawQuery('SELECT ${DbConstants.colAccountId} AS accountId, '
            '${DbConstants.colType} AS type, '
            'SUM(${DbConstants.colAmount}) AS amt '
            'FROM ${DbConstants.tableExpenses} '
            'WHERE ${DbConstants.colAccountId} IS NOT NULL '
            'GROUP BY accountId, type');
    for (final row in outRows) {
      final id = row['accountId'] as int;
      final amt = ((row['amt'] ?? 0) as num).toDouble();
      final sign = row['type'] == DbConstants.txIncome ? 1 : -1;
      flows[id] = (flows[id] ?? 0) + sign * amt;
    }

    final inRows = await db.rawQuery(
        'SELECT ${DbConstants.colToAccountId} AS accountId, '
        'SUM(COALESCE(${DbConstants.colToAmount}, ${DbConstants.colAmount})) AS amt '
        'FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colType} = ? '
        'AND ${DbConstants.colToAccountId} IS NOT NULL '
        'GROUP BY accountId',
        [DbConstants.txTransfer]);
    for (final row in inRows) {
      final id = row['accountId'] as int;
      flows[id] = (flows[id] ?? 0) + ((row['amt'] ?? 0) as num).toDouble();
    }

    // Investments paid from an account leave it like an expense (a
    // withdrawal, stored negative, comes back in).
    final invRows =
        await db.rawQuery('SELECT ${DbConstants.colAccountId} AS accountId, '
            'SUM(${DbConstants.colAmount}) AS amt '
            'FROM ${DbConstants.tableInvestments} '
            'WHERE ${DbConstants.colAccountId} IS NOT NULL '
            'GROUP BY accountId');
    for (final row in invRows) {
      final id = row['accountId'] as int;
      flows[id] = (flows[id] ?? 0) - ((row['amt'] ?? 0) as num).toDouble();
    }

    return flows.map((id, v) => MapEntry(id, v.round()));
  }

  Future<int> insertEmiPlan(EmiPlan plan) async {
    final db = await database;
    return db.insert(DbConstants.tableEmiPlans, plan.toMap());
  }

  Future<List<EmiPlan>> getEmiPlans() async {
    final db = await database;
    final rows =
        await db.query(DbConstants.tableEmiPlans, orderBy: DbConstants.colDate);
    return rows.map(EmiPlan.fromMap).toList();
  }

  Future<void> deleteEmiPlan(int id) async {
    final db = await database;
    await db.delete(DbConstants.tableEmiPlans,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }
}
