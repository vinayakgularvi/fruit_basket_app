import '../models/lead.dart';

/// Returns `null` when [leads] is empty.
({String title, String body})? newLeadsNotificationContent(List<Lead> leads) {
  if (leads.isEmpty) return null;
  final title =
      leads.length == 1 ? 'New lead' : '${leads.length} new leads';
  final names = leads
      .map((l) => l.name.trim().isNotEmpty ? l.name.trim() : l.mobile.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  var body = names.isEmpty
      ? 'Open the app to view'
      : names.take(3).join(', ');
  if (names.length > 3) body = '$body…';
  return (title: title, body: body);
}
