/// Best-effort parse of total weight in kg from free-text quantity (e.g. "5 kg").
double? guessWeightKgFromQuantityNotes(String raw) {
  final s = raw.toLowerCase().replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final kg = RegExp(r'(\d+(?:\.\d+)?)\s*kg').firstMatch(s);
  if (kg != null) return double.tryParse(kg.group(1)!);
  final g = RegExp(r'(\d+(?:\.\d+)?)\s*g\b').firstMatch(s);
  if (g != null) {
    final v = double.tryParse(g.group(1)!);
    if (v != null) return v / 1000;
  }
  return null;
}
