import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/category_memory.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the part of [SmsService] that is not the plugin: the window cutoff
/// and the already-seen filter, driven through [SmsService.inboxOverride].
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database; every test file shares one ffi process.
  DBService.dbNameOverride = 'sms_scan_test.db';

  final now = DateTime(2025, 8, 1, 12);

  RawSms sms(String body, {int daysAgo = 1, String sender = 'VM-HDFCBK'}) =>
      RawSms(
        sender: sender,
        body: body,
        receivedAt: now.subtract(Duration(days: daysAgo)),
      );

  setUp(() async {
    await DBService().clearAll();
    // Mirrors the Settings toggle; off by default, so tests must opt in.
    SmsService.enabled = true;
  });

  tearDown(() {
    SmsService.inboxOverride = null;
    SmsService.enabled = false;
  });

  test('parses transaction alerts and skips the rest', () async {
    SmsService.inboxOverride = () async => [
          sms('Rs.499.00 debited from A/c XX4821 on 31-Jul-25 to SWIGGY'),
          sms('123456 is your OTP. Do not share.'),
          sms('INR 45,000 credited to A/c XX4821. Info: SALARY'),
          sms('Get 50% off at MYNTRA! Click here to apply now.'),
        ];

    final found = await SmsService.scan(now: now);
    expect(found.length, 2);
    expect(found.map((f) => f.description), containsAll(['SWIGGY', 'HDFCBK']));
  });

  test('ignores messages older than the window', () async {
    SmsService.inboxOverride = () async => [
          sms('Rs.100 debited from A/c XX4821 to RECENT', daysAgo: 1),
          sms('Rs.200 debited from A/c XX4821 to STALE', daysAgo: 10),
        ];

    final found = await SmsService.scan(now: now);
    expect(found.map((f) => f.description), ['RECENT']);
  });

  test('does not re-offer a message that was already imported', () async {
    final message =
        sms('Rs.499.00 debited from A/c XX4821 on 31-Jul-25 to SWIGGY');
    SmsService.inboxOverride = () async => [message];

    final first = await SmsService.scan(now: now);
    expect(first.length, 1);

    await DBService().insertExpense(
        first.single.toExpense(accountId: null, category: 'Food'));

    // The same inbox, rescanned: the message is now accounted for.
    expect(await SmsService.scan(now: now), isEmpty);
  });

  test('does not re-offer a dismissed message', () async {
    SmsService.inboxOverride =
        () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];

    final first = await SmsService.scan(now: now);
    expect(first.length, 1);

    await DBService().ignoreSourceRefs([first.single.sourceRef]);
    expect(await SmsService.scan(now: now), isEmpty);
  });

  test('returns newest first', () async {
    SmsService.inboxOverride = () async => [
          sms('Rs.100 debited from A/c XX4821 on 20-Jul-25 to OLDER'),
          sms('Rs.200 debited from A/c XX4821 on 30-Jul-25 to NEWER'),
        ];

    final found = await SmsService.scan(now: now);
    expect(found.map((f) => f.description), ['NEWER', 'OLDER']);
  });

  test('an empty inbox is not an error', () async {
    SmsService.inboxOverride = () async => [];
    expect(await SmsService.scan(now: now), isEmpty);
  });

  test('a draft routes to the account matching the message last-4', () async {
    SmsService.inboxOverride = () async => [
          sms('Rs.2,150 spent on Credit Card XX5678 at AMAZON'),
          sms('Rs.499 debited from A/c XX9999 to SWIGGY'),
        ];
    final accounts = [
      Account(id: 1, name: 'HDFC Savings', type: 'bank', last4: '4821'),
      Account(id: 2, name: 'HDFC Card', type: 'credit_card', last4: '5678'),
    ];

    final drafts = [
      for (final p in await SmsService.scan(now: now))
        SmsDraft.from(p, accounts)
    ];

    final amazon = drafts.firstWhere((d) => d.parsed.description == 'AMAZON');
    expect(amazon.accountId, 2);
    expect(amazon.category, 'Other');
    expect(amazon.selected, isTrue);

    // XX9999 belongs to no account, so it is left for the user to pick.
    final swiggy = drafts.firstWhere((d) => d.parsed.description == 'SWIGGY');
    expect(swiggy.accountId, isNull);
  });

  test('an imported draft lands as a real transaction on its account',
      () async {
    SmsService.inboxOverride =
        () async => [sms('Rs.2,150 spent on Credit Card XX5678 at AMAZON')];
    final card =
        Account(name: 'HDFC Card', type: 'credit_card', last4: '5678');
    final cardId = await DBService().insertAccount(card);

    final parsed = (await SmsService.scan(now: now)).single;
    final draft = SmsDraft.from(
        parsed, [Account(id: cardId, name: 'HDFC Card', type: 'credit_card', last4: '5678')]);
    await DBService().insertExpenses([
      draft.parsed
          .toExpense(accountId: draft.accountId, category: draft.category)
    ]);

    final saved = (await DBService().getExpenses()).single;
    expect(saved.amount, 215000);
    expect(saved.type, DbConstants.txExpense);
    expect(saved.accountId, cardId);

    // The whole point: spending on the card moves that card's balance.
    final flows = await DBService().getAccountFlows();
    expect(flows[cardId], -215000);
  });

  test('an income draft moves the balance the other way', () async {
    SmsService.inboxOverride =
        () async => [sms('INR 45,000 credited to A/c XX4821. Info: SALARY')];
    final bankId = await DBService()
        .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));

    final parsed = (await SmsService.scan(now: now)).single;
    await DBService().insertExpenses(
        [parsed.toExpense(accountId: bankId, category: 'Salary')]);

    expect((await DBService().getAccountFlows())[bankId], 4500000);
  });

  test('a hand-entered row is never treated as an SMS import', () async {
    await DBService().insertExpense(Expense(
      description: 'Cash lunch',
      amount: 20000,
      date: now,
      category: 'Food',
      paymentMode: 'Cash',
    ));
    SmsService.inboxOverride =
        () async => [sms('Rs.200 debited from A/c XX4821 to CANTEEN')];

    // The typed row has no sourceRef, so it cannot suppress a real message.
    expect((await SmsService.scan(now: now)).length, 1);
  });

  test('sourceRef survives an import and blocks the rescan across sessions',
      () async {
    final message = sms('Rs.750 debited from A/c XX4821 to BIGBASKET');
    SmsService.inboxOverride = () async => [message];

    final parsed = (await SmsService.scan(now: now)).single;
    await DBService()
        .insertExpenses([parsed.toExpense(accountId: null, category: 'Food')]);

    // Re-derive the ref the way a later scan would, from the raw message.
    final rederived = SmsImport.sourceRefFor(
        message.sender, message.receivedAt, message.body);
    expect(rederived, parsed.sourceRef);
    expect(await DBService().existingSourceRefs(), contains(rederived));
  });

  group('transfers end to end', () {
    test('a card bill collapses to one transfer that moves both balances',
        () async {
      // The bank and the card each text about the same payment.
      SmsService.inboxOverride = () async => [
            sms('Rs.15,000 debited from A/c XX4821 on 31-Jul-25 towards '
                'HDFC Credit Card XX5678 payment'),
            sms('Payment of Rs.15,000 received on your HDFC Credit Card '
                'XX5678', sender: 'VM-HDFCB2'),
          ];
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final cardId = await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));
      final accounts = await DBService().getAccounts();

      final found = await SmsService.scan(now: now);
      expect(found.length, 1, reason: 'the two alerts are one movement');

      final draft = SmsDraft.from(found.single, accounts);
      expect(draft.isTransfer, isTrue);
      expect(draft.accountId, bankId);
      expect(draft.toAccountId, cardId);
      expect(draft.needsDestination, isFalse);

      await DBService().insertExpenses([draft.toExpense()]);
      final flows = await DBService().getAccountFlows();
      // Bank goes down, card debt goes up toward zero.
      expect(flows[bankId], -1500000);
      expect(flows[cardId], 1500000);
    });

    test('a card bill is not counted as spending', () async {
      SmsService.inboxOverride = () async => [
            sms('Rs.15,000 debited from A/c XX4821 on 31-Jul-25 towards '
                'HDFC Credit Card XX5678 payment'),
          ];
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final cardId = await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));
      final accounts = await DBService().getAccounts();

      final draft =
          SmsDraft.from((await SmsService.scan(now: now)).single, accounts);
      await DBService().insertExpenses([draft.toExpense()]);

      final provider = ExpenseProvider();
      await provider.ensureYearLoaded(2025);
      // The purchases already hit the card; the repayment must not be a
      // second expense on top of them.
      expect(provider.totalForMonth(2025, 7), 0);
      expect(provider.spendingForMonth(2025, 7), isEmpty);
      expect(bankId, isNotNull);
      expect(cardId, isNotNull);
    });

    test('both halves are marked seen so neither returns', () async {
      final bank = sms('Rs.15,000 debited from A/c XX4821 on 31-Jul-25 '
          'towards HDFC Credit Card XX5678 payment');
      final card = sms(
          'Payment of Rs.15,000 received on your HDFC Credit Card XX5678',
          sender: 'VM-HDFCB2');
      SmsService.inboxOverride = () async => [bank, card];

      final found = (await SmsService.scan(now: now)).single;
      await DBService().insertExpenses([
        found.toExpense(accountId: null, category: 'Transfer', toAccountId: null)
      ]);
      await DBService().ignoreSourceRefs(found.alsoCoversRefs);

      expect(await SmsService.scan(now: now), isEmpty);
    });

    test('an unresolvable destination is flagged, not silently dropped',
        () async {
      SmsService.inboxOverride = () async => [
            sms('Rs.15,000 debited from A/c XX4821 towards Credit Card '
                'XX9999 payment'),
          ];
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final accounts = await DBService().getAccounts();

      final draft =
          SmsDraft.from((await SmsService.scan(now: now)).single, accounts);
      expect(draft.isTransfer, isTrue);
      expect(draft.accountId, bankId);
      expect(draft.toAccountId, isNull);
      // The screen blocks import on this rather than posting a one-sided
      // transfer that debits the bank and credits nothing.
      expect(draft.needsDestination, isTrue);
    });
  });

  group('duplicates of hand-entered rows', () {
    test('a matching typed row leaves the draft unchecked', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      await DBService().insertExpense(Expense(
        description: 'Swiggy dinner',
        amount: 49900,
        date: now.subtract(const Duration(days: 1)),
        category: 'Food',
        paymentMode: 'Other',
        accountId: bankId,
      ));
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      final accounts = await DBService().getAccounts();
      final existing = await DBService().getExpenses();

      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single, accounts,
          existing: existing);
      expect(draft.duplicateOf, isNotNull);
      expect(draft.duplicateOf!.description, 'Swiggy dinner');
      expect(draft.selected, isFalse, reason: 'must not import by default');
    });

    test('an unrelated typed row leaves the draft checked', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      await DBService().insertExpense(Expense(
        description: 'Something else',
        amount: 12300,
        date: now.subtract(const Duration(days: 1)),
        category: 'Food',
        paymentMode: 'Cash',
        accountId: bankId,
      ));
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      final accounts = await DBService().getAccounts();
      final existing = await DBService().getExpenses();

      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single, accounts,
          existing: existing);
      expect(draft.duplicateOf, isNull);
      expect(draft.selected, isTrue);
    });
  });

  group('category memory', () {
    test('a familiar merchant arrives with its category already set',
        () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      // Three past Swiggy orders, all filed under Food.
      for (var i = 1; i <= 3; i++) {
        await DBService().insertExpense(Expense(
          description: 'SWIGGY',
          amount: 30000 + i,
          date: now.subtract(Duration(days: 10 + i)),
          category: 'Food',
          paymentMode: 'Other',
          accountId: bankId,
        ));
      }
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];

      final memory =
          CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single,
          await DBService().getAccounts(),
          memory: memory);

      expect(draft.category, 'Food');
      expect(draft.recalledCategory, 'Food');
      expect(draft.toExpense().category, 'Food');
    });

    test('an unfamiliar merchant still defaults to Other', () async {
      await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to NEWSHOP')];

      final memory =
          CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single,
          await DBService().getAccounts(),
          memory: memory);

      expect(draft.category, 'Other');
      expect(draft.recalledCategory, isNull);
    });

    test('the most-used category wins over a one-off', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      for (var i = 0; i < 4; i++) {
        await DBService().insertExpense(Expense(
          description: 'AMAZON',
          amount: 1000 + i,
          date: now.subtract(Duration(days: 5 + i)),
          category: 'Shopping',
          paymentMode: 'Other',
          accountId: bankId,
        ));
      }
      await DBService().insertExpense(Expense(
        description: 'AMAZON',
        amount: 9999,
        date: now.subtract(const Duration(days: 2)),
        category: 'Entertainment',
        paymentMode: 'Other',
        accountId: bankId,
      ));
      SmsService.inboxOverride =
          () async => [sms('Rs.2,150 spent on card XX4821 at AMAZON')];

      final memory =
          CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single,
          await DBService().getAccounts(),
          memory: memory);
      expect(draft.category, 'Shopping');
    });

    test('a transfer is never given a recalled category', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final cardId = await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));
      await DBService().insertExpense(Expense(
        description: 'Transfer',
        amount: 500,
        date: now.subtract(const Duration(days: 3)),
        category: 'Bills',
        paymentMode: 'Other',
        accountId: bankId,
      ));
      SmsService.inboxOverride = () async => [
            sms('Rs.15,000 debited from A/c XX4821 towards Credit Card '
                'XX5678 payment'),
          ];

      final memory =
          CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
      final draft = SmsDraft.from(
          (await SmsService.scan(now: now)).single,
          await DBService().getAccounts(),
          memory: memory);
      expect(draft.category, 'Transfer');
      expect(draft.recalledCategory, isNull);
      expect(cardId, isNotNull);
    });

    test('transfers contribute nothing to the memory', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      await DBService().insertExpense(Expense(
        description: 'BIGBASKET',
        amount: 500,
        date: now.subtract(const Duration(days: 3)),
        category: 'Transfer',
        paymentMode: '',
        type: DbConstants.txTransfer,
        accountId: bankId,
      ));
      final memory =
          CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
      expect(memory.categoryFor('BIGBASKET'), isNull);
    });
  });

  group('spend by account', () {
    test('splits the month across the accounts that carried it', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final cardId = await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));

      Future<void> spend(int? account, int amount) => DBService().insertExpense(
            Expense(
              description: 'x',
              amount: amount,
              date: DateTime(2025, 8, 10),
              category: 'Food',
              paymentMode: 'Other',
              accountId: account,
            ),
          );
      await spend(bankId, 10000);
      await spend(cardId, 25000);
      await spend(cardId, 5000);
      await spend(null, 700);

      final provider = ExpenseProvider();
      await provider.ensureYearLoaded(2025);
      final byAccount = provider.spendByAccountForMonth(2025, 8);

      expect(byAccount[bankId], 10000);
      expect(byAccount[cardId], 30000);
      // Rows with no account are kept under a null key rather than dropped.
      expect(byAccount[null], 700);
      expect(byAccount.values.fold<int>(0, (a, b) => a + b),
          provider.totalForMonth(2025, 8));
    });

    test('income and transfers are left out', () async {
      final bankId = await DBService()
          .insertAccount(Account(name: 'HDFC', type: 'bank', last4: '4821'));
      final cardId = await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));
      await DBService().insertExpense(Expense(
        description: 'Salary',
        amount: 4500000,
        date: DateTime(2025, 8, 1),
        category: 'Salary',
        paymentMode: '',
        type: DbConstants.txIncome,
        accountId: bankId,
      ));
      await DBService().insertExpense(Expense(
        description: 'Card bill',
        amount: 1500000,
        date: DateTime(2025, 8, 28),
        category: 'Transfer',
        paymentMode: '',
        type: DbConstants.txTransfer,
        accountId: bankId,
        toAccountId: cardId,
      ));
      await DBService().insertExpense(Expense(
        description: 'Lunch',
        amount: 20000,
        date: DateTime(2025, 8, 10),
        category: 'Food',
        paymentMode: 'Other',
        accountId: bankId,
      ));

      final provider = ExpenseProvider();
      await provider.ensureYearLoaded(2025);
      // Only the lunch counts: paying the card bill is not spending on the
      // bank it came from.
      expect(provider.spendByAccountForMonth(2025, 8), {bankId: 20000});
    });

    test('a month with no spending is empty', () async {
      final provider = ExpenseProvider();
      await provider.ensureYearLoaded(2025);
      expect(provider.spendByAccountForMonth(2025, 3), isEmpty);
    });
  });

  group('the Settings toggle', () {
    test('scanning reads nothing while it is off', () async {
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      expect(await SmsService.scan(now: now), isNotEmpty);

      SmsService.enabled = false;
      expect(await SmsService.scan(now: now), isEmpty);
    });

    test('the inbox is not even opened while it is off', () async {
      var reads = 0;
      SmsService.inboxOverride = () async {
        reads++;
        return [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      };

      SmsService.enabled = false;
      await SmsService.scan(now: now);
      expect(reads, 0, reason: 'the setting must gate the read itself');

      SmsService.enabled = true;
      await SmsService.scan(now: now);
      expect(reads, 1);
    });

    test('permission is never requested while it is off', () async {
      SmsService.enabled = false;
      expect(await SmsService.requestPermission(), isFalse);
    });

    test('turning it back on resumes where it left off', () async {
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      final first = await SmsService.scan(now: now);
      await DBService().insertExpenses(
          [first.single.toExpense(accountId: null, category: 'Food')]);

      SmsService.enabled = false;
      expect(await SmsService.scan(now: now), isEmpty);

      // Still deduped against what was already imported, not re-offered.
      SmsService.enabled = true;
      expect(await SmsService.scan(now: now), isEmpty);
    });
  });

  group('custom scan range', () {
    test('an explicit from/to window bounds what is offered', () async {
      SmsService.inboxOverride = () async => [
            sms('Rs.100 debited from A/c XX4821 to INRANGE', daysAgo: 5),
            sms('Rs.200 debited from A/c XX4821 to TOONEW', daysAgo: 1),
            sms('Rs.300 debited from A/c XX4821 to TOOOLD', daysAgo: 20),
          ];

      final found = await SmsService.scan(
        now: now,
        from: now.subtract(const Duration(days: 7)),
        to: now.subtract(const Duration(days: 3)),
      );
      expect(found.map((f) => f.description), ['INRANGE']);
    });

    test('a from earlier than the default window reaches older messages',
        () async {
      SmsService.inboxOverride = () async =>
          [sms('Rs.100 debited from A/c XX4821 to LASTWEEK', daysAgo: 6)];

      // The two-day default misses it...
      expect(await SmsService.scan(now: now), isEmpty);
      // ...but a wider explicit start pulls it in.
      final found = await SmsService.scan(
          now: now, from: now.subtract(const Duration(days: 10)));
      expect(found.map((f) => f.description), ['LASTWEEK']);
    });
  });

  group('recovering dismissed messages', () {
    test('a dismissed message returns only when asked for', () async {
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];

      final first = await SmsService.scan(now: now);
      await DBService().ignoreSourceRefs([first.single.sourceRef]);

      // The normal scan still hides it.
      expect(await SmsService.scan(now: now), isEmpty);
      // Opting in surfaces it again so it can be imported.
      final recovered =
          await SmsService.scan(now: now, includeDismissed: true);
      expect(recovered.map((f) => f.description), ['SWIGGY']);
    });

    test('an already-imported message stays hidden even with dismissed shown',
        () async {
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      final parsed = (await SmsService.scan(now: now)).single;
      await DBService()
          .insertExpenses([parsed.toExpense(accountId: null, category: 'Food')]);

      expect(
          await SmsService.scan(now: now, includeDismissed: true), isEmpty);
    });

    test('unignoreSourceRefs clears a rejection', () async {
      SmsService.inboxOverride =
          () async => [sms('Rs.499 debited from A/c XX4821 to SWIGGY')];
      final ref = (await SmsService.scan(now: now)).single.sourceRef;

      await DBService().ignoreSourceRefs([ref]);
      expect(await DBService().existingSourceRefs(), contains(ref));

      await DBService().unignoreSourceRefs([ref]);
      expect(await DBService().existingSourceRefs(), isNot(contains(ref)));
      // With the rejection gone, an ordinary scan offers it once more.
      expect((await SmsService.scan(now: now)).length, 1);
    });
  });

  group('importing as an investment', () {
    test('a debit draft can be filed as a contribution', () async {
      SmsService.inboxOverride = () async =>
          [sms('Rs.5,000 debited from A/c XX4821 to GROWW', daysAgo: 1)];
      final parsed = (await SmsService.scan(now: now)).single;
      final draft = SmsDraft.from(parsed, const [])
        ..asInvestment = true
        ..investmentType = 'Mutual Funds';

      expect(draft.canBeInvestment, isTrue);
      final investment = draft.toInvestment();
      expect(investment.amount, 500000);
      expect(investment.type, 'Mutual Funds');
      expect(investment.name, 'GROWW');
      expect(investment.date, parsed.date);
    });

    test('an income draft cannot be reclassified as an investment', () async {
      SmsService.inboxOverride =
          () async => [sms('INR 45,000 credited to A/c XX4821. Info: SALARY')];
      final draft =
          SmsDraft.from((await SmsService.scan(now: now)).single, const []);
      expect(draft.canBeInvestment, isFalse);
    });
  });

  group('the two-day window', () {
    test('yesterday is in range', () async {
      SmsService.inboxOverride = () async =>
          [sms('Rs.100 debited from A/c XX4821 to RECENT', daysAgo: 1)];
      expect((await SmsService.scan(now: now)).length, 1);
    });

    test('three days ago is out of range', () async {
      SmsService.inboxOverride = () async =>
          [sms('Rs.100 debited from A/c XX4821 to OLD', daysAgo: 3)];
      expect(await SmsService.scan(now: now), isEmpty);
    });

    test('the default window is two days', () {
      expect(SmsService.defaultWindow, const Duration(days: 2));
    });
  });
}
