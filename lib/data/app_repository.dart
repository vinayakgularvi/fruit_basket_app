import 'dart:async';
import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../models/customer.dart';
import '../models/delivery_completion_event.dart';
import '../models/lead.dart';
import '../models/needed_fruit.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart' show Payment, PaymentCollectionKind;
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/delivery_route_sort.dart';
import '../utils/payment_schedule.dart';
import '../utils/phone_launch.dart';
import 'customer_firestore.dart';
import 'leads_firestore.dart';
import 'needed_fruit_firestore.dart';

class DeliveryAgentCompensation {
  const DeliveryAgentCompensation({
    required this.username,
    required this.weeklyAllowanceRupees,
    required this.perOrderRupees,
  });

  final String username;
  final int weeklyAllowanceRupees;
  final int perOrderRupees;
}

class AppRepository extends ChangeNotifier {
  AppRepository();

  static const _kSessionLoggedIn = 'session_logged_in';
  static const _kSessionUsername = 'session_username';
  static const _kSessionRole = 'session_role';

  /// Local prefs key per slot (offline cache; canonical order is Firestore
  /// `delivery_route_order/current`).
  static String _manualDeliveryOrderPrefsKey(DeliverySlot slot) {
    return 'delivery_route_order_${slot.name}';
  }

  /// Reads newest `delivery_route_order_{slot}_yyyy-MM-dd` value if present (one-time migration).
  static String? _legacyDatedManualOrderCsv(
    SharedPreferences prefs,
    DeliverySlot slot,
  ) {
    final prefix = 'delivery_route_order_${slot.name}_';
    String? bestKey;
    for (final k in prefs.getKeys()) {
      if (!k.startsWith(prefix)) continue;
      final suffix = k.substring(prefix.length);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(suffix)) continue;
      if (bestKey == null || k.compareTo(bestKey) > 0) bestKey = k;
    }
    if (bestKey == null) return null;
    return prefs.getString(bestKey);
  }

  static Future<void> _migrateLegacyDatedManualOrderKeys(
    SharedPreferences prefs,
    DeliverySlot slot,
    String csv,
  ) async {
    final prefix = 'delivery_route_order_${slot.name}_';
    await prefs.setString(_manualDeliveryOrderPrefsKey(slot), csv);
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith(prefix)) await prefs.remove(k);
    }
  }

  final List<Customer> _customers = [];
  final List<Lead> _leads = [];
  final List<NeededFruit> _neededFruits = [];
  final Map<String, bool> _deliveryDoneToday = {};
  /// Calendar day shown on the delivery route screen (completions read/write).
  DateTime _deliveryRouteCalendarDay = dateOnly(DateTime.now());
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leadsRootSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leadsGroupSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _neededFruitsSub;
  QuerySnapshot<Map<String, dynamic>>? _lastLeadsRootSnap;
  QuerySnapshot<Map<String, dynamic>>? _lastLeadsGroupSnap;
  final StreamController<List<Lead>> _newLeadsController =
      StreamController<List<Lead>>.broadcast();
  Set<String> _leadIdsAtLastMerge = {};
  bool _leadsInitialSnapshotDone = false;
  DateTime? _lastExpiredLeadsPurgeAt;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deliveryCompletionSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _deliveryRouteOrderSub;
  final StreamController<List<DeliveryCompletionEvent>>
      _newDeliveryCompletionsController =
      StreamController<List<DeliveryCompletionEvent>>.broadcast();
  Set<String> _deliveryEventIdsAtLastMerge = {};
  bool _deliveryEventsInitialSnapshotDone = false;
  FirebaseFirestore? _firestore;
  bool _firebaseReady = false;
  bool _isLoggedIn = false;
  bool _authLoading = false;
  String? _userRole;
  String? _currentUsername;
  List<String> _deliveryAgentUsernames = const [];
  final Map<String, DeliveryAgentCompensation> _deliveryAgentCompByUsername =
      {};
  /// Saved customer id order for admin “Custom” route (per slot; reused daily).
  /// Synced across devices via Firestore `delivery_route_order/current`.
  final Map<DeliverySlot, List<String>> _manualDeliveryOrderBySlot = {};
  /// False until the first Firestore snapshot arrives (or after [refreshCustomers]).
  bool _customersReady = true;
  bool _leadsReady = true;
  bool _neededFruitsReady = true;

  bool get usesFirestore => _firebaseReady;
  bool get isLoggedIn => _isLoggedIn;
  bool get authLoading => _authLoading;
  String? get userRole => _userRole;
  String? get currentUsername => _currentUsername;
  bool get isDeliveryAgent =>
      _userRole?.trim().toLowerCase() == 'delivery_agent';
  bool get isAdmin => _userRole?.trim().toLowerCase() == 'admin';
  /// Role values from Firestore: `fruit-buyer` or `fruit_buyer`.
  bool get isFruitBuyer {
    final r = _userRole?.trim().toLowerCase() ?? '';
    return r == 'fruit-buyer' || r == 'fruit_buyer';
  }

  /// Date-only for route list, skips, and completion events. Admins can change
  /// the day; delivery agents always use today (no historical route date).
  DateTime get deliveryRouteCalendarDay =>
      isDeliveryAgent ? dateOnly(DateTime.now()) : _deliveryRouteCalendarDay;

  bool _isViewingTodaysDeliveryCalendar() =>
      _calendarDayString(deliveryRouteCalendarDay) ==
      _calendarDayString(dateOnly(DateTime.now()));

  void _applyCompletionDocToDoneMap(Map<String, dynamic>? data) {
    if (data == null) return;
    final kind = data['kind'] as String? ?? '';
    if (kind == 'stop') {
      final cid = data['customerId'] as String?;
      if (cid != null) {
        _deliveryDoneToday[cid] = true;
      }
    } else if (kind == 'mark_all') {
      final slotRaw = data['slot'] as String?;
      DeliverySlot? slot;
      for (final s in DeliverySlot.values) {
        if (s.name == slotRaw) {
          slot = s;
          break;
        }
      }
      if (slot != null) {
        for (final c in customersOnDeliveryRoute(slot)) {
          _deliveryDoneToday[c.id] = true;
        }
      }
    }
  }

  void _rebuildDeliveryDoneMapFromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    _deliveryDoneToday.clear();
    final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      snap.docs,
    )..sort((a, b) {
        final ta = a.data()['createdAt'];
        final tb = b.data()['createdAt'];
        if (ta is Timestamp && tb is Timestamp) {
          return ta.compareTo(tb);
        }
        return 0;
      });
    for (final d in docs) {
      _applyCompletionDocToDoneMap(d.data());
    }
  }

  /// Changes which calendar day the delivery screen loads completions for.
  void setDeliveryRouteCalendarDay(DateTime day) {
    if (isDeliveryAgent) return;
    final d = dateOnly(day);
    if (d == _deliveryRouteCalendarDay) return;
    _deliveryRouteCalendarDay = d;
    _deliveryDoneToday.clear();
    _deliveryEventIdsAtLastMerge = {};
    _deliveryEventsInitialSnapshotDone = false;
    _attachDeliveryCompletionSubscription();
    notifyListeners();
  }

  void _attachDeliveryCompletionSubscription() {
    _deliveryCompletionSub?.cancel();
    _deliveryCompletionSub = null;
    if (!_firebaseReady || _firestore == null) return;
    final dayStr = _calendarDayString(deliveryRouteCalendarDay);
    _deliveryCompletionSub = _firestore!
        .collection('delivery_completion_events')
        .where('calendarDay', isEqualTo: dayStr)
        .snapshots()
        .listen(
          _onDeliveryCompletionSnapshot,
          onError: (Object e, StackTrace st) {
            debugPrint('Firestore delivery_completion_events: $e\n$st');
          },
        );
  }
  List<String> get deliveryAgentUsernames =>
      List.unmodifiable(_deliveryAgentUsernames);

  /// True while Firestore is connected but the first `customers` snapshot has not arrived yet.
  bool get customersLoading => usesFirestore && !_customersReady;

  /// True while Firestore is connected but the first `leads` snapshot has not arrived yet.
  bool get leadsLoading => usesFirestore && !_leadsReady;

  /// True while Firestore is connected but the first `needed_fruits` snapshot has not arrived.
  bool get neededFruitsLoading => usesFirestore && !_neededFruitsReady;

  List<Lead> get leads => List.unmodifiable(_leads);

  List<NeededFruit> get neededFruits => List.unmodifiable(_neededFruits);

  int get pendingNeededFruitCount =>
      _neededFruits.where((e) => !e.purchased).length;

  /// Fruit names from past [needed_fruits] rows (bought + to-buy), ranked by frequency
  /// then recency; [prefix] filters case-insensitively (prefix match preferred).
  List<String> suggestedPurchaseFruitNames(String prefix, {int limit = 12}) {
    final p = prefix.trim().toLowerCase();
    final count = <String, int>{};
    final display = <String, String>{};
    for (final f in _neededFruits.reversed) {
      final raw = f.fruitName.trim();
      if (raw.isEmpty) continue;
      final k = raw.toLowerCase();
      count[k] = (count[k] ?? 0) + 1;
      display[k] = raw;
    }
    final keys = count.keys.toList();
    keys.sort((a, b) {
      if (p.isNotEmpty) {
        final as = a.startsWith(p);
        final bs = b.startsWith(p);
        if (as != bs) return as ? -1 : 1;
        final ac = a.contains(p);
        final bc = b.contains(p);
        if (ac != bc) return ac ? -1 : 1;
      }
      final byFreq = (count[b]!).compareTo(count[a]!);
      if (byFreq != 0) return byFreq;
      return a.compareTo(b);
    });
    return keys.take(limit).map((k) => display[k]!).toList();
  }

  /// Quantity lines from history for [fruitName] (exact case-insensitive match).
  /// If [fruitName] is empty, uses all fruits (still deduped, most recent first).
  /// [prefix] filters the quantity string (case-insensitive contains).
  List<String> suggestedPurchaseQuantityNotes({
    required String fruitName,
    String prefix = '',
    int limit = 10,
  }) {
    final fn = fruitName.trim().toLowerCase();
    final pr = prefix.trim().toLowerCase();
    final seen = <String>{};
    final out = <String>[];
    for (final f in _neededFruits.reversed) {
      if (fn.isNotEmpty && f.fruitName.trim().toLowerCase() != fn) continue;
      final q = f.quantityNotes.trim();
      if (q.isEmpty || seen.contains(q)) continue;
      if (pr.isNotEmpty && !q.toLowerCase().contains(pr)) continue;
      seen.add(q);
      out.add(q);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Fires when new lead document(s) appear after the first snapshot (not on initial load).
  Stream<List<Lead>> get newLeads => _newLeadsController.stream;

  /// New delivery completion docs from a delivery agent — for admin local notifications.
  Stream<List<DeliveryCompletionEvent>> get newDeliveryCompletions =>
      _newDeliveryCompletionsController.stream;

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> activeCustomers() =>
      _customers.where((c) => c.active).toList();

  /// Active customers whose plan ends today (renew / inactive follow-up).
  int get lastDayActiveCustomerCount =>
      _customers.where(subscriptionLastDayToday).length;

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
  int get perOrderPayoutRupees {
    if (isDeliveryAgent && _currentUsername != null) {
      return deliveryAgentPerOrderRupees(_currentUsername!);
    }
    return 10;
  }
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
      if (c.secondaryPlanTier != null) {
        sum += planPriceToApproximateMonthlyRupees(
          planPriceRupees: c.secondaryPlanPriceRupees,
          billingPeriod: c.billingPeriod,
        );
      }
    }
    return sum.toDouble();
  }

  /// Sum of active customers’ plan prices as an approximate weekly run-rate.
  double get weeklyRevenueEstimate {
    var sum = 0.0;
    for (final c in activeCustomers()) {
      final periodTotal = c.planPriceRupees +
          (c.secondaryPlanTier != null ? c.secondaryPlanPriceRupees : 0);
      if (c.billingPeriod == BillingPeriod.weekly) {
        sum += periodTotal;
      } else if (c.billingPeriod == BillingPeriod.trial2Day) {
        sum += periodTotal *
            (BillingPeriod.weekly.deliveryDays /
                BillingPeriod.trial2Day.deliveryDays);
      } else {
        sum += periodTotal *
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
    return _customers
        .where((c) => c.active && c.preferredSlot == slot)
        .toList();
  }

  /// Active customers in [slot] for the delivery route calendar day, excluding
  /// [Customer.skippedDeliveryDates] for that day.
  List<Customer> customersOnDeliveryRoute(DeliverySlot slot) {
    final day = deliveryRouteCalendarDay;
    return customersInDeliverySlot(slot)
        .where((c) => !customerSkipsDeliveryOnDate(c, day))
        .toList();
  }

  /// Applies saved manual order; unknown ids are appended (by name). If nothing
  /// saved, returns [fallbackOrdered] (e.g. time-optimized list).
  List<Customer> orderedCustomersForCustomRoute(
    DeliverySlot slot,
    List<Customer> base,
    List<Customer> fallbackOrdered,
  ) {
    final saved = _manualDeliveryOrderBySlot[slot];
    if (saved == null || saved.isEmpty) {
      return List<Customer>.from(fallbackOrdered);
    }
    final byId = {for (final c in base) c.id: c};
    final out = <Customer>[];
    for (final id in saved) {
      final c = byId.remove(id);
      if (c != null) out.add(c);
    }
    final rest = byId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    out.addAll(rest);
    return out;
  }

  DocumentReference<Map<String, dynamic>> _deliveryRouteOrderDocRef() {
    return _firestore!
        .collection('delivery_route_order')
        .doc('current');
  }

  bool _sameCustomerIdOrder(List<String>? a, List<String> b) {
    if (a == null) return b.isEmpty;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Parses `morning` / `evening` from Firestore (string CSV or list of ids).
  String? _routeOrderCsvFromFirestore(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is Iterable) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .join(',');
    }
    return null;
  }

  /// Applies Firestore `delivery_route_order/current` fields `morning` / `evening`
  /// (comma-separated ids). Only updates slots present in [data].
  void _applyDeliveryRouteOrderFromFirestoreData(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return;
    var changed = false;
    for (final slot in DeliverySlot.values) {
      final key = slot.name;
      if (!data.containsKey(key)) continue;
      final csv = _routeOrderCsvFromFirestore(data[key]);
      if (csv == null) continue;
      final next = csv.split(',').where((s) => s.isNotEmpty).toList();
      final cur = _manualDeliveryOrderBySlot[slot];
      if (_sameCustomerIdOrder(cur, next)) continue;
      if (next.isEmpty) {
        _manualDeliveryOrderBySlot.remove(slot);
      } else {
        _manualDeliveryOrderBySlot[slot] = next;
      }
      changed = true;
    }
    if (changed) {
      unawaited(_persistManualDeliveryOrdersToPrefs());
      notifyListeners();
    }
  }

  void _onDeliveryRouteOrderSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    try {
      if (!snap.exists) return;
      _applyDeliveryRouteOrderFromFirestoreData(snap.data());
    } catch (e, st) {
      debugPrint('_onDeliveryRouteOrderSnapshot: $e\n$st');
    }
  }

  void _subscribeDeliveryRouteOrder() {
    _deliveryRouteOrderSub?.cancel();
    _deliveryRouteOrderSub = null;
    if (!_firebaseReady || _firestore == null) return;
    _deliveryRouteOrderSub = _deliveryRouteOrderDocRef()
        .snapshots(includeMetadataChanges: true)
        .listen(
          _onDeliveryRouteOrderSnapshot,
          onError: (Object e, StackTrace st) {
            debugPrint(
              'Firestore delivery_route_order/current stream error '
              '(check Security Rules): $e\n$st',
            );
          },
        );
  }

  /// If Firestore has no usable route order yet, push local prefs so other
  /// devices converge (first-writer wins for conflicting prefs).
  Future<void> _maybeSeedLocalRouteOrderPrefsToFirestore() async {
    if (!_firebaseReady || _firestore == null) return;
    final ref = _deliveryRouteOrderDocRef();
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.server));
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          snap = await ref.get();
        } else {
          rethrow;
        }
      }
      if (snap.exists) {
        final d = snap.data();
        if (d != null) {
          for (final slot in DeliverySlot.values) {
            final csv = _routeOrderCsvFromFirestore(d[slot.name]);
            if (csv != null && csv.trim().isNotEmpty) {
              return;
            }
          }
        }
      }
      final payload = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_currentUsername != null) {
        payload['updatedBy'] = _currentUsername;
      }
      var n = 0;
      for (final slot in DeliverySlot.values) {
        final ids = _manualDeliveryOrderBySlot[slot];
        if (ids == null || ids.isEmpty) continue;
        payload[slot.name] = ids.join(',');
        n++;
      }
      if (n == 0) return;
      await ref.set(payload, SetOptions(merge: true));
      debugPrint(
        'delivery_route_order/current: seeded $n slot(s) from device prefs',
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        '_maybeSeedLocalRouteOrderPrefsToFirestore: ${e.code} ${e.message}\n$st',
      );
    }
  }

  Future<void> _pullDeliveryRouteOrderFromServer() async {
    if (!_firebaseReady || _firestore == null) return;
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _deliveryRouteOrderDocRef().get(
          const GetOptions(source: Source.server),
        );
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          snap = await _deliveryRouteOrderDocRef().get();
        } else {
          rethrow;
        }
      }
      if (!snap.exists) {
        await _maybeSeedLocalRouteOrderPrefsToFirestore();
        return;
      }
      _applyDeliveryRouteOrderFromFirestoreData(snap.data());
      await _maybeSeedLocalRouteOrderPrefsToFirestore();
    } on FirebaseException catch (e, st) {
      debugPrint('_pullDeliveryRouteOrderFromServer: ${e.code} ${e.message}\n$st');
    }
  }

  Future<void> _persistManualDeliveryOrdersToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final slot in DeliverySlot.values) {
        final ids = _manualDeliveryOrderBySlot[slot];
        if (ids == null || ids.isEmpty) {
          await prefs.remove(_manualDeliveryOrderPrefsKey(slot));
        } else {
          await prefs.setString(
            _manualDeliveryOrderPrefsKey(slot),
            ids.join(','),
          );
        }
      }
    } catch (e, st) {
      debugPrint('_persistManualDeliveryOrdersToPrefs: $e\n$st');
    }
  }

  Future<void> setManualDeliveryRouteOrder(
    DeliverySlot slot,
    List<String> customerIdsInOrder,
  ) async {
    _manualDeliveryOrderBySlot[slot] = List<String>.from(customerIdsInOrder);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _manualDeliveryOrderPrefsKey(slot),
        customerIdsInOrder.join(','),
      );
    } catch (e, st) {
      debugPrint('setManualDeliveryRouteOrder prefs: $e\n$st');
    }
    if (_firebaseReady && _firestore != null) {
      try {
        await _deliveryRouteOrderDocRef().set(
          <String, dynamic>{
            slot.name: customerIdsInOrder.join(','),
            'updatedAt': FieldValue.serverTimestamp(),
            if (_currentUsername != null) 'updatedBy': _currentUsername,
          },
          SetOptions(merge: true),
        );
      } on FirebaseException catch (e, st) {
        debugPrint(
          'setManualDeliveryRouteOrder Firestore: ${e.code} ${e.message}\n$st',
        );
      }
    }
  }

  Future<void> loadManualDeliveryRouteOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _manualDeliveryOrderBySlot.clear();
      for (final slot in DeliverySlot.values) {
        var raw = prefs.getString(_manualDeliveryOrderPrefsKey(slot));
        if (raw == null || raw.isEmpty) {
          final legacy = _legacyDatedManualOrderCsv(prefs, slot);
          if (legacy != null && legacy.isNotEmpty) {
            raw = legacy;
            await _migrateLegacyDatedManualOrderKeys(prefs, slot, legacy);
          }
        }
        if (raw != null && raw.isNotEmpty) {
          _manualDeliveryOrderBySlot[slot] =
              raw.split(',').where((s) => s.isNotEmpty).toList();
        }
      }
      notifyListeners();
      if (_firebaseReady && _firestore != null) {
        await _pullDeliveryRouteOrderFromServer();
      }
    } catch (e, st) {
      debugPrint('loadManualDeliveryRouteOrders: $e\n$st');
    }
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
    final wasChecked = isDeliveryChecked(customerId);
    _deliveryDoneToday[customerId] = !wasChecked;
    notifyListeners();
    if (!wasChecked &&
        _firebaseReady &&
        _firestore != null &&
        _currentUsername != null) {
      Customer? customer;
      for (final c in _customers) {
        if (c.id == customerId) {
          customer = c;
          break;
        }
      }
      if (customer != null) {
        unawaited(_recordDeliveryStopCompleted(customer));
      }
    }
  }

  void markAllDeliveriesDone(DeliverySlot slot, bool value) {
    final list = customersOnDeliveryRoute(slot);
    for (final c in list) {
      _deliveryDoneToday[c.id] = value;
    }
    notifyListeners();
    if (value &&
        list.isNotEmpty &&
        _firebaseReady &&
        _firestore != null &&
        _currentUsername != null) {
      unawaited(_recordDeliveryMarkAll(slot, list.length));
    }
  }

  String _calendarDayString(DateTime date) {
    final d = dateOnly(date);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _recordDeliveryStopCompleted(Customer c) async {
    final fs = _firestore;
    if (fs == null) return;
    final username = _currentUsername;
    if (username == null) return;
    final day = _calendarDayString(deliveryRouteCalendarDay);
    final role = _userRole?.trim().toLowerCase() ?? 'admin';
    try {
      await fs.collection('delivery_completion_events').add({
        'createdAt': FieldValue.serverTimestamp(),
        'calendarDay': day,
        'kind': 'stop',
        'customerId': c.id,
        'customerName': c.name,
        'slot': c.preferredSlot.name,
        'markedBy': username,
        'markedByRole': role,
      });
    } on FirebaseException catch (e, st) {
      debugPrint('_recordDeliveryStopCompleted: $e\n$st');
    }
  }

  Future<void> _recordDeliveryMarkAll(DeliverySlot slot, int count) async {
    final fs = _firestore;
    if (fs == null) return;
    final username = _currentUsername;
    if (username == null) return;
    final day = _calendarDayString(deliveryRouteCalendarDay);
    final role = _userRole?.trim().toLowerCase() ?? 'admin';
    try {
      await fs.collection('delivery_completion_events').add({
        'createdAt': FieldValue.serverTimestamp(),
        'calendarDay': day,
        'kind': 'mark_all',
        'customerName': '',
        'completedCount': count,
        'slot': slot.name,
        'markedBy': username,
        'markedByRole': role,
      });
    } on FirebaseException catch (e, st) {
      debugPrint('_recordDeliveryMarkAll: $e\n$st');
    }
  }

  int completedCountForSlot(DeliverySlot slot) {
    return customersOnDeliveryRoute(slot)
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
      _deliveryEventIdsAtLastMerge = {};
      _deliveryEventsInitialSnapshotDone = false;
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
      await _syncUserRoleFromFirestore();
      _attachDeliveryCompletionSubscription();
      _neededFruitsSub?.cancel();
      _neededFruitsReady = false;
      _neededFruitsSub = _firestore!
          .collection('needed_fruits')
          .orderBy('fruitName')
          .snapshots()
          .listen(
            _onNeededFruitsSnapshot,
            onError: (Object e, StackTrace st) {
              debugPrint(
                'Firestore needed_fruits stream error (check rules for '
                'match /needed_fruits/{id}): $e\n$st',
              );
              _neededFruitsReady = true;
              notifyListeners();
            },
          );
      await loadManualDeliveryRouteOrders();
      _subscribeDeliveryRouteOrder();
      debugPrint(
        'Firebase OK — project=${Firebase.app().options.projectId}, '
        'Firestore customers + leads + needed_fruits, database=$kFirestoreDatabaseId',
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('Firebase init failed (check database ID & rules): $e\n$st');
      _firebaseReady = false;
      _firestore = null;
      _seed();
      await loadManualDeliveryRouteOrders();
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

  /// Web stores session in [SharedPreferences] per origin; role can drift from
  /// Firestore. Re-read `users/{username}` after Firebase connects so admin
  /// accounts are not stuck on a stale `delivery_agent` session.
  Future<void> _syncUserRoleFromFirestore() async {
    if (!_firebaseReady || _firestore == null) return;
    if (!_isLoggedIn || _currentUsername == null) return;
    final username = _currentUsername!;
    try {
      final snap = await _firestore!.collection('users').doc(username).get();
      final d = snap.data();
      if (d == null || d['active'] != true) return;
      if (d['username'] != username) return;
      final raw = d['role'] as String? ?? 'admin';
      final normalized = raw.trim().isEmpty ? 'admin' : raw.trim();
      if (normalized != _userRole) {
        _userRole = normalized;
        await _saveSession(username: username, role: normalized);
        if (_firebaseReady && _firestore != null) {
          _deliveryDoneToday.clear();
          _deliveryEventIdsAtLastMerge = {};
          _deliveryEventsInitialSnapshotDone = false;
          _attachDeliveryCompletionSubscription();
          await _resyncDeliveryCompletionBaseline();
        }
        notifyListeners();
      }
    } on FirebaseException catch (e, st) {
      debugPrint(
        'syncUserRoleFromFirestore: ${e.code} ${e.message}\n$st',
      );
    }
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
      (
        id: 'fruit_buyer',
        username: 'fruit_buyer',
        password: 'fruitbuyer123',
        role: 'fruit-buyer',
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
      _deliveryAgentCompByUsername.clear();
      _deliveryAgentCompByUsername['alfa'] = const DeliveryAgentCompensation(
        username: 'alfa',
        weeklyAllowanceRupees: 0,
        perOrderRupees: 10,
      );
      return;
    }
    final snap = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'delivery_agent')
        .where('active', isEqualTo: true)
        .get();
    final names = <String>[];
    final comps = <String, DeliveryAgentCompensation>{};
    for (final d in snap.docs) {
      final data = d.data();
      final username = (data['username'] as String? ?? '').trim();
      if (username.isEmpty) continue;
      names.add(username);
      final weekly = (data['weeklyAllowanceRupees'] as num?)?.toInt() ?? 0;
      final perOrder = (data['perOrderRupees'] as num?)?.toInt() ?? 10;
      comps[username] = DeliveryAgentCompensation(
        username: username,
        weeklyAllowanceRupees: weekly < 0 ? 0 : weekly,
        perOrderRupees: perOrder < 0 ? 0 : perOrder,
      );
    }
    names.sort();
    _deliveryAgentUsernames = names;
    _deliveryAgentCompByUsername
      ..clear()
      ..addAll(comps);
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
      'weeklyAllowanceRupees': 0,
      'perOrderRupees': 10,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _refreshDeliveryAgentUsers();
    notifyListeners();
  }

  DeliveryAgentCompensation deliveryAgentCompensation(String username) {
    final u = username.trim();
    final v = _deliveryAgentCompByUsername[u];
    if (v != null) return v;
    return DeliveryAgentCompensation(
      username: u,
      weeklyAllowanceRupees: 0,
      perOrderRupees: 10,
    );
  }

  int deliveryAgentWeeklyAllowanceRupees(String username) =>
      deliveryAgentCompensation(username).weeklyAllowanceRupees;

  int deliveryAgentPerOrderRupees(String username) =>
      deliveryAgentCompensation(username).perOrderRupees;

  int estimatedMonthlyOrdersForAgent(String username) {
    final u = username.trim();
    if (u.isEmpty) return 0;
    final assignedActive = _customers
        .where((c) => c.active && c.assignedDeliveryAgentUsername == u)
        .length;
    return assignedActive * BillingPeriod.monthly.deliveryDays;
  }

  int estimatedMonthlyCompensationRupees(
    String username, {
    int? weeklyAllowanceRupees,
    int? perOrderRupees,
  }) {
    final weekly =
        weeklyAllowanceRupees ?? deliveryAgentWeeklyAllowanceRupees(username);
    final perOrder = perOrderRupees ?? deliveryAgentPerOrderRupees(username);
    final monthlyOrders = estimatedMonthlyOrdersForAgent(username);
    return (weekly * 4) + (perOrder * monthlyOrders);
  }

  Future<void> updateDeliveryAgentCompensation({
    required String username,
    required int weeklyAllowanceRupees,
    required int perOrderRupees,
  }) async {
    final u = username.trim();
    if (u.isEmpty) return;
    final weekly = weeklyAllowanceRupees < 0 ? 0 : weeklyAllowanceRupees;
    final perOrder = perOrderRupees < 0 ? 0 : perOrderRupees;
    if (_firestore == null) return;
    await _firestore!.collection('users').doc(u).set({
      'username': u,
      'role': 'delivery_agent',
      'weeklyAllowanceRupees': weekly,
      'perOrderRupees': perOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _refreshDeliveryAgentUsers();
    notifyListeners();
  }

  Future<void> addFruitBuyerUser({
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
      'role': 'fruit-buyer',
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
        final isBuyer =
            username == 'fruit_buyer' && password == 'fruitbuyer123';
        final ok = isAdmin || isAgent || isBuyer;
        _isLoggedIn = ok;
        _currentUsername = ok ? username : null;
        _userRole = isAdmin
            ? 'admin'
            : (isAgent
                ? 'delivery_agent'
                : (isBuyer ? 'fruit-buyer' : null));
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
      if (ok) {
        final r = d['role'] as String? ?? 'admin';
        _userRole = r.trim().isEmpty ? 'admin' : r.trim();
      } else {
        _userRole = null;
      }
      await _refreshDeliveryAgentUsers();
      if (ok) {
        await _saveSession(
          username: username,
          role: _userRole ?? 'admin',
        );
      } else {
        await _clearSession();
      }
      if (ok && _firebaseReady && _firestore != null) {
        await _resyncDeliveryCompletionBaseline();
        // After logout we clear `_neededFruits`; the snapshot stream does not
        // replay until data changes — refetch so fruit_buyer sees admin’s list.
        await refreshNeededFruits();
      }
      return ok;
    } finally {
      _authLoading = false;
      notifyListeners();
    }
  }

  /// After login, align seen delivery-event ids so we do not notify for history.
  Future<void> _resyncDeliveryCompletionBaseline() async {
    if (!_firebaseReady || _firestore == null) return;
    try {
      final snap = await _firestore!
          .collection('delivery_completion_events')
          .where(
            'calendarDay',
            isEqualTo: _calendarDayString(deliveryRouteCalendarDay),
          )
          .get();
      _deliveryEventIdsAtLastMerge = snap.docs.map((d) => d.id).toSet();
      _deliveryEventsInitialSnapshotDone = true;
    } on FirebaseException catch (e, st) {
      debugPrint('_resyncDeliveryCompletionBaseline: $e\n$st');
    }
  }

  void logout() {
    _isLoggedIn = false;
    _userRole = null;
    _currentUsername = null;
    _deliveryRouteCalendarDay = dateOnly(DateTime.now());
    _neededFruits.clear();
    _leadIdsAtLastMerge = {};
    _leadsInitialSnapshotDone = false;
    _lastExpiredLeadsPurgeAt = null;
    _deliveryEventIdsAtLastMerge = {};
    _deliveryEventsInitialSnapshotDone = false;
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

    unawaited(_maybePurgeExpiredLeads());
  }

  static const Duration _leadRetention = Duration(days: 30);
  static const Duration _leadPurgeThrottle = Duration(hours: 6);

  Future<void> _commitBatchedDeletes(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    if (_firestore == null || refs.isEmpty) return;
    const chunk = 450;
    for (var i = 0; i < refs.length; i += chunk) {
      final batch = _firestore!.batch();
      final end = i + chunk > refs.length ? refs.length : i + chunk;
      for (var j = i; j < end; j++) {
        batch.delete(refs[j]);
      }
      await batch.commit();
    }
  }

  /// Deletes leads whose [Lead.mobile] matches [customerPhone] (all `leads` paths).
  Future<void> _deleteLeadsMatchingCustomerPhone(String customerPhone) async {
    if (!_firebaseReady || _firestore == null) return;
    if (phoneMatchKey(customerPhone).isEmpty) return;
    try {
      final snap = await _firestore!.collectionGroup('leads').get();
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        final lead = leadFromFirestore(d);
        if (leadMobileMatchesCustomerPhone(lead.mobile, customerPhone)) {
          refs.add(d.reference);
        }
      }
      if (refs.isEmpty) return;
      await _commitBatchedDeletes(refs);
      _leads.removeWhere(
        (l) => leadMobileMatchesCustomerPhone(l.mobile, customerPhone),
      );
      debugPrint(
        'Removed ${refs.length} lead(s) matching customer phone '
        '(converted to customer).',
      );
      notifyListeners();
    } on FirebaseException catch (e, st) {
      debugPrint('_deleteLeadsMatchingCustomerPhone: ${e.code} ${e.message}\n$st');
    } catch (e, st) {
      debugPrint('_deleteLeadsMatchingCustomerPhone: $e\n$st');
    }
  }

  Future<void> _maybePurgeExpiredLeads() async {
    if (!_firebaseReady || _firestore == null) return;
    final now = DateTime.now();
    if (_lastExpiredLeadsPurgeAt != null &&
        now.difference(_lastExpiredLeadsPurgeAt!) < _leadPurgeThrottle) {
      return;
    }
    _lastExpiredLeadsPurgeAt = now;
    await _purgeExpiredLeadsOlderThanRetention();
  }

  /// Deletes leads with [Lead.createdAt] older than [_leadRetention] (requires `createdAt` on doc).
  Future<void> _purgeExpiredLeadsOlderThanRetention() async {
    if (!_firebaseReady || _firestore == null) return;
    try {
      final snap = await _firestore!.collectionGroup('leads').get();
      final cutoff = DateTime.now().subtract(_leadRetention);
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        final lead = leadFromFirestore(d);
        final t = lead.createdAt;
        if (t == null) continue;
        if (t.isBefore(cutoff)) {
          refs.add(d.reference);
        }
      }
      if (refs.isEmpty) return;
      await _commitBatchedDeletes(refs);
      final paths = refs.map((r) => r.path).toSet();
      _leads.removeWhere((l) => paths.contains(l.id));
      debugPrint(
        'Purged ${refs.length} lead(s) older than ${_leadRetention.inDays} days.',
      );
      notifyListeners();
    } on FirebaseException catch (e, st) {
      debugPrint('_purgeExpiredLeadsOlderThanRetention: ${e.code} ${e.message}\n$st');
    }
  }

  void _onDeliveryCompletionSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final wasInitialDone = _deliveryEventsInitialSnapshotDone;
    final beforeEventIds = Set<String>.from(_deliveryEventIdsAtLastMerge);
    final byId = <String, DeliveryCompletionEvent>{};
    for (final d in snap.docs) {
      final e = DeliveryCompletionEvent.fromFirestore(d);
      if (e != null) byId[d.id] = e;
    }
    final afterIds = byId.keys.toSet();

    if (beforeEventIds.isEmpty || !_isViewingTodaysDeliveryCalendar()) {
      _rebuildDeliveryDoneMapFromQuerySnapshot(snap);
    } else {
      final byDoc = {for (final d in snap.docs) d.id: d};
      for (final id in afterIds.difference(beforeEventIds)) {
        final d = byDoc[id];
        if (d != null) {
          _applyCompletionDocToDoneMap(d.data());
        }
      }
    }

    if (wasInitialDone && isAdmin) {
      final added = afterIds.difference(beforeEventIds);
      if (added.isNotEmpty && !_newDeliveryCompletionsController.isClosed) {
        final fresh = added.map((id) => byId[id]!).where(
              (e) => e.markedByRole == 'delivery_agent',
            ).toList()
          ..sort((a, b) => a.customerName.compareTo(b.customerName));
        if (fresh.isNotEmpty) {
          _newDeliveryCompletionsController.add(fresh);
        }
      }
    }
    _deliveryEventIdsAtLastMerge = afterIds;
    _deliveryEventsInitialSnapshotDone = true;
    notifyListeners();
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

  void _sortNeededFruitsLocal() {
    final pending = _neededFruits.where((e) => !e.purchased).toList()
      ..sort((a, b) {
        final c = a.fruitName.toLowerCase().compareTo(b.fruitName.toLowerCase());
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    final bought = _neededFruits.where((e) => e.purchased).toList()
      ..sort((a, b) {
        final at = a.purchasedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.purchasedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    _neededFruits
      ..clear()
      ..addAll([...pending, ...bought]);
  }

  void _onNeededFruitsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _neededFruits
      ..clear()
      ..addAll(neededFruitsFromQueryDocs(snap.docs));
    _sortNeededFruitsLocal();
    _neededFruitsReady = true;
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

  Future<void> refreshNeededFruits() async {
    if (!_firebaseReady || _firestore == null) {
      notifyListeners();
      return;
    }
    try {
      final snap = await _firestore!
          .collection('needed_fruits')
          .orderBy('fruitName')
          .get();
      _neededFruits
        ..clear()
        ..addAll(neededFruitsFromQueryDocs(snap.docs));
      _sortNeededFruitsLocal();
      _neededFruitsReady = true;
      notifyListeners();
      debugPrint('Firestore: refreshed needed_fruits (${_neededFruits.length})');
    } on FirebaseException catch (e, st) {
      debugPrint('refreshNeededFruits failed: ${e.code} ${e.message}\n$st');
    }
  }

  Future<void> addNeededFruit({
    required String fruitName,
    required String quantityNotes,
    String notes = '',
  }) async {
    if (!isAdmin && !isFruitBuyer) return;
    final fn = fruitName.trim();
    final qn = quantityNotes.trim();
    final nt = notes.trim();
    if (fn.isEmpty || qn.isEmpty) return;
    if (_firestore == null) {
      _neededFruits.add(
        NeededFruit(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          fruitName: fn,
          quantityNotes: qn,
          notes: nt,
          purchased: false,
        ),
      );
      _sortNeededFruitsLocal();
      notifyListeners();
      return;
    }
    await _firestore!.collection('needed_fruits').add({
      'fruitName': fn,
      'quantityNotes': qn,
      'notes': nt,
      'purchased': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateNeededFruit(
    String id, {
    required String fruitName,
    required String quantityNotes,
    String notes = '',
  }) async {
    if (!isAdmin && !isFruitBuyer) return;
    final fn = fruitName.trim();
    final qn = quantityNotes.trim();
    final nt = notes.trim();
    if (fn.isEmpty || qn.isEmpty) return;
    if (_firestore == null) {
      final i = _neededFruits.indexWhere((x) => x.id == id);
      if (i < 0 || _neededFruits[i].purchased) return;
      _neededFruits[i] = _neededFruits[i].copyWith(
        fruitName: fn,
        quantityNotes: qn,
        notes: nt,
      );
      _sortNeededFruitsLocal();
      notifyListeners();
      return;
    }
    final ref = _firestore!.collection('needed_fruits').doc(id);
    final snap = await ref.get();
    if (!snap.exists) return;
    final cur = neededFruitFromFirestore(snap);
    if (cur.purchased) return;
    await ref.update({
      'fruitName': fn,
      'quantityNotes': qn,
      'notes': nt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a list row as bought with weight, optional rate/kg, and total cost.
  Future<void> recordNeededFruitPurchase({
    required String id,
    required double totalWeightKg,
    double? pricePerKgRupees,
    required double totalCostRupees,
  }) async {
    if (!isAdmin && !isFruitBuyer) return;
    if (totalWeightKg <= 0 || totalCostRupees < 0) return;
    if (_firestore == null) {
      final i = _neededFruits.indexWhere((x) => x.id == id);
      if (i < 0 || _neededFruits[i].purchased) return;
      _neededFruits[i] = _neededFruits[i].copyWith(
        purchased: true,
        purchasedAt: DateTime.now(),
        pricePerKgRupees: pricePerKgRupees,
        totalWeightKg: totalWeightKg,
        totalCostRupees: totalCostRupees,
      );
      _sortNeededFruitsLocal();
      notifyListeners();
      return;
    }
    final ref = _firestore!.collection('needed_fruits').doc(id);
    final snap = await ref.get();
    if (!snap.exists) return;
    if (neededFruitFromFirestore(snap).purchased) return;
    final data = <String, dynamic>{
      'purchased': true,
      'purchasedAt': FieldValue.serverTimestamp(),
      'totalWeightKg': totalWeightKg,
      'totalCostRupees': totalCostRupees,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (pricePerKgRupees != null && pricePerKgRupees > 0) {
      data['pricePerKgRupees'] = pricePerKgRupees;
    } else {
      data['pricePerKgRupees'] = FieldValue.delete();
    }
    await ref.update(data);
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
    _deliveryCompletionSub?.cancel();
    _deliveryRouteOrderSub?.cancel();
    if (!_newLeadsController.isClosed) {
      _newLeadsController.close();
    }
    if (!_newDeliveryCompletionsController.isClosed) {
      _newDeliveryCompletionsController.close();
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
        try {
          await _deleteLeadsMatchingCustomerPhone(customer.phone);
        } catch (e, st) {
          debugPrint('delete leads after addCustomer: $e\n$st');
        }
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
        try {
          await _deleteLeadsMatchingCustomerPhone(customer.phone);
        } catch (e, st) {
          debugPrint('delete leads after updateCustomer: $e\n$st');
        }
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

  /// Renews for one billing period: new segment starts the day after current
  /// [endDate]. Clears period payment flags so the new period can be billed.
  Future<void> recontinueSubscription(String customerId) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    final newStart = dateOnly(c.endDate).add(const Duration(days: 1));
    final newEnd = endDateForBilling(newStart, c.billingPeriod);
    await updateCustomer(
      c.copyWith(
        startDate: newStart,
        endDate: newEnd,
        paymentTrackedPeriodStart: null,
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
        clearPendingDue: true,
      ),
    );
  }

  Future<void> setCustomerActive(String customerId, bool active) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    await updateCustomer(_customers[i].copyWith(active: active));
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

  /// Removes [skippedDate] from [Customer.skippedDeliveryDates] and shortens
  /// [Customer.endDate] when it had been extended for that skip.
  Future<void> undoSkipDeliveryDate(
    String customerId,
    DateTime skippedDate,
  ) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    final target = dateOnly(skippedDate);
    final had = c.skippedDeliveryDates.any((d) => dateOnly(d) == target);
    if (!had) return;
    final nextDates = c.skippedDeliveryDates
        .where((d) => dateOnly(d) != target)
        .map(dateOnly)
        .toList()
      ..sort();
    final nextSkipped = max(nextDates.length, c.skippedDeliveryDays - 1);
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
    final todayClock = dateOnly(DateTime.now());
    final anchor = paymentScheduleAnchorDate(c, todayClock);
    final pStart = periodStartForDate(c, anchor);
    if (pStart == null) return;

    final due = paymentDueForCustomer(c, anchor);
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

  /// Admin override for outstanding amount in the current billing period.
  Future<void> adjustDueAmountForCurrentPeriod(
    String customerId,
    int newDueRupees,
  ) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    if (!c.active) return;
    final todayClock = dateOnly(DateTime.now());
    final anchor = paymentScheduleAnchorDate(c, todayClock);
    final pStart = periodStartForDate(c, anchor);
    if (pStart == null) return;

    final plan = c.totalPlanPriceRupees;
    final v = newDueRupees.clamp(0, plan);
    final due = paymentDueForCustomer(c, anchor);

    if (v == 0) {
      if (due != null) {
        await recordPaymentCollection(
          customerId,
          due.kind,
          collectedAmountRupees: due.amountRupees,
        );
      }
      return;
    }

    if (v >= plan) {
      await updateCustomer(
        c.copyWith(
          paymentTrackedPeriodStart: pStart,
          clearPendingDue: true,
          weeklyPeriodPaid: false,
          monthlyAdvancePaid: false,
          monthlyBalancePaid: false,
        ),
      );
      return;
    }

    final kind = due?.kind ??
        (c.billingPeriod.usesWeeklyStylePayment
            ? PaymentCollectionKind.weeklyFull
            : PaymentCollectionKind.monthlyAdvance);
    await updateCustomer(
      c.copyWith(
        paymentTrackedPeriodStart: pStart,
        pendingDueKind: kind.name,
        pendingDueRemainingRupees: v,
        weeklyPeriodPaid: false,
        monthlyAdvancePaid: false,
        monthlyBalancePaid: false,
      ),
    );
  }

  /// Sets how much of the plan is treated as paid for this period (admin).
  /// Same as setting due to plan − paid via [adjustDueAmountForCurrentPeriod].
  Future<void> adjustPaidInCurrentPeriod(
    String customerId,
    int newPaidRupees,
  ) async {
    final i = _customers.indexWhere((c) => c.id == customerId);
    if (i < 0) return;
    final c = _customers[i];
    if (!c.active) return;
    final plan = c.totalPlanPriceRupees;
    final paid = newPaidRupees.clamp(0, plan);
    final newDue = plan - paid;
    await adjustDueAmountForCurrentPeriod(customerId, newDue);
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
        planPriceRupees: 2599,
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
        planPriceRupees: 443,
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
        planPriceRupees: 3399,
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
        planPriceRupees: 1699,
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

    _neededFruits
      ..clear()
      ..addAll(_sampleNeededFruitsLocal());
    _neededFruitsReady = true;
  }

  List<NeededFruit> _sampleNeededFruitsLocal() {
    return [
      const NeededFruit(
        id: 'local_nf1',
        fruitName: 'Banana',
        quantityNotes: '6 kg',
        notes: 'Robusta',
        purchased: false,
      ),
      NeededFruit(
        id: 'local_nf2',
        fruitName: 'Mango',
        quantityNotes: '1 crate',
        notes: '',
        purchased: true,
        purchasedAt: DateTime(2026, 1, 10, 14, 30),
        pricePerKgRupees: 120,
        totalWeightKg: 5,
        totalCostRupees: 600,
      ),
    ];
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
        price: '₹2,599',
        source: 'healthy_meal_whatsapp',
      ),
    ];
  }
}

DateTime _end(DateTime start, BillingPeriod p) =>
    endDateForBilling(start, p);
