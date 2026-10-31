// Dart port of packages/parser/src/text.ts.
import '../models/recipe.dart';
import 'confidence.dart';
import 'ingredient.dart';

class InputLine {
  const InputLine(this.text, {this.confidence, this.box});
  final String text;
  final double? confidence;
  final Box? box;
}

int? parseDuration(String s) {
  final m = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)\b\.?(?:\s*(?:and\s*)?(\d+)\s*(?:m|min|mins|minutes?)\b)?|(\d+)\s*(?:m|min|mins|minutes?)\b',
    caseSensitive: false,
  ).firstMatch(s);
  if (m == null) return null;
  if (m.group(1) != null) return (double.parse(m.group(1)!) * 60 + (m.group(2) != null ? int.parse(m.group(2)!) : 0)).round();
  return int.parse(m.group(3)!);
}

final _ingredientsHdr = RegExp(r"^(?:ingredients?|you(?:'|’)?ll need|what you(?:'|’)?ll need|what you need)\s*:?\s*$", caseSensitive: false);
final _stepsHdr = RegExp(r'^(?:instructions|directions|method|steps|preparation|how to make(?: it)?|to make)\s*:?\s*$', caseSensitive: false);
final _numbered = RegExp(r'^(?:step\s*)?(\d{1,2})\s*[.):]\s*', caseSensitive: false);
const _verbs =
    'preheat|heat|mix|stir|add|bake|boil|combine|whisk|cook|pour|serve|place|season|melt|bring|remove|transfer|let|cut|chop|slice|dice|toss|fold|simmer|roast|fry|saute|sauté|grill|blend|beat|spread|sprinkle|top|drain|reserve|cover|line|grease|knead|roll|marinate|garnish|enjoy|set|put|make|start|finish|wash|peel|mince|grate|press|chill|refrigerate|freeze|cream|microwave|air fry|layer|repeat|flip|reduce|turn|allow|use|in a|in another|once|when|while|meanwhile|then|after|finally';
final _imperative = RegExp('^(?:$_verbs)\\b', caseSensitive: false);
final _servings = RegExp(
  r'\b(?:serves|servings?|makes|yields?|portions?)\s*:?\s*(\d+)(?:\s*(?:-|–|to)\s*\d+)?|(\d+)(?:\s*(?:-|–|to)\s*\d+)?\s*(?:servings|portions|people)\b',
  caseSensitive: false,
);
final _timeLabel = RegExp(r'\b(prep|preparation|cook|cooking|bake|baking|total|active|ready in)\b(?:\s*time)?\s*:?', caseSensitive: false);
final _temp = RegExp(r'\b\d{3}\s*°?\s*(?:f|c|degrees)\b|°', caseSensitive: false);
final _noise = RegExp(
  r'^(?:follow\b|like and\b|save (?:this|for later)|comment\b|link in (?:my )?bio|full recipe (?:on|at|in)\b|recipe (?:on|at|in) (?:my )?(?:bio|blog|website)|tag a friend|#)',
  caseSensitive: false,
);

final _unquantified = RegExp(
  r'^(?:some|a few|a little)\b|\b(?:to taste|for (?:serving|garnish|topping|frying|dusting|greasing)|optional|as needed|a pinch|a handful|a dash)\b',
  caseSensitive: false,
);

bool isStepLike(String line) {
  final t = stripBullet(line);
  if (_numbered.hasMatch(t) && !looksLikeIngredient(t.replaceFirst(_numbered, ''))) return true;
  if (_imperative.hasMatch(t)) return true;
  return t.length > 70 && RegExp(r'[.!]$').hasMatch(t);
}

