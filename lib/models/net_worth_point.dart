/// A single month-end net-worth data point (value in minor units).
class NetWorthPoint {
  /// First day of the month this point represents.
  final DateTime month;

  /// Net worth at the end of [month], in minor units.
  final int value;

  const NetWorthPoint({required this.month, required this.value});
}
