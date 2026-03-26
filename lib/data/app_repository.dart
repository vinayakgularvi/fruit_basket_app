import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart' show Payment, PaymentCollectionKind;
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/delivery_route_sort.dart';
import '../utils/payment_schedule.dart';
import 'customer_firestore.dart';

class AppRepository extends ChangeNotifier {
  AppRepository();

  final List<Customer> _customers = [];
  final Map<String, bool> _deliveryDoneToday = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customerSub;
  FirebaseFirestore? _firestore;
  bool _firebaseReady = false;
  bool _isLoggedIn = false;
  bool _authLoading = false;
  String? _userRole;
  String? _currentUsername;
  List<String> _deliveryAgentUsernames = const [];
  /// False until the first Firestore snapshot arrives (or after [refreshCustomers]).
  bool _customersReady = true;

  bool get usesFirestore => _firebaseReady;
  bool get isLoggedIn => _isLoggedIn;
  bool get authLoading => _authLoading;
  String? get userRole => _userRole;
  String? get currentUsername => _currentUsername;
  bool get isDeliveryAgent => _userRole == 'delivery_agent';
  bool get isAdmin => _userRole == 'admin';
  List<String> get deliveryAgentUsernames =>
      List.unmodifiable(_deliveryAgentUsernames);

  /// True while Firestore is connected but the first `customers` snapshot has not arrived yet.
  bool get customersLoading => usesFirestore && !_customersReady;

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> activeCustomers() =>
      _customers.where((c) => c.active).toList();

  int get todayDeliveryCount {
    if (isDeliveryAgent && _currentUsername != null) {
      return _customers
          .where(
            (c) =>
                c.active &&
                c.assignedDeliveryAgentUsername == _currentUsername,
          )
          .length;
    }
    return activeCustomers().length;
  }
  int get perOrderPayoutRupees => 10;
  int get todayDeliveryPayoutRupees => todayDeliveryCount * perOrderPayoutRupees;

  /// Sum of active customers’ plan prices, scaled to an approximate monthly
  /// run-rate (weekly plans use delivery-day ratio vs monthly).
  double get monthlyRevenueEstimate {
    var sum = 0;
    for (final c in activeCustomers()) {
      sum += planPriceToApproximateMonthlyRupees(
        planPriceRupees: c.planPriceRupees,
        billingPeriod: c.billingPeriod,
      );
    }
    return sum.toDouble();
  }

  /// Sum of active customers’ plan prices as an approximate weekly run-rate.
  double get weeklyRevenueEstimate {
    var sum = 0.0;
    for (final c in activeCustomers()) {
      if (c.billingPeriod == BillingPeriod.weekly) {
        sum += c.planPriceRupees;
      } else {
        sum += c.planPriceRupees *
            (BillingPeriod.weekly.deliveryDays /
                BillingPeriod.monthly.deliveryDays);
      }
    }
    return sum;
  }

  /// Derived from active customers and today’s payment rules.
  List<Payment> get pendingPayments {
    final today = dateOnly(DateTime.now());
    final out = <Payment>[];
    for (final c in activeCustomers()) {
      final due = paymentDueForCustomer(c, today);
      if (due == null) continue;
      out.add(
        Payment(
          id: '${c.id}|${due.kind.name}',
          customerId: c.id,
          customerName: c.name,
          amount: due.amountRupees.toDouble(),
          dueLabel: due.label,
          kind: due.kind,
        ),
      );
    }
    return out;
  }

  double get totalPendingAmount =>
      pendingPayments.fold(0.0, (a, p) => a + p.amount);

  /// Active customers for [slot] (unsorted). Use for route optimization in UI.
  List<Customer> customersInDeliverySlot(DeliverySlot slot) {
    final list = _customers
        .where((c) => c.active && c.preferredSlot == slot)
        .toList();
    if (isDeliveryAgent && _currentUsername != null) {
      return list
          .where((c) => c.assignedDeliveryAgentUsername == _currentUsername)
          .toList();
    }
    return list;
  }

  List<Customer> customersForSlot(
    DeliverySlot slot, {
    DeliveryListSort sort = DeliveryListSort.byRequestedTime,
  }) {
    final list = customersInDeliverySlot(slot);
    sortDeliveryCustomers(list, sort);
    return list;
  }

