import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:larder/app.dart';
import 'package:larder/data/recipe_store.dart';
import 'package:larder/data/settings.dart';
import 'package:larder/features/detail/detail_screen.dart';
import 'package:larder/models/recipe.dart';
import 'package:larder/parser/ingredient.dart';
import 'package:larder/parser/quantity.dart';
import 'package:larder/parser/text.dart';
import 'package:larder/providers.dart';
import 'package:larder/sync/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

IngredientLine line(String raw) {
  final p = parseIngredientLine(raw);
  return IngredientLine(id: 'x', raw: raw, quantity: p.quantity, quantityMax: p.quantityMax, unit: p.unit, unitRaw: p.unitRaw, item: p.item, note: p.note);
}

void main() {
  sqfliteFfiInit();

  test('scales and converts ingredient lines', () {
    expect(displayIngredient(line('2 cups flour'), 1, null), '2 cups flour');
    expect(displayIngredient(line('1 cup milk'), 1.5, null), '1½ cups milk');
    expect(displayIngredient(line('1 cup milk'), 1, UnitSystem.metric), '237 ml milk');
    expect(displayIngredient(line('salt to taste'), 2, null), 'salt to taste');
  });

  testWidgets('library shows saved recipes, review queue and detail with scaling', (tester) async {
    late RecipeStore store;
    late Settings settings;
    await tester.runAsync(() async {
      store = await RecipeStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      settings = await Settings.load(store);
      var n = 0;
      final draft = structureText('Garlic Noodles\nServes 2\n1 cup noodles\n2 cloves garlic\nCook the noodles.', 'pasted_text', newId: () => 'l${n++}');
      await store.put(Recipe.fromDraft(draft, id: 'r1', source: const RecipeSource(kind: 'manual'), now: DateTime.utc(2026, 10, 31))
        ..status = 'saved'
        ..ownerId = settings.guestId);
      await store.put(Recipe.fromDraft(RecipeDraft(title: 'Mystery card'), id: 'r2', source: const RecipeSource(kind: 'scan', scanType: 'handwritten', pageCount: 1), now: DateTime.utc(2026, 10, 30))..ownerId = settings.guestId);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          initialSettingsProvider.overrideWithValue(settings.copyWith(clipboardBanner: false)),
          authProvider.overrideWithValue(AuthService()),
        ],
        child: const LarderApp(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Garlic Noodles'), findsOneWidget);
    expect(find.text('1 recipe to check'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'garlic');
    await tester.pumpAndSettle();
    expect(find.text('Mystery card'), findsNothing);

    await tester.tap(find.text('Garlic Noodles'));
    await tester.pumpAndSettle();
    expect(find.text('2 servings'), findsOneWidget);
    expect(find.textContaining('1 cup noodles'), findsOneWidget);
    await tester.tap(find.byTooltip('More servings'));
    await tester.pumpAndSettle();
    expect(find.text('3 servings'), findsOneWidget);
    expect(find.textContaining('1½ cups noodles'), findsOneWidget);
    await tester.runAsync(store.close);
  });
}
