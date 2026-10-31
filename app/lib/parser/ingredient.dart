// Dart port of packages/parser/src/ingredient.ts. Keep in sync; test/parser_vectors_test.dart checks the shared vectors.
import 'confidence.dart';

const Map<String, List<String>> units = {
  'tsp': ['teaspoon', 'teaspoons', 'tsp', 'tsps', 'tsp.', 'teasp', 't'],
  'tbsp': ['tablespoon', 'tablespoons', 'tbsp', 'tbsps', 'tbsp.', 'tbs', 'tbs.', 'tbl', 'tbl.', 'T'],
  'cup': ['cup', 'cups', 'c', 'c.'],
  'floz': ['fl oz', 'fl. oz', 'fl. oz.', 'fl oz.', 'fluid ounce', 'fluid ounces'],
  'oz': ['ounce', 'ounces', 'oz', 'oz.'],
  'lb': ['pound', 'pounds', 'lb', 'lbs', 'lb.', 'lbs.'],
  'g': ['g', 'gram', 'grams', 'gr', 'g.'],
  'kg': ['kg', 'kilogram', 'kilograms', 'kilo', 'kilos', 'kg.'],
  'ml': ['ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres', 'ml.'],
  'l': ['l', 'liter', 'liters', 'litre', 'litres'],
  'pint': ['pint', 'pints', 'pt', 'pt.'],
  'quart': ['quart', 'quarts', 'qt', 'qt.'],
  'gallon': ['gallon', 'gallons', 'gal', 'gal.'],
  'pinch': ['pinch', 'pinches'],
  'dash': ['dash', 'dashes'],
  'clove': ['clove', 'cloves'],
  'can': ['can', 'cans'],
  'package': ['package', 'packages', 'pkg', 'pkg.', 'packet', 'packets'],
  'stick': ['stick', 'sticks'],
  'slice': ['slice', 'slices'],
  'bunch': ['bunch', 'bunches'],
  'sprig': ['sprig', 'sprigs'],
  'handful': ['handful', 'handfuls'],
  'piece': ['piece', 'pieces', 'pc', 'pcs'],
};

const _caseSensitive = {'t', 'T'};

final List<(String, String)> _aliases = [
  for (final e in units.entries)
    for (final a in e.value) (a, e.key),
]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

const _vulgar = {
  '½': '1/2', '⅓': '1/3', '⅔': '2/3', '¼': '1/4', '¾': '3/4', '⅕': '1/5', '⅖': '2/5', '⅗': '3/5', '⅘': '4/5',
  '⅙': '1/6', '⅚': '5/6', '⅛': '1/8', '⅜': '3/8', '⅝': '5/8', '⅞': '7/8',
};

String normalizeFractions(String s) {
  var out = s.replaceAll(RegExp('[\u2044\u2215]'), '/').replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-');
  return out.replaceAllMapped(RegExp(r'(\d)?([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])'), (m) {
    final whole = m.group(1);
    final frac = _vulgar[m.group(2)]!;
    return whole != null ? '$whole $frac' : frac;
  });
}

const _num = r'(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?|\.\d+)';
final qtyRe = RegExp('^($_num)(?:\\s*(?:-|to)\\s*($_num))?');

double? parseNumber(String s) {
  final t = s.trim();
  var m = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(t);
  if (m != null) {
    final d = int.parse(m.group(3)!);
    return d == 0 ? null : int.parse(m.group(1)!) + int.parse(m.group(2)!) / d;
  }
  m = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (m != null) {
    final d = int.parse(m.group(2)!);
    return d == 0 ? null : int.parse(m.group(1)!) / d;
  }
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  return n != null && n.isFinite ? n : null;
}

({String unit, String raw})? matchUnit(String s) {
  for (final (alias, unit) in _aliases) {
    if (s.length < alias.length) continue;
    final candidate = s.substring(0, alias.length);
    final same = _caseSensitive.contains(alias) ? candidate == alias : candidate.toLowerCase() == alias.toLowerCase();
    if (!same) continue;
    final next = s.length > alias.length ? s[alias.length] : '';
    if (next.isNotEmpty && RegExp('[A-Za-z]').hasMatch(next)) continue;
    if (!alias.endsWith('.') && next == '.') return (unit: unit, raw: s.substring(0, alias.length + 1));
    return (unit: unit, raw: candidate);
  }
  return null;
}

class ParsedIngredient {
  const ParsedIngredient({
    required this.raw,
    this.isSection = false,
    this.quantity,
    this.quantityMax,
    this.unit,
    this.unitRaw,
    this.item = '',
    this.note,
    this.confidence = Confidence.medium,
  });

  final String raw;
  final bool isSection;
  final double? quantity;
  final double? quantityMax;
  final String? unit;
  final String? unitRaw;
  final String item;
  final String? note;
  final Confidence confidence;
}

