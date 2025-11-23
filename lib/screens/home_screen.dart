import 'package:flutter/material.dart';
import 'add_expense_screen.dart';
import 'add_investment_screen.dart';
// import 'backups_screen.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_chart.dart';
// import 'month_selector.dart';
import 'expense_list_screen.dart';
import '../widgets/expense_trends_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  List<Widget> _screens(BuildContext context) => [
        Consumer<ExpenseProvider>(
          builder: (context, provider, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Dashboard & Charts', style: TextStyle(fontSize: 20)),
              SizedBox(height: 8),
              MonthSelector(
                initialYear: _selectedYear,
                initialMonth: _selectedMonth,
                onChanged: (year, month) {
                  setState(() {
                    _selectedYear = year;
                    _selectedMonth = month;
                  });
                },
              ),
              SizedBox(height: 8),
              if (provider
                  .expensesForMonth(_selectedYear, _selectedMonth)
                  .isEmpty)
                const Text('No expenses this month.')
              else ...[
                SizedBox(
                  height: 250,
                  child: ExpenseChart(
                      expenses: provider.expensesForMonth(
                          _selectedYear, _selectedMonth)),
                ),
                Text(
                  'Total: ₹${provider.totalForMonth(_selectedYear, _selectedMonth).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('Trends (Last 12 Months)',
                    style: TextStyle(fontSize: 16)),
                ExpenseTrendsChart(provider: provider),
              ],
            ],
          ),
        ),
        const AddExpenseScreen(),
        const AddInvestmentScreen(),
        const ExpenseListScreen(),
      ];

  // _onItemTapped removed (no longer needed)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance Tracker')),
      body: _screens(context)[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add Expense',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Add Investment',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Expenses',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}

class MonthSelector extends StatefulWidget {
  final void Function(int year, int month) onChanged;
  final int initialYear;
  final int initialMonth;
  const MonthSelector(
      {super.key,
      required this.onChanged,
      required this.initialYear,
      required this.initialMonth});

  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  late int year;
  late int month;

  @override
  void initState() {
    super.initState();
    year = widget.initialYear;
    month = widget.initialMonth;
  }

  void _changeMonth(int delta) {
    setState(() {
      month += delta;
      if (month > 12) {
        month = 1;
        year++;
      } else if (month < 1) {
        month = 12;
        year--;
      }
      widget.onChanged(year, month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _changeMonth(-1),
        ),
        Text("$year-${month.toString().padLeft(2, '0')}",
            style: const TextStyle(fontSize: 16)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }
}
