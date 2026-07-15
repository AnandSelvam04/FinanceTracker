class DbConstants {
  static const String dbName = 'finance.db';
  static const int dbVersion = 8;

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

  // Indexes on the expenses table.
  static const String idxExpensesDate = 'idx_expenses_date';
  static const String idxExpensesTypeAccount = 'idx_expenses_type_account';
  static const String idxExpensesToAccount = 'idx_expenses_to_account';

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

  // Frequency values stored in recurring_rules.frequency
  static const String freqDaily = 'daily';
  static const String freqWeekly = 'weekly';
  static const String freqMonthly = 'monthly';
  static const String freqYearly = 'yearly';
}
