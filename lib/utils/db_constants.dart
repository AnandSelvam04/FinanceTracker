class DbConstants {
  static const String dbName = 'finance.db';
  static const int dbVersion = 4;

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

  // Transaction type values stored in expenses.type
  static const String txExpense = 'expense';
  static const String txIncome = 'income';
  static const String txTransfer = 'transfer';
}
