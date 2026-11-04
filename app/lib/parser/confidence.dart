enum Confidence {
  high,
  medium,
  low;

  static Confidence parse(String? s) => Confidence.values.firstWhere((c) => c.name == s, orElse: () => Confidence.medium);
}

Confidence minConfidence(Iterable<Confidence> cs) =>
    cs.fold(Confidence.high, (a, b) => a.index >= b.index ? a : b);

Confidence ocrConfidence(double? c) {
  if (c == null) return Confidence.high;
  if (c >= 0.85) return Confidence.high;
  if (c >= 0.6) return Confidence.medium;
  return Confidence.low;
}