final _noQtyOk = RegExp(
  r'\b(to taste|to serve|for serving|for garnish|garnish|as needed|optional|some|a few|a little|handful|pinch|dash)\b',
  caseSensitive: false,
);
final _junk = RegExp(r'[|{}<>~^_=\\]|[a-z][0-9][a-z]|\d[OoIl]\b|\b[OoIl]\d');

String stripBullet(String line) => line.replaceFirst(RegExp(r'^\s*[-–—•*·▢□☐▪◦●○]+\s*'), '').trim();

({String item, String? note}) _splitNote(String rest) {
  var depth = 0;
  for (var i = 0; i < rest.length; i++) {
    final ch = rest[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth = depth > 0 ? depth - 1 : 0;
    } else if (ch == ',' && depth == 0) {
      final item = rest.substring(0, i).trim();
      final note = rest.substring(i + 1).trim();
      if (item.isNotEmpty) return (item: item, note: note.isEmpty ? null : note);
    }
  }
  return (item: rest.trim(), note: null);
}

bool isSectionHeader(String line) {
  final t = line.trim();
  if (t.isEmpty || RegExp(r'^\d').hasMatch(normalizeFractions(t))) return false;
  final words = t.replaceFirst(RegExp(r':$'), '').split(RegExp(r'\s+')).length;
  if (t.endsWith(':') && words <= 6) return true;
  return RegExp(r'^for (the )?[a-z]', caseSensitive: false).hasMatch(t) && words <= 5 && !t.contains(',');
}

ParsedIngredient parseIngredientLine(String rawInput) {
  final raw = rawInput.trim();
  final line = stripBullet(raw);
  if (isSectionHeader(line)) {
    return ParsedIngredient(
      raw: raw,
      isSection: true,
      item: line.replaceFirst(RegExp(r':\s*$'), '').trim(),
      confidence: Confidence.high,
    );
  }

  var rest = normalizeFractions(line);
  rest = rest.replaceFirstMapped(
    RegExp(r'^(\d+(?:\.\d+)?|\d+\s+\d+/\d+|\d+/\d+)(?=[A-Za-z])'),
    (m) => '${m.group(1)} ',
  );

  double? quantity;
  double? quantityMax;
  final qm = qtyRe.firstMatch(rest);
  if (qm != null) {
    quantity = parseNumber(qm.group(1)!);
    quantityMax = qm.group(2) != null ? parseNumber(qm.group(2)!) : null;
    rest = rest.substring(qm.group(0)!.length).trim();
  } else {
    final am = RegExp(r'^(a|an|one)\s+(?=\S)', caseSensitive: false).firstMatch(rest);
    if (am != null && matchUnit(rest.substring(am.group(0)!.length)) != null) {
      quantity = 1;
      rest = rest.substring(am.group(0)!.length);
    }
  }

  String? sizeNote;
  if (quantity != null) {
    final pm = RegExp(r'^\(([^)]{1,40})\)\s*').firstMatch(rest);
    if (pm != null) {
      sizeNote = pm.group(1)!.trim();
      rest = rest.substring(pm.group(0)!.length);
    }
  }

  String? unit;
  String? unitRaw;
  if (quantity != null) {
    final um = matchUnit(rest);
    if (um != null) {
      unit = um.unit;
      unitRaw = um.raw;
      rest = rest.substring(um.raw.length).trim();
    }
  }
  rest = rest.replaceFirst(RegExp(r'^of\s+', caseSensitive: false), '');

  final split = _splitNote(rest);
  final notes = [sizeNote, split.note].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  Confidence confidence;
  if (quantity != null) {
    confidence = split.item.isNotEmpty ? Confidence.high : Confidence.low;
  } else {
    confidence = _noQtyOk.hasMatch(line) ? Confidence.high : Confidence.medium;
  }
  if (_junk.hasMatch(line)) confidence = Confidence.low;

  return ParsedIngredient(
    raw: raw,
    quantity: quantity,
    quantityMax: quantityMax,
    unit: unit,
    unitRaw: unitRaw,
    item: split.item,
    note: notes.isEmpty ? null : notes,
    confidence: confidence,
  );
}

bool looksLikeIngredient(String line) {
  final t = stripBullet(line);
  if (t.isEmpty) return false;
  final n = normalizeFractions(t);
  if (qtyRe.hasMatch(n.replaceFirstMapped(RegExp(r'^(\d+)(?=[A-Za-z])'), (m) => '${m.group(1)} '))) {
    if (RegExp(r'^\d+\s*(°|degrees|min|minutes|hours?|hrs?|seconds?)\b', caseSensitive: false).hasMatch(n)) return false;
    return t.length <= 90;
  }
  return RegExp(r'^(a|an)\s', caseSensitive: false).hasMatch(t) &&
      matchUnit(t.replaceFirst(RegExp(r'^(a|an)\s+', caseSensitive: false), '')) != null;
}
