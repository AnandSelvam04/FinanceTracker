import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:finance_tracker/services/app_service.dart';
// import 'package:finance_tracker/views/home_view.dart';

void main() {
  runApp(const FinanceTrackerApp());
}

class FinanceTrackerApp extends StatelessWidget {
  const FinanceTrackerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Add providers here
        // ChangeNotifierProvider(create: (_) => AppService()),
      ],
      child: MaterialApp(
        title: 'Finance Tracker',
        theme: ThemeData(
          primarySwatch: Colors.green,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const Placeholder(), // Replace with HomeView()
      ),
    );
  }
}
