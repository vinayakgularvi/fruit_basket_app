import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = AppRepository();
  await repo.initFirebase();
  runApp(
    ChangeNotifierProvider(
      create: (_) => repo,
      child: const FruitBasketApp(),
    ),
  );
}

class FruitBasketApp extends StatelessWidget {
  const FruitBasketApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return MaterialApp(
      title: 'Fruit Basket',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: repo.isLoggedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}
