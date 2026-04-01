import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../models/customer.dart';
import '../models/lead.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart' show Payment, PaymentCollectionKind;
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/delivery_route_sort.dart';
import '../utils/payment_schedule.dart';
import 'customer_firestore.dart';
import 'leads_firestore.dart';

class AppRepository extends ChangeNotifier {
  AppRepository();

  static const _kSessionLoggedIn = 'session_logged_in';
  static const _kSessionUsername = 'session_username';
  static const _kSessionRole = 'session_role';

  final List<Customer> _customers = [];
  final List<Lead> _leads = [];
  final Map<String, bool> _deliveryDoneToday = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leadsRootSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leadsGroupSub;
  QuerySnapshot<Map<String, dynamic>>? _lastLeadsRootSnap;
  QuerySnapshot<Map<String, dynamic>>? _lastLeadsGroupSnap;
  final StreamController<List<Lead>> _newLeadsController =
      StreamController<List<Lead>>.broadcast();
  Set<String> _leadIdsAtLastMerge = {};
  bool _leadsInitialSnapshotDone = false;
  FirebaseFirestore? _firestore;
  bool _firebaseReady = false;
  bool _isLoggedIn = false;
  bool _authLoading = false;
  String? _userRole;
  String? _currentUsername;
  List<String> _deliveryAgentUsernames = const [];
  /// False until the first Firestore snapshot arrives (or after [refreshCustomers]).
  bool _customersReady = true;
  bool _leadsReady = true;

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

  /// True while Firestore is connected but the first `leads` snapshot has not arrived yet.
  bool get leadsLoading => usesFirestore && !_leadsReady;

  List<Lead> get leads => List.unmodifiable(_leads);

