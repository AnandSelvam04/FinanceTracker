class DbConstants {
  static const String dbName = 'finance.db';
  static const int dbVersion = 3;

  // Expenses Table
  static const String tableExpenses = 'expenses';
  static const String colId = 'id';
  static const String colDescription = 'description';
  static const String colAmount = 'amount';
  static const String colDate = 'date';
  static const String colCategory = 'category';
  static const String colPaymentMode = 'paymentMode';

  // Investments Table
  static const String tableInvestments = 'investments';
  static const String colName = 'name';
  static const String colType = 'type';

  // Budgets Table
  static const String tableBudgets = 'budgets';
  static const String colYear = 'year';
  static const String colMonth = 'month';
}