String _cleanText(String s) => s
    .replaceAll(RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false), '')
    .replaceAll(RegExp(r'(?:^|\s)#[\p{L}\p{N}_]+', unicode: true), ' ')
    .replaceAll(
      RegExp(r'\b(?:(?:full )?recipe )?(?:link )?in (?:my )?bio\b|\bfollow (?:me|us) for more\b.*$', caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _cleanTitle(String s) {
  // ignore: valid_regexps
  var t = s.replaceAll(RegExp(r'\p{Extended_Pictographic}|\u{FE0F}|\u{200D}', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceFirst(RegExp(r'^(?:recipe|title)\s*:\s*', caseSensitive: false), '').replaceFirst(RegExp(r'[\s:|\-–—·]+$'), '');
  if (t.length > 100) {
    final sentence = RegExp(r'^(.{10,100}?)[.!?](\s|$)').firstMatch(t);
    t = sentence != null ? sentence.group(1)! : '${t.substring(0, 80).trim()}…';
  }
  return t;
}

class _Meta {
  int? servings;
  String? yieldText;
  int? prep;
  int? cook;
  int? total;
}

bool _readMeta(String line, _Meta meta) {
  if (line.length > 80 || looksLikeIngredient(line)) return false;
  final segments = line.split(RegExp(r'\s*[·|•;,]\s*|\s+-\s+')).where((s) => s.isNotEmpty);
  final found = _Meta();
  var any = false;
  for (final seg in segments) {
    final s = _servings.firstMatch(seg);
    if (s != null) {
      found.servings = int.parse(s.group(1) ?? s.group(2)!);
      found.yieldText = seg.trim();
      any = true;
      continue;
    }
    final label = _timeLabel.firstMatch(seg);
    final minutes = parseDuration(seg);
    if (minutes != null &&
        (label != null || seg.replaceAll(RegExp(r'[\d.\s]|h(?:ou)?rs?|hours?|m(?:in(?:ute)?s?)?|and', caseSensitive: false), '').length <= 2)) {
      final kind = label?.group(1)!.toLowerCase() ?? 'total';
      if (kind.startsWith('prep') || kind == 'active') {
        found.prep = minutes;
      } else if (kind.startsWith('cook') || kind.startsWith('bak')) {
        found.cook = minutes;
      } else {
        found.total = minutes;
      }
      any = true;
      continue;
    }
    if (_temp.hasMatch(seg) && seg.length <= 25) continue;
    return false;
  }
  if (!any) return false;
  meta.servings ??= found.servings;
  meta.yieldText ??= found.yieldText;
  meta.prep ??= found.prep;
  meta.cook ??= found.cook;
  meta.total ??= found.total;
  return true;
}

/// Turns caption, pasted or OCR text into a draft. Nothing is invented: absent fields stay null.
RecipeDraft structureLines(List<InputLine> input, String provenance, {required String Function() newId}) {
  final meta = _Meta();
  final ingredients = <IngredientLine>[];
  final steps = <StepLine>[];
  var title = '';
  var titleConf = Confidence.high;
  var metaConf = Confidence.high;
  var mode = 'pre';

  final lines = [
    for (final l in input)
      for (final text in l.text.split(RegExp(r'\r?\n')))
        InputLine(_cleanText(text), confidence: l.confidence, box: l.box),
  ].where((l) => l.text.isNotEmpty && !_noise.hasMatch(l.text));

  void addStep(String text, InputLine l) {
    final conf = ocrConfidence(l.confidence);
    final prev = steps.isEmpty ? null : steps.last;
    final continues = prev != null &&
        !_numbered.hasMatch(text) &&
        !RegExp(r'[.!?)]$').hasMatch(prev.text) &&
        RegExp(r'^[a-z(]').hasMatch(text);
    if (prev != null && continues) {
      prev.text = '${prev.text} $text';
      prev.confidence = minConfidence([prev.confidence, conf]);
      if (l.box != null && prev.box != null && l.box!.page != prev.box!.page) {
        prev.seam = true;
        prev.confidence = minConfidence([prev.confidence, Confidence.medium]);
      }
      return;
    }
    final body = text.replaceFirst(_numbered, '').trim();
    if (body.isEmpty) return;
    steps.add(StepLine(id: newId(), text: body, confidence: conf, provenance: provenance, box: l.box));
  }

  void addIngredient(String text, InputLine l) {
    final p = parseIngredientLine(text);
    if (p.item.isEmpty && !p.isSection) return;
    ingredients.add(IngredientLine(
      id: newId(),
      raw: p.raw,
      isSection: p.isSection,
      quantity: p.quantity,
      quantityMax: p.quantityMax,
      unit: p.unit,
      unitRaw: p.unitRaw,
      item: p.item,
      note: p.note,
      confidence: minConfidence([p.confidence, ocrConfidence(l.confidence)]),
      provenance: provenance,
      box: l.box,
    ));
  }

  for (final l in lines) {
    final text = l.text;
    if (_ingredientsHdr.hasMatch(text)) {
      mode = 'ingredients';
      continue;
    }
    if (_stepsHdr.hasMatch(text)) {
      mode = 'steps';
      continue;
    }
    if (mode != 'steps' && _readMeta(text, meta)) {
      metaConf = minConfidence([metaConf, ocrConfidence(l.confidence)]);
      continue;
    }
    if (mode == 'steps') {
      addStep(text, l);
      continue;
    }
    if (mode == 'ingredients') {
      if (isSectionHeader(text) || looksLikeIngredient(text) || !isStepLike(text)) {
        addIngredient(text, l);
      } else {
        mode = 'steps';
        addStep(text, l);
      }
      continue;
    }
    if (title.isNotEmpty && steps.isEmpty && isSectionHeader(text)) {
      mode = 'ingredients';
      addIngredient(text, l);
    } else if (looksLikeIngredient(text)) {
      addIngredient(text, l);
    } else if (ingredients.isNotEmpty && steps.isEmpty && _unquantified.hasMatch(text) && !isStepLike(text)) {
      // Unquantified ingredients right after the list ("Salt to taste", "Parsley, for serving").
      addIngredient(text, l);
    } else if (steps.isNotEmpty || ingredients.isNotEmpty || isStepLike(text)) {
      addStep(text, l);
    } else if (title.isEmpty) {
      title = _cleanTitle(text);
      titleConf = minConfidence([provenance == 'linked_page' ? Confidence.high : Confidence.medium, ocrConfidence(l.confidence)]);
    }
  }

  return RecipeDraft(
    title: title,
    servings: meta.servings?.toDouble(),
    yieldText: meta.yieldText,
    prepMinutes: meta.prep,
    cookMinutes: meta.cook,
    totalMinutes: meta.total,
    ingredients: ingredients,
    steps: steps,
    titleConfidence: title.isNotEmpty ? titleConf : Confidence.low,
    servingsConfidence: metaConf,
    timesConfidence: metaConf,
    foundIn: ingredients.isNotEmpty || steps.isNotEmpty || title.isNotEmpty ? [provenance] : [],
  );
}

RecipeDraft structureText(String text, String provenance, {required String Function() newId}) =>
    structureLines([InputLine(text)], provenance, newId: newId);
