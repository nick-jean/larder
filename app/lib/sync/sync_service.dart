import '../data/recipe_store.dart';
import 'api_client.dart';

/// Pushes dirty recipes and pulls server changes (last writer wins on version, then updatedAt).
class SyncService {
  SyncService(this.store, this.api);
  final RecipeStore store;
  final ApiClient api;

  /// Only recipes owned by [uid] are uploaded; guest recipes stay local until added to the account.
  Future<int> sync(String uid) async {
    if (!api.configured) return 0;
    final dirty = (await store.dirtyRecipes()).where((r) => r.ownerId == uid).toList();
    final cursorKey = 'syncCursor:$uid';
    final result = await api.sync(cursor: await store.getValue(cursorKey), recipes: dirty);
    final applied = await store.applySync(sent: dirty, received: result.recipes);
    // Conflicts mean the server copy won; drop the cursor so the next sync pulls it.
    await store.setValue(cursorKey, result.conflictIds.isEmpty ? result.cursor : null);
    return applied;
  }
}
