import 'package:flutter_test/flutter_test.dart';
import 'package:larder/data/recipe_store.dart';
import 'package:larder/data/settings.dart';
import 'package:larder/models/recipe.dart';
import 'package:larder/parser/text.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _n = 0;
String _id() => 'id${_n++}';

Recipe sample(String text, {String id = 'r1', int version = 1, String owner = 'u1'}) =>
    Recipe.fromDraft(structureText(text, 'pasted_text', newId: _id), id: id, source: const RecipeSource(kind: 'manual'), now: DateTime.utc(2026, 10, 31))
      ..ownerId = owner
      ..version = version;

void main() {
  sqfliteFfiInit();
  late RecipeStore store;

  setUp(() async => store = await RecipeStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => store.close());

  test('saves, searches by ingredient and title, hides deleted', () async {
    await store.put(sample('Lemon Pasta\n200g spaghetti\n1 lemon\nBoil the pasta.'));
    await store.put(sample('Tomato Soup\n4 tomatoes\nSimmer.', id: 'r2'));
    expect((await store.search('spaghetti')).map((r) => r.id), ['r1']);
    expect((await store.search('soup tomato')).map((r) => r.id), ['r2']);
    expect(await store.search('100%'), isEmpty);
    await store.put(sample('Tomato Soup\n4 tomatoes', id: 'r2')..deleted = true);
    expect((await store.recipes()).map((r) => r.id), ['r1']);
  });

  test('sync clears dirty only for unchanged rows and keeps newer local edits', () async {
    final r = sample('Toast\n1 slice bread\nToast it.');
    await store.put(r);
    expect(await store.dirtyRecipes(), hasLength(1));
    await store.applySync(sent: [r], received: []);
    expect(await store.dirtyRecipes(), isEmpty);

    final local = sample('Toast v3\n1 slice bread', version: 3);
    await store.put(local);
    final applied = await store.applySync(sent: [], received: [sample('Toast v2\n1 slice bread', version: 2)]);
    expect(applied, 0);
    expect((await store.recipe('r1'))!.title, 'Toast v3');
  });

  test('moves guest recipes to the signed-in account', () async {
    await store.put(sample('Guest Toast\n1 slice bread', owner: 'guest-1'));
    expect(await store.reassignOwner('guest-1', 'u9'), 1);
    expect((await store.recipe('r1'))!.ownerId, 'u9');
  });

  test('settings persist with a stable guest id', () async {
    final s = await Settings.load(store);
    await s.copyWith(clipboardBanner: false).save(store);
    final again = await Settings.load(store);
    expect(again.guestId, s.guestId);
    expect(again.clipboardBanner, isFalse);
  });
}
