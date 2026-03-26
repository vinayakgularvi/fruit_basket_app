import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart';

class AppRepository extends ChangeNotifier {
  AppRepository() {
    _seed();
  }

  final List<Customer> _customers = [];
  final Map<String, bool> _deliveryDoneToday = {};
  final List<Payment> _payments = [];

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> activeCustomers() =>
      _customers.where((c) => c.active).toList();

  /// Active customers with a delivery scheduled for today (demo: all active).
  int get todayDeliveryCount => activeCustomers().length;

  double get monthlyRevenueEstimate {
    // Demo: sum of pending + rough subscription estimate
    const perCustomer = 120.0;
    return activeCustomers().length * perCustomer;
  }

  List<Payment> get pendingPayments =>
      _payments.where((p) => p.status == PaymentStatus.pending).toList();

  double get totalPendingAmount =>
      pendingPayments.fold(0.0, (a, p) => a + p.amount);

  List<Customer> customersForSlot(DeliverySlot slot) {
    return _customers
        .where((c) => c.active && c.preferredSlot == slot)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  bool isDeliveryChecked(String customerId) =>
      _deliveryDoneToday[customerId] ?? false;

  void toggleDeliveryDone(String customerId) {
    _deliveryDoneToday[customerId] = !isDeliveryChecked(customerId);
    notifyListeners();
  }

  void markAllDeliveriesDone(DeliverySlot slot, bool value) {
    for (final c in customersForSlot(slot)) {
      _deliveryDoneToday[c.id] = value;
    }
    notifyListeners();
  }

  int completedCountForSlot(DeliverySlot slot) {
    return customersForSlot(slot)
        .where((c) => isDeliveryChecked(c.id))
        .length;
  }

  void addCustomer(Customer customer) {
    _customers.add(customer);
    notifyListeners();
  }

  void updateCustomer(Customer customer) {
    final i = _customers.indexWhere((c) => c.id == customer.id);
    if (i >= 0) {
      _customers[i] = customer;
      notifyListeners();
    }
  }

  void markPaymentPaid(String paymentId) {
    final i = _payments.indexWhere((p) => p.id == paymentId);
    if (i >= 0) {
      _payments[i] = Payment(
        id: _payments[i].id,
        customerId: _payments[i].customerId,
        customerName: _payments[i].customerName,
        amount: _payments[i].amount,
        dueLabel: _payments[i].dueLabel,
        status: PaymentStatus.paid,
      );
      notifyListeners();
    }
  }

  void _seed() {
    const sample = [
      Customer(
        id: '1',
        name: 'Ananya Rao',
        phone: '+91 98765 43210',
        address: '12 Residency Rd, Indiranagar',
        preferredSlot: DeliverySlot.morning,
        notes: 'Fruit box + salad',
      ),
      Customer(
        id: '2',
        name: 'Vikram Mehta',
        phone: '+91 91234 56789',
        address: '88 MG Road, Apt 4B',
        preferredSlot: DeliverySlot.evening,
        notes: 'Evening meal only',
      ),
      Customer(
        id: '3',
        name: 'Priya Nair',
        phone: '+91 99887 76655',
        address: '5 Koramangala 4th Block',
        preferredSlot: DeliverySlot.morning,
      ),
      Customer(
        id: '4',
        name: 'Rahul Khan',
        phone: '+91 90909 80808',
        address: '22 HSR Layout Sector 2',
        preferredSlot: DeliverySlot.evening,
        active: false,
      ),
    ];
    _customers.addAll(sample);

    _payments.addAll(const [
      Payment(
        id: 'p1',
        customerId: '2',
        customerName: 'Vikram Mehta',
        amount: 2499,
        dueLabel: 'Due Mar 28',
      ),
      Payment(
        id: 'p2',
        customerId: '1',
        customerName: 'Ananya Rao',
        amount: 1899,
        dueLabel: 'Due Mar 30',
      ),
      Payment(
        id: 'p3',
        customerId: '3',
        customerName: 'Priya Nair',
        amount: 3200,
        dueLabel: 'Due Apr 1',
      ),
    ]);
  }
}
