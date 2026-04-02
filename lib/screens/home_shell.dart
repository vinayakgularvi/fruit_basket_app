import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'delivery_screen.dart';
import 'leads_screen.dart';
import 'payments_screen.dart';

/// Below this width the shell uses a bottom [NavigationBar] (can clip many
/// items on narrow web viewports). Wider layouts use [NavigationRail] so every
/// admin destination (including Leads) stays visible.
const _kSideNavBreakpoint = 720.0;

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
            LeadsScreen(key: ValueKey('shell_leads')),
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
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: 'Leads',
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
    final railDestinations = !deliveryOnly
        ? const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: Text('Home'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: Text('Customers'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: Text('Leads'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: Text('Deliveries'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: Text('Payments'),
            ),
          ]
        : const <NavigationRailDestination>[];

    final selectedIndex = _index >= screens.length ? 0 : _index;
    final width = MediaQuery.sizeOf(context).width;
    final useSideNav = !deliveryOnly && width >= _kSideNavBreakpoint;

    if (useSideNav) {
      // [extended] and [labelType] != null/.all are mutually exclusive in Material.
      final extendedRail = width >= 1100;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: extendedRail
                  ? null
                  : NavigationRailLabelType.all,
              extended: extendedRail,
              minExtendedWidth: 200,
              destinations: railDestinations,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: selectedIndex,
                children: screens,
              ),
            ),
          ],
        ),
      );
    }

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
