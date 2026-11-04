import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:larder/parser/ingredient.dart';
import 'package:larder/parser/links.dart';
import 'package:larder/parser/quantity.dart';
import 'package:larder/parser/text.dart';

dynamic _vectors(String name) => jsonDecode(File('../packages/parser/vectors/$name.json').readAsStringSync());

double? _round(num? v) => v == null ? null : double.parse(v.toStringAsFixed(6));

void main() {
  var n = 0;
  String newId() => 'id${n++}';

  group('ingredient vectors', () {
    for (final v in _vectors('ingredients') as List) {
      test(v['raw'], () {
        final p = parseIngredientLine(v['raw'] as String);
        expect(
          {
            'isSection': p.isSection,
            'quantity': _round(p.quantity),
            'quantityMax': _round(p.quantityMax),
            'unit': p.unit,
            'unitRaw': p.unitRaw,
            'item': p.item,
            'note': p.note,
            'confidence': p.confidence.name,
          },
          {
            'isSection': v['isSection'],
            'quantity': _round(v['quantity'] as num?),
            'quantityMax': _round(v['quantityMax'] as num?),
            'unit': v['unit'],
            'unitRaw': v['unitRaw'],
            'item': v['item'],
            'note': v['note'],
            'confidence': v['confidence'],
          },
        );
      });
    }
  });

  group('quantity vectors', () {
    final q = _vectors('quantity') as Map<String, dynamic>;
    for (final f in q['format'] as List) {
      test('format ${f[0]}', () => expect(formatQuantity((f[0] as num).toDouble()), f[1]));
    }
    for (final v in q['convert'] as List) {
      test('convert ${v['quantity']} ${v['unit']} → ${v['system']}', () {
        final c = convertQuantity(
          (v['quantity'] as num).toDouble(),
          (v['max'] as num?)?.toDouble(),
          v['unit'] as String?,
          v['system'] == 'metric' ? UnitSystem.metric : UnitSystem.us,
        );
        final e = v['expect'] as Map<String, dynamic>?;
        if (e == null) {
          expect(c, isNull);
        } else {
          expect([_round(c!.quantity), _round(c.quantityMax), c.unit], [_round(e['quantity'] as num), _round(e['quantityMax'] as num?), e['unit']]);
        }
      });
    }
  });

  group('link vectors', () {
    for (final v in _vectors('links') as List) {
      test(v['input'], () {
        final c = classifyLink(v['input'] as String);
        if (v['platform'] == null) {
          expect(c, isNull);
        } else {
          expect(
            [c?.platform, c?.canonicalUrl, c?.creatorHandle, c?.postId, c?.isShortLink],
            [v['platform'], v['canonicalUrl'], v['creatorHandle'], v['postId'], v['isShortLink']],
          );
        }
      });
    }
  });

  group('text vectors', () {
    for (final v in _vectors('text') as List) {
      test(v['name'], () {
        final d = structureText(v['text'] as String, v['provenance'] as String, newId: newId);
        final e = v['expect'] as Map<String, dynamic>;
        expect(
          {
            'title': d.title,
            'servings': d.servings,
            'prepMinutes': d.prepMinutes,
            'cookMinutes': d.cookMinutes,
            'totalMinutes': d.totalMinutes,
            'ingredientCount': d.ingredients.length,
            'steps': d.steps.map((s) => s.text).toList(),
          },
          {...e, 'servings': (e['servings'] as num?)?.toDouble()},
        );
      });
    }
  });
}
