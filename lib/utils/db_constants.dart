class DbConstants {
  static const String dbName = 'finance.db';
  static const int dbVersion = 11;

  // Expenses Table (holds expense, income, and transfer rows — see colType)
  static const String tableExpenses = 'expenses';
  static const String colId = 'id';
  static const String colDescription = 'description';
  static const String colAmount = 'amount';
  static const String colDate = 'date';
  static const String colCategory = 'category';
  static const String colPaymentMode = 'paymentMode';
  static const String colAccountId = 'accountId';
  static const String colToAccountId = 'toAccountId';
  // Amount credited to the destination account of a transfer, in the
  // destination account's currency (minor units). Null = same as colAmount
  // (both accounts in the same currency).
  static const String colToAmount = 'toAmount';
  // Stable identifier of the external record a row was imported from (see
  // SmsImport.sourceRefFor). Null for hand-entered rows. Lets a rescan of the
  // SMS inbox skip messages that were already imported.
  static const String colSourceRef = 'sourceRef';

  // Indexes on the expenses table.
  static const String idxExpensesDate = 'idx_expenses_date';
  static const String idxExpensesTypeAccount = 'idx_expenses_type_account';
  static const String idxExpensesToAccount = 'idx_expenses_to_account';
  static const String idxExpensesSourceRef = 'idx_expenses_source_ref';

  // Investments Table
  static const String tableInvestments = 'investments';
  static const String colName = 'name';
  // Shared by investments (investment type) and expenses (transaction type:
  // expense | income | transfer) and accounts (account type).
  static const String colType = 'type';

  // Budgets Table
  static const String tableBudgets = 'budgets';
  static const String colYear = 'year';
  static const String colMonth = 'month';

  // Accounts Table
  static const String tableAccounts = 'accounts';
  static const String colOpeningBalance = 'openingBalance';
  static const String colIcon = 'icon';
  static const String colColor = 'color';
  // Per-account currency symbol (null = app base currency) and the exchange
  // rate to base (base units per 1 account-currency unit; null/absent = 1.0).
  static const String colCurrency = 'currency';
  static const String colRate = 'rate';
  // Last four digits of the account/card number, as printed in bank SMS
  // alerts ("A/c XX4821"). Null when unset; used to route a parsed message
  // to the right account.
  static const String colLast4 = 'last4';

  // SMS messages the user dismissed in the import review queue, so a later
  // rescan of the inbox does not offer them again.
  static const String tableSmsIgnored = 'sms_ignored';

  // Transaction type values stored in expenses.type
  static const String txExpense = 'expense';
  static const String txIncome = 'income';
  static const String txTransfer = 'transfer';

  // Recurring Rules Table
  static const String tableRecurringRules = 'recurring_rules';
  static const String colFrequency = 'frequency';
  static const String colNextDue = 'nextDue';
  static const String colAnchorDay = 'anchorDay';
  static const String colEnabled = 'enabled';

  // Templates Table
  static const String tableTemplates = 'templates';

  // Savings Goals Table
  static const String tableGoals = 'goals';
  // Target amount and amount saved so far, both in minor units. targetDate is
  // an optional ISO-8601 deadline (null = no deadline). Name reuses colName.
  static const String colTargetAmount = 'targetAmount';
  static const String colSavedAmount = 'savedAmount';
  static const String colTargetDate = 'targetDate';

  // Frequency values stored in recurring_rules.frequency
  static const String freqDaily = 'daily';
  static const String freqWeekly = 'weekly';
  static const String freqMonthly = 'monthly';
  static const String freqYearly = 'yearly';
}
