import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'delivery_screen.dart';
import 'payments_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final deliveryOnly = repo.isDeliveryAgent;
    final screens = deliveryOnly
        ? const [
            DashboardScreen(key: ValueKey('shell_dash')),
            DeliveryScreen(key: ValueKey('shell_delivery_agent')),
          ]
        : const [
            DashboardScreen(key: ValueKey('shell_dash')),
            CustomersScreen(key: ValueKey('shell_customers')),
            DeliveryScreen(key: ValueKey('shell_delivery')),
            PaymentsScreen(key: ValueKey('shell_payments')),
          ];
    final nav = deliveryOnly
        ? const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'Deliveries',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'Deliveries',
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Payments',
            ),
          ];
    final selectedIndex = _index >= screens.length ? 0 : _index;
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: nav,
      ),
    );
  }
}
