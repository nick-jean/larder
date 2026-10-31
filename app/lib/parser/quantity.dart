// Dart port of packages/parser/src/quantity.ts.
const _fractions = [
  (1 / 8, '⅛'), (1 / 4, '¼'), (1 / 3, '⅓'), (3 / 8, '⅜'), (1 / 2, '½'), (5 / 8, '⅝'), (2 / 3, '⅔'), (3 / 4, '¾'), (7 / 8, '⅞'),
];

String numToString(num n) {
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toString();
}

String _trimDecimal(double n, int places) => numToString(double.parse(n.toStringAsFixed(places)));

String formatQuantity(double q) {
  if (!q.isFinite) return '';
  if (q < 0) return '-${formatQuantity(-q)}';
  final whole = q.floor();
  final frac = q - whole;
  if (frac < 0.02) return '$whole';
  if (frac > 0.98) return '${whole + 1}';
  for (final (value, glyph) in _fractions) {
    if ((frac - value).abs() <= 0.02) return whole > 0 ? '$whole$glyph' : glyph;
  }
  return _trimDecimal(q, q < 1 ? 2 : 1);
}

String formatRange(double? q, double? max) {
  if (q == null) return '';
  return max != null ? '${formatQuantity(q)}–${formatQuantity(max)}' : formatQuantity(q);
}

enum UnitSystem { us, metric }

const _usVolumeMl = {'tsp': 4.92892, 'tbsp': 14.7868, 'cup': 236.588, 'floz': 29.5735, 'pint': 473.176, 'quart': 946.353, 'gallon': 3785.41};
const _usWeightG = {'oz': 28.3495, 'lb': 453.592};
const _metricVolumeMl = {'ml': 1.0, 'l': 1000.0};
const _metricWeightG = {'g': 1.0, 'kg': 1000.0};

double _roundTo(double x, double step) => (x / step).round() * step;

double _roundMetric(double x) {
  if (x < 10) return _roundTo(x, 0.5);
  if (x < 250) return x.roundToDouble();
  return _roundTo(x, 5);
}

class Converted {
  const Converted(this.quantity, this.quantityMax, this.unit);
  final double quantity;
  final double? quantityMax;
  final String unit;
}

(double, String)? _toMetric(double q, String unit) {
  final v = _usVolumeMl[unit];
  if (v != null) {
    final ml = q * v;
    return ml >= 1000 ? (_roundTo(ml / 1000, 0.05), 'l') : (_roundMetric(ml), 'ml');
  }
  final w = _usWeightG[unit];
  if (w != null) {
    final g = q * w;
    return g >= 1000 ? (_roundTo(g / 1000, 0.05), 'kg') : (_roundMetric(g), 'g');
  }
  return null;
}

(double, String)? _toUs(double q, String unit) {
  final v = _metricVolumeMl[unit];
  if (v != null) {
    final ml = q * v;
    if (ml < 15) return (_roundTo(ml / _usVolumeMl['tsp']!, 0.25), 'tsp');
    if (ml < 60) return (_roundTo(ml / _usVolumeMl['tbsp']!, 0.5), 'tbsp');
    if (ml < 1900) return (_roundTo(ml / _usVolumeMl['cup']!, 0.25), 'cup');
    return (_roundTo(ml / _usVolumeMl['quart']!, 0.25), 'quart');
  }
  final w = _metricWeightG[unit];
  if (w != null) {
    final g = q * w;
    if (g < _usWeightG['lb']!) return (_roundTo(g / _usWeightG['oz']!, 0.25), 'oz');
    return (_roundTo(g / _usWeightG['lb']!, 0.25), 'lb');
  }
  return null;
}

Converted? convertQuantity(double q, double? max, String? unit, UnitSystem system) {
  if (unit == null) return null;
  final fn = system == UnitSystem.metric ? _toMetric : _toUs;
  final a = fn(q, unit);
  if (a == null) return null;
  if (max == null) return Converted(a.$1, null, a.$2);
  if (q == 0) return Converted(a.$1, fn(max, unit)?.$1, a.$2);
  final ratio = a.$1 / q;
  final b = system == UnitSystem.metric ? _roundMetric(max * ratio) : _roundTo(max * ratio, 0.25);
  return Converted(a.$1, b, a.$2);
}

const _labels = {
  'tsp': ('tsp', 'tsp'), 'tbsp': ('tbsp', 'tbsp'), 'cup': ('cup', 'cups'), 'floz': ('fl oz', 'fl oz'), 'oz': ('oz', 'oz'),
  'lb': ('lb', 'lb'), 'g': ('g', 'g'), 'kg': ('kg', 'kg'), 'ml': ('ml', 'ml'), 'l': ('l', 'l'), 'pint': ('pint', 'pints'),
  'quart': ('quart', 'quarts'), 'gallon': ('gallon', 'gallons'),
};

String unitLabel(String unit, double? quantity) {
  final pair = _labels[unit];
  if (pair == null) return unit;
  return quantity != null && quantity > 1 ? pair.$2 : pair.$1;
}
