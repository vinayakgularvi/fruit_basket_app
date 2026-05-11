import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../feature_flags.dart';
import '../models/customer_list_filter.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'delivery_screen.dart';
import 'employees_screen.dart';
import 'leads_screen.dart';
import 'needed_fruits_screen.dart';
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
  int _customersKey = 0;
  CustomerListFilter? _customersInitialFilter;

  void _openCustomersWithFilter(CustomerListFilter filter) {
    setState(() {
      _customersInitialFilter = filter;
      _customersKey++;
      _index = 1;
    });
  }

  List<Widget> _adminScreens(bool includeFruitsTab) {
    final dash = DashboardScreen(
      key: const ValueKey('shell_dash'),
      onOpenCustomersFilter: _openCustomersWithFilter,
    );
    final cust = CustomersScreen(
      key: ValueKey('shell_cust_$_customersKey'),
      initialFilter: _customersInitialFilter,
    );
    const emp = EmployeesScreen(key: ValueKey('shell_employees'));
    const leads = LeadsScreen(key: ValueKey('shell_leads'));
    const fruits = NeededFruitsScreen(key: ValueKey('shell_needed_fruits'));
    const del = DeliveryScreen(key: ValueKey('shell_delivery'));
    const pay = PaymentsScreen(key: ValueKey('shell_payments'));
    if (includeFruitsTab) {
      return [dash, cust, emp, leads, fruits, del, pay];
    }
    return [dash, cust, emp, leads, del, pay];
  }

  List<NavigationDestination> _adminBottomDestinations(bool includeFruitsTab) {
    final base = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: 'Customers',
      ),
      const NavigationDestination(
        icon: Icon(Icons.badge_outlined),
        selectedIcon: Icon(Icons.badge),
        label: 'Employees',
      ),
      const NavigationDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: 'Leads',
      ),
    ];
    if (includeFruitsTab) {
      base.add(
        const NavigationDestination(
          icon: Icon(Icons.shopping_basket_outlined),
          selectedIcon: Icon(Icons.shopping_basket),
          label: 'Buy fruits',
        ),
      );
    }
    base.addAll(const [
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
    ]);
    return base;
  }

  List<NavigationRailDestination> _adminRailDestinations(bool includeFruitsTab) {
    final base = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Home'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: Text('Customers'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.badge_outlined),
        selectedIcon: Icon(Icons.badge),
        label: Text('Employees'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: Text('Leads'),
      ),
    ];
    if (includeFruitsTab) {
      base.add(
        const NavigationRailDestination(
          icon: Icon(Icons.shopping_basket_outlined),
          selectedIcon: Icon(Icons.shopping_basket),
          label: Text('Buy fruits'),
        ),
      );
    }
    base.addAll(const [
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
    ]);
    return base;
  }

  static const _fruitBuyerNav = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.shopping_basket_outlined),
      selectedIcon: Icon(Icons.shopping_basket),
      label: 'Buy fruits',
    ),
  ];

  static const _fruitBuyerRail = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.shopping_basket_outlined),
      selectedIcon: Icon(Icons.shopping_basket),
      label: Text('Buy fruits'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final deliveryOnly = repo.isDeliveryAgent;
    final fruitBuyerOnly =
        repo.isFruitBuyer && !repo.isAdmin && !repo.isDeliveryAgent;
    final showFruitsTab =
        FeatureFlags.showFruitBuyUi && (repo.isAdmin || repo.isFruitBuyer);

    final screens = deliveryOnly
        ? [
            const DashboardScreen(
              key: ValueKey('shell_dash'),
              onOpenCustomersFilter: null,
            ),
            const DeliveryScreen(key: ValueKey('shell_delivery_agent')),
          ]
        : fruitBuyerOnly
            ? FeatureFlags.showFruitBuyUi
                ? [
                    const DashboardScreen(
                      key: ValueKey('shell_dash_fruit_buyer'),
                      onOpenCustomersFilter: null,
                    ),
                    const NeededFruitsScreen(
                      key: ValueKey('shell_needed_fruits_fruit_buyer'),
                    ),
                  ]
                : [
                    const DashboardScreen(
                      key: ValueKey('shell_dash_fruit_buyer'),
                      onOpenCustomersFilter: null,
                    ),
                  ]
            : _adminScreens(showFruitsTab);
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
        : fruitBuyerOnly
            ? (FeatureFlags.showFruitBuyUi
                ? _fruitBuyerNav
                : const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Home',
                    ),
                  ])
            : _adminBottomDestinations(showFruitsTab);
    final railDestinations = deliveryOnly
        ? const <NavigationRailDestination>[]
        : fruitBuyerOnly
            ? (FeatureFlags.showFruitBuyUi
                ? _fruitBuyerRail
                : const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Home'),
                    ),
                  ])
            : _adminRailDestinations(showFruitsTab);

    final screenCount = screens.length;
    if (_index >= screenCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = 0);
      });
    }
    final selectedIndex = _index >= screenCount ? 0 : _index;
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