  /// Fires when new lead document(s) appear after the first snapshot (not on initial load).
  Stream<List<Lead>> get newLeads => _newLeadsController.stream;

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
  int get newCustomersPendingApprovalCount => _customers
      .where((c) => c.customerCreated && !c.adminApproved)
      .length;

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
          phone: c.phone,
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
    await _restoreSession();
    if (firebaseOptionsArePlaceholder) {
      debugPrint(
        'Firebase: replace REPLACE_ME in lib/firebase_options.dart '
        '(Firebase Console → Project settings, or run flutterfire configure). '
        'Using local sample data.',
      );
      _seed();
      notifyListeners();
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
      _leadsReady = false;
      _leads.clear();
      _leadIdsAtLastMerge = {};
      _leadsInitialSnapshotDone = false;
      _lastLeadsRootSnap = null;
      _lastLeadsGroupSnap = null;
      // Root `leads` and subcollections `users/*/leads` — merge by document path.
      _leadsRootSub = _firestore!
          .collection('leads')
          .snapshots()
          .listen(
            _onLeadsRootSnapshot,
            onError: (Object e, StackTrace st) {
              debugPrint(
                'Firestore collection("leads") stream error (check rules for '
                'match /leads/{leadId}): $e\n$st',
              );
              _leadsReady = true;
              notifyListeners();
            },
          );
      _leadsGroupSub = _firestore!
          .collectionGroup('leads')
          .snapshots()
          .listen(
            _onLeadsGroupSnapshot,
            onError: (Object e, StackTrace st) {
              debugPrint(
                'Firestore collectionGroup("leads") stream error (check rules '
                'for subcollection leads under users): $e\n$st',
              );
              _leadsReady = true;
              notifyListeners();
            },
          );
      await _ensureDefaultUser();
      await _refreshDeliveryAgentUsers();
      debugPrint(
        'Firebase OK — project=${Firebase.app().options.projectId}, '
        'Firestore customers + leads (root + collectionGroup), database=$kFirestoreDatabaseId',
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('Firebase init failed (check database ID & rules): $e\n$st');
      _firebaseReady = false;
      _firestore = null;
      _seed();
      notifyListeners();
    }
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_kSessionLoggedIn) ?? false;
    if (!loggedIn) return;
    final username = prefs.getString(_kSessionUsername);
    final role = prefs.getString(_kSessionRole);
    if (username == null || role == null) return;
    _isLoggedIn = true;
    _currentUsername = username;
    _userRole = role;
  }

  Future<void> _saveSession({
    required String username,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSessionLoggedIn, true);
    await prefs.setString(_kSessionUsername, username);
    await prefs.setString(_kSessionRole, role);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionLoggedIn);
    await prefs.remove(_kSessionUsername);
    await prefs.remove(_kSessionRole);
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
        if (ok) {
          await _saveSession(
            username: username,
            role: _userRole ?? 'delivery_agent',
          );
        } else {
          await _clearSession();
        }
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
      if (ok) {
        await _saveSession(
          username: username,
          role: _userRole ?? 'admin',
        );
      } else {
        await _clearSession();
      }
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
    _leadIdsAtLastMerge = {};
    _leadsInitialSnapshotDone = false;
    unawaited(_clearSession());
    notifyListeners();
  }

  void _onCustomersSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _customers
      ..clear()
      ..addAll(customersFromQueryDocs(snap.docs));
    _customersReady = true;
    notifyListeners();
  }

  void _mergeLeadsFromSnapshots() {
    final byPath = <String, Lead>{};
    final root = _lastLeadsRootSnap;
    final group = _lastLeadsGroupSnap;
    if (root != null) {
      for (final d in root.docs) {
        byPath[d.reference.path] = leadFromFirestore(d);
      }
    }
    if (group != null) {
      for (final d in group.docs) {
        byPath[d.reference.path] = leadFromFirestore(d);
      }
    }

    final afterIds = byPath.keys.toSet();
    // Require both root and collectionGroup snapshots before treating merges as
    // "after baseline"; otherwise the second stream's first event looks like adds.
    final hasLeadsBaseline = root != null && group != null;

    if (hasLeadsBaseline && _leadsInitialSnapshotDone) {
      final added = afterIds.difference(_leadIdsAtLastMerge);
      if (added.isNotEmpty && !_newLeadsController.isClosed) {
        final fresh = added.map((id) => byPath[id]!).toList()
          ..sort((a, b) {
            final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bt.compareTo(at);
          });
        _newLeadsController.add(fresh);
      }
    }
    _leadIdsAtLastMerge = afterIds;
    if (hasLeadsBaseline) {
      _leadsInitialSnapshotDone = true;
    }

    _leads
      ..clear()
      ..addAll(byPath.values);
    _leads.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    debugPrint(
      'Leads merged: ${_leads.length} unique '
      '(root docs=${root?.docs.length ?? "-"}, '
      'group docs=${group?.docs.length ?? "-"})',
    );
  }

  void _onLeadsRootSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _lastLeadsRootSnap = snap;
    _mergeLeadsFromSnapshots();
    _leadsReady = true;
    notifyListeners();
  }

  void _onLeadsGroupSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _lastLeadsGroupSnap = snap;
    _mergeLeadsFromSnapshots();
    _leadsReady = true;
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

  Future<void> refreshLeads() async {
    if (!_firebaseReady || _firestore == null) {
      notifyListeners();
      return;
    }
    try {
      final root = await _firestore!.collection('leads').get();
      final group = await _firestore!.collectionGroup('leads').get();
      _lastLeadsRootSnap = root;
      _lastLeadsGroupSnap = group;
      _mergeLeadsFromSnapshots();
      _leadsReady = true;
      notifyListeners();
      debugPrint('Firestore: refreshed leads (${_leads.length} unique)');
    } on FirebaseException catch (e, st) {
      debugPrint('refreshLeads failed: ${e.code} ${e.message}\n$st');
    }
  }

  /// Persists `called` / `notInterested` on the lead document ([leadPath] is full
  /// Firestore path, e.g. `users/uid/leads/docId`).
  Future<void> updateLeadFollowUp(
    String leadPath, {
    bool? called,
    bool? notInterested,
  }) async {
    if (called == null && notInterested == null) return;
    if (!_firebaseReady || _firestore == null) {
      final i = _leads.indexWhere((l) => l.id == leadPath);
      if (i >= 0) {
        _leads[i] = _leads[i].copyWith(
          called: called,
          notInterested: notInterested,
        );
        notifyListeners();
      }
      return;
    }
    try {
      final data = <String, dynamic>{};
      if (called != null) data['called'] = called;
      if (notInterested != null) data['notInterested'] = notInterested;
      await _firestore!.doc(leadPath).set(data, SetOptions(merge: true));
    } on FirebaseException catch (e, st) {
      debugPrint('updateLeadFollowUp failed: ${e.code} ${e.message}\n$st');
      rethrow;
    }
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    _leadsRootSub?.cancel();
    _leadsGroupSub?.cancel();
    if (!_newLeadsController.isClosed) {
      _newLeadsController.close();
    }
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

  Future<void> deleteCustomer(String customerId) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i >= 0) {
      _customers.removeAt(i);
      notifyListeners();
    }
    if (_firebaseReady && _firestore != null) {
      try {
        await _firestore!.collection('customers').doc(customerId).delete();
        debugPrint('Firestore: deleted customers/$customerId');
      } on FirebaseException catch (e, st) {
        debugPrint(
          'Firestore deleteCustomer failed: code=${e.code} message=${e.message}\n$st',
        );
        rethrow;
      }
    }
  }

  Future<void> approveCustomer(String customerId) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    if (c.adminApproved) return;
    await updateCustomer(
      c.copyWith(
        adminApproved: true,
      ),
    );
  }

  /// Marks [skippedDate] as skipped and extends [endDate] based on total skips.
  Future<void> skipDeliveryDate(
    String customerId,
    DateTime skippedDate,
  ) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    final skipDate = dateOnly(skippedDate);
    final nextDates = List<DateTime>.from(c.skippedDeliveryDates);
    if (!nextDates.any(
      (d) => d.year == skipDate.year && d.month == skipDate.month && d.day == skipDate.day,
    )) {
      nextDates.add(skipDate);
    }
    nextDates.sort((a, b) => a.compareTo(b));
    final nextSkipped = nextDates.length > c.skippedDeliveryDays
        ? nextDates.length
        : c.skippedDeliveryDays;
    final newEnd = endDateAfterDeliveryDays(
      dateOnly(c.startDate),
      c.billingPeriod.deliveryDays + nextSkipped,
    );
    await updateCustomer(
      c.copyWith(
        skippedDeliveryDays: nextSkipped,
        skippedDeliveryDates: nextDates,
        endDate: dateOnly(newEnd),
      ),
    );
  }

  /// Convenience action used by old UI paths.
  Future<void> skipOneDeliveryDay(String customerId) {
    return skipDeliveryDate(customerId, DateTime.now());
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
    if (due == null || !collectionKindMatchesDue(kind, due.kind)) return;

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
        case PaymentCollectionKind.monthlyBalance:
          ma = true;
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
        customerCreated: true,
        adminApproved: true,
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
        customerCreated: true,
        adminApproved: true,
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
        customerCreated: true,
        adminApproved: true,
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
        customerCreated: true,
        adminApproved: true,
      ),
    ];
    _customers.addAll(sample);

    _customersReady = true;

    _leads
      ..clear()
      ..addAll(_sampleLeadsLocal());
    _leadsReady = true;
  }

  List<Lead> _sampleLeadsLocal() {
    return [
      Lead(
        id: 'local_sample',
        billing: 'monthly',
        calendar: 'Monthly=26, Weekly=6, Sunday holiday',
        createdAt: DateTime.now(),
        goal: 'immunity',
        meal: 'breakfast',
        mealLabel: 'Breakfast (7:30am – 9am)',
        mobile: '9986732351',
        name: 'Sample lead (local)',
        plan: 'standard',
        price: '₹2,199',
        source: 'healthy_meal_whatsapp',
      ),
    ];
  }
}

DateTime _end(DateTime start, BillingPeriod p) =>
    endDateForBilling(start, p);
