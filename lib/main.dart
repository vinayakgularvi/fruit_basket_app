import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppRepository(),
      child: const FruitBasketApp(),
    ),
  );
}

class FruitBasketApp extends StatelessWidget {
  const FruitBasketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fruit Basket',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}
