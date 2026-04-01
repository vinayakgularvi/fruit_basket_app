/// Inbound lead from Firestore `leads` collection (e.g. WhatsApp / web form).
class Lead {
  const Lead({
    required this.id,
    this.billing = '',
    this.calendar = '',
    this.createdAt,
    this.goal = '',
    this.meal = '',
    this.mealLabel = '',
    this.mobile = '',
    this.name = '',
    this.plan = '',
    this.price = '',
    this.source = '',
    this.called = false,
    this.notInterested = false,
  });

  final String id;
  final String billing;
  final String calendar;
  final DateTime? createdAt;
  final String goal;
  final String meal;
  final String mealLabel;
  final String mobile;
  final String name;
  final String plan;
  final String price;
  final String source;
  /// Staff marked that they called this lead.
  final bool called;
  /// Lead is not interested (follow-up closed).
  final bool notInterested;

  Lead copyWith({
    String? id,
    String? billing,
    String? calendar,
    DateTime? createdAt,
    String? goal,
    String? meal,
    String? mealLabel,
    String? mobile,
    String? name,
    String? plan,
    String? price,
    String? source,
    bool? called,
    bool? notInterested,
  }) {
    return Lead(
      id: id ?? this.id,
      billing: billing ?? this.billing,
      calendar: calendar ?? this.calendar,
      createdAt: createdAt ?? this.createdAt,
      goal: goal ?? this.goal,
      meal: meal ?? this.meal,
      mealLabel: mealLabel ?? this.mealLabel,
      mobile: mobile ?? this.mobile,
      name: name ?? this.name,
      plan: plan ?? this.plan,
      price: price ?? this.price,
      source: source ?? this.source,
      called: called ?? this.called,
      notInterested: notInterested ?? this.notInterested,
    );
  }
}
