import '../utils/delivery_plan_dates.dart';

/// Staff record (payroll + attendance), stored in Firestore `employees`.
class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    required this.startDate,
    this.salaryRupees = 0,
    this.incentiveRupees = 0,
    this.absentDates = const [],
  });

  factory Employee.empty() => Employee(
        id: '',
        name: '',
        mobile: '',
        address: '',
        startDate: dateOnly(DateTime.now()),
      );

  /// True until first Firestore write assigns an id.
  bool get isNew => id.isEmpty;

  final String id;
  final String name;
  final String mobile;
  final String address;
  final DateTime startDate;
  final int salaryRupees;
  /// Monthly incentive in rupees (fixed amount).
  final int incentiveRupees;
  /// Calendar days marked absent (date-only semantics).
  final List<DateTime> absentDates;

  int get totalSalaryRupees => salaryRupees + incentiveRupees;

  Employee copyWith({
    String? id,
    String? name,
    String? mobile,
    String? address,
    DateTime? startDate,
    int? salaryRupees,
    int? incentiveRupees,
    List<DateTime>? absentDates,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      address: address ?? this.address,
      startDate: startDate ?? this.startDate,
      salaryRupees: salaryRupees ?? this.salaryRupees,
      incentiveRupees: incentiveRupees ?? this.incentiveRupees,
      absentDates: absentDates ?? this.absentDates,
    );
  }
}