  bool isDeliveryChecked(String customerId) =>
      _deliveryDoneToday[customerId] ?? false;

  void toggleDeliveryDone(String customerId) {
    _deliveryDoneToday[customerId] = !isDeliveryChecked(customerId);
    notifyListeners();
  }

  void markAllDeliveriesDone(DeliverySlot slot, bool value) {
    for (final c in customersInDeliverySlot(slot)) {
      _deliveryDoneToday[c.id] = value;
    }
    notifyListeners();
  }

  int completedCountForSlot(DeliverySlot slot) {
    return customersInDeliverySlot(slot)
        .where((c) => isDeliveryChecked(c.id))
        .length;
  }

  /// Call from `main()` before `runApp`. Uses Firestore database [kFirestoreDatabaseId].
  Future<void> initFirebase() async {
    if (firebaseOptionsArePlaceholder) {
      debugPrint(
        'Firebase: replace REPLACE_ME in lib/firebase_options.dart '
        '(Firebase Console → Project settings, or run flutterfire configure). '
        'Using local sample data.',
      );
      _seed();
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Default DB: prefer [FirebaseFirestore.instance] (same as database "(default)").
      _firestore = kFirestoreDatabaseId == '(default)'
          ? FirebaseFirestore.instance
          : FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: kFirestoreDatabaseId,
            );
      _firebaseReady = true;
      _customersReady = false;
      _customers.clear();
      _customerSub = _firestore!
          .collection('customers')
          .snapshots()
          .listen(
            _onCustomersSnapshot,
            onError: (Object e, StackTrace st) {
              debugPrint(
                'Firestore customers stream error (check Security Rules): $e\n$st',
              );
              _customersReady = true;
              notifyListeners();
            },
          );
      await _ensureDefaultUser();
      await _refreshDeliveryAgentUsers();
      debugPrint(
        'Firebase OK — project=${Firebase.app().options.projectId}, '
        'Firestore collection "customers", database=$kFirestoreDatabaseId',
      );
    } catch (e, st) {
      debugPrint('Firebase init failed (check database ID & rules): $e\n$st');
      _firebaseReady = false;
      _firestore = null;
      _seed();
    }
  }

  Future<void> _ensureDefaultUser() async {
    if (_firestore == null) return;
    final users = _firestore!.collection('users');
    const defaults = [
      (
        id: 'fruit_basket',
        username: 'fruit_basket',
        password: 'fruit_basket.26',
        role: 'admin',
      ),
      (
        id: 'alfa',
        username: 'alfa',
        password: 'alfa123',
        role: 'delivery_agent',
      ),
    ];
    for (final u in defaults) {
      final ref = users.doc(u.id);
      final snap = await ref.get();
      if (snap.exists) {
        await ref.set({
          'username': u.username,
          'password': u.password,
          'role': u.role,
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'username': u.username,
          'password': u.password,
          'role': u.role,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> _refreshDeliveryAgentUsers() async {
    if (_firestore == null) {
      _deliveryAgentUsernames = const ['alfa'];
      return;
    }
    final snap = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'delivery_agent')
        .where('active', isEqualTo: true)
        .get();
    _deliveryAgentUsernames = snap.docs
        .map((d) => (d.data()['username'] as String? ?? '').trim())
        .where((u) => u.isNotEmpty)
        .toList()
      ..sort();
  }

  Future<void> addDeliveryAgentUser({
    required String username,
    required String password,
  }) async {
    final u = username.trim();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) return;
    if (_firestore == null) return;
    await _firestore!.collection('users').doc(u).set({
      'username': u,
      'password': p,
      'role': 'delivery_agent',
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _refreshDeliveryAgentUsers();
    notifyListeners();
  }

  Future<bool> loginWithUsernamePassword(
    String username,
    String password,
  ) async {
    _authLoading = true;
    notifyListeners();
    try {
      if (_firestore == null) {
        // Fallback for local/offline mode.
        final isAdmin =
            username == 'fruit_basket' && password == 'fruit_basket.26';
        final isAgent = username == 'alfa' && password == 'alfa123';
        final ok = isAdmin || isAgent;
        _isLoggedIn = ok;
        _currentUsername = ok ? username : null;
        _userRole = isAdmin
            ? 'admin'
            : (isAgent ? 'delivery_agent' : null);
        return ok;
      }
      final snap = await _firestore!.collection('users').doc(username).get();
      final d = snap.data();
      final ok = d != null &&
          d['active'] == true &&
          d['username'] == username &&
          d['password'] == password;
      _isLoggedIn = ok;
      _currentUsername = ok ? username : null;
      _userRole = ok ? (d['role'] as String? ?? 'admin') : null;
      await _refreshDeliveryAgentUsers();
      return ok;
    } finally {
      _authLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _isLoggedIn = false;
    _userRole = null;
    _currentUsername = null;
    notifyListeners();
  }

  void _onCustomersSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _customers
      ..clear()
      ..addAll(customersFromQueryDocs(snap.docs));
    _customersReady = true;
    notifyListeners();
  }

  /// One-shot read (also used by pull-to-refresh). The real-time stream keeps updating after.
  Future<void> refreshCustomers() async {
    if (!_firebaseReady || _firestore == null) {
      notifyListeners();
      return;
    }
    try {
      final snap = await _firestore!.collection('customers').get();
      _customers
        ..clear()
        ..addAll(customersFromQueryDocs(snap.docs));
      _customersReady = true;
      notifyListeners();
      debugPrint('Firestore: refreshed customers (${_customers.length} docs)');
    } on FirebaseException catch (e, st) {
      debugPrint('refreshCustomers failed: ${e.code} ${e.message}\n$st');
    }
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    super.dispose();
  }

  Future<void> addCustomer(Customer customer) async {
    if (_firebaseReady && _firestore != null) {
      try {
        await _firestore!
            .collection('customers')
            .doc(customer.id)
            .set(customerToFirestore(customer));
        debugPrint('Firestore: wrote customers/${customer.id}');
        return;
      } on FirebaseException catch (e, st) {
        debugPrint(
          'Firestore addCustomer failed: code=${e.code} message=${e.message}\n$st',
        );
        rethrow;
      }
    }
    _customers.add(customer);
    notifyListeners();
    debugPrint(
      'addCustomer: local list only — Firebase not active (init failed or '
      'placeholder config). Data will not appear in the console.',
    );
  }

  Future<void> updateCustomer(Customer customer) async {
    final i = _customers.indexWhere((c) => c.id == customer.id);
    if (i >= 0) {
      _customers[i] = customer;
      notifyListeners();
    }
    if (_firebaseReady && _firestore != null) {
      try {
        await _firestore!
            .collection('customers')
            .doc(customer.id)
            .set(customerToFirestore(customer));
        debugPrint('Firestore: updated customers/${customer.id}');
      } on FirebaseException catch (e, st) {
        debugPrint(
          'Firestore updateCustomer failed: code=${e.code} message=${e.message}\n$st',
        );
        rethrow;
      }
    }
  }

  /// Mark a scheduled payment collected (updates customer payment flags in Firestore).
  /// [collectedAmountRupees] is the actual cash taken; omit or pass null to use the
  /// scheduled amount from [defaultCollectionAmountRupees].
  /// If less than the amount due, the remainder is stored for next-day collection.
  Future<void> recordPaymentCollection(
    String customerId,
    PaymentCollectionKind kind, {
    int? collectedAmountRupees,
  }) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    final today = dateOnly(DateTime.now());
    final pStart = periodStartForDate(c, today);
    if (pStart == null) return;

    final due = paymentDueForCustomer(c, today);
    if (due == null || due.kind != kind) return;

    final dueNow = due.amountRupees;
    final amountCollected = collectedAmountRupees ?? dueNow;
    if (amountCollected < 0) return;

    var w = c.weeklyPeriodPaid;
    var ma = c.monthlyAdvancePaid;
    var mb = c.monthlyBalancePaid;

    bool periodMatches() {
      final tr = c.paymentTrackedPeriodStart;
      if (tr == null) return false;
      final a = dateOnly(tr);
      final b = dateOnly(pStart);
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    String? pendingKind = c.pendingDueKind;
    int? pendingRem = c.pendingDueRemainingRupees;

    if (!periodMatches()) {
      w = false;
      ma = false;
      mb = false;
      pendingKind = null;
      pendingRem = null;
    }

    final fullPay = amountCollected >= dueNow;

    if (fullPay) {
      switch (kind) {
        case PaymentCollectionKind.weeklyFull:
          w = true;
          break;
        case PaymentCollectionKind.monthlyAdvance:
          ma = true;
          break;
        case PaymentCollectionKind.monthlyBalance:
          mb = true;
          break;
      }
      pendingKind = null;
      pendingRem = null;
    } else {
      pendingKind = kind.name;
      pendingRem = dueNow - amountCollected;
    }

    await updateCustomer(
      c.copyWith(
        paymentTrackedPeriodStart: pStart,
        weeklyPeriodPaid: w,
        monthlyAdvancePaid: ma,
        monthlyBalancePaid: mb,
        lastPaymentAmountRupees: amountCollected,
        lastPaymentAt: DateTime.now(),
        lastPaymentKind: kind.name,
        clearPendingDue: fullPay,
        pendingDueKind: fullPay ? null : pendingKind,
        pendingDueRemainingRupees: fullPay ? null : pendingRem,
      ),
    );
  }

  void markPaymentPaid(String paymentId) {
    final j = paymentId.lastIndexOf('|');
    if (j < 0) return;
    final customerId = paymentId.substring(0, j);
    final kindName = paymentId.substring(j + 1);
    for (final k in PaymentCollectionKind.values) {
      if (k.name == kindName) {
        unawaited(recordPaymentCollection(customerId, k));
        return;
      }
    }
  }

  void _seed() {
    final s1 = DateTime(2025, 2, 1);
    final s2 = DateTime(2025, 2, 10);
    final s3 = DateTime(2025, 3, 1);
    final s4 = DateTime(2025, 1, 15);

    final sample = [
      Customer(
        id: '1',
        name: 'Ananya Rao',
        phone: '+91 98765 43210',
        address: '12 Residency Rd, Indiranagar',
        preferredSlot: DeliverySlot.morning,
        planTier: PlanTier.standard,
        billingPeriod: BillingPeriod.monthly,
        planPriceRupees: 2199,
        startDate: s1,
        endDate: _end(s1, BillingPeriod.monthly),
        requestedDeliveryTime: '',
        notes: 'Fruit box + salad',
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
      ),
      Customer(
        id: '2',
        name: 'Vikram Mehta',
        phone: '+91 91234 56789',
        address: '88 MG Road, Apt 4B',
        preferredSlot: DeliverySlot.evening,
        planTier: PlanTier.basic,
        billingPeriod: BillingPeriod.weekly,
        planPriceRupees: 343,
        startDate: s2,
        endDate: _end(s2, BillingPeriod.weekly),
        requestedDeliveryTime: '',
        notes: 'Evening meal only',
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
      ),
      Customer(
        id: '3',
        name: 'Priya Nair',
        phone: '+91 99887 76655',
        address: '5 Koramangala 4th Block',
        preferredSlot: DeliverySlot.morning,
        planTier: PlanTier.premium,
        billingPeriod: BillingPeriod.monthly,
        planPriceRupees: 2999,
        startDate: s3,
        endDate: _end(s3, BillingPeriod.monthly),
        requestedDeliveryTime: '',
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
      ),
      Customer(
        id: '4',
        name: 'Rahul Khan',
        phone: '+91 90909 80808',
        address: '22 HSR Layout Sector 2',
        preferredSlot: DeliverySlot.evening,
        planTier: PlanTier.basic,
        billingPeriod: BillingPeriod.monthly,
        planPriceRupees: 1299,
        startDate: s4,
        endDate: _end(s4, BillingPeriod.monthly),
        requestedDeliveryTime: '',
        active: false,
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
      ),
    ];
    _customers.addAll(sample);

    _customersReady = true;
  }
}

DateTime _end(DateTime start, BillingPeriod p) =>
    endDateForBilling(start, p);
