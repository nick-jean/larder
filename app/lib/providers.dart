import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'data/recipe_store.dart';
import 'data/settings.dart';
import 'models/recipe.dart';
import 'sync/api_client.dart';
import 'sync/auth_service.dart';
import 'sync/sync_service.dart';

const uuid = Uuid();
String newId() => uuid.v4();

final storeProvider = Provider<RecipeStore>((_) => throw UnimplementedError('override in main'));
final authProvider = Provider<AuthService>((_) => throw UnimplementedError('override in main'));
final initialSettingsProvider = Provider<Settings>((_) => throw UnimplementedError('override in main'));

final apiProvider = Provider<ApiClient>((ref) => ApiClient(tokenProvider: ref.watch(authProvider).idToken));

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => ref.watch(initialSettingsProvider);

  Future<void> update(Settings next) async {
    state = next;
    await next.save(ref.read(storeProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Signed-in Firebase uid, the dev uid for local API testing, or the local guest id.
final ownerIdProvider = Provider<String>((ref) {
  final auth = ref.watch(authProvider);
  void onAuth() => ref.invalidateSelf();
  auth.addListener(onAuth);
  ref.onDispose(() => auth.removeListener(onAuth));
  return auth.uid ?? (devUid.isNotEmpty ? devUid : ref.watch(settingsProvider).guestId);
});

class RecipesNotifier extends AsyncNotifier<List<Recipe>> {
  RecipeStore get _store => ref.read(storeProvider);

  @override
  Future<List<Recipe>> build() {
    ref.watch(ownerIdProvider);
    return _load();
  }

  Future<List<Recipe>> _load() async {
    final owner = ref.read(ownerIdProvider);
    return (await _store.recipes()).where((r) => r.ownerId == owner).toList();
  }

  Future<void> reload() async => state = AsyncData(await _load());

  /// Saves a local change: bumps the version so it wins over older copies on sync.
  Future<Recipe> save(Recipe recipe) async {
    final r = recipe.copy()
      ..ownerId = ref.read(ownerIdProvider)
      ..version = recipe.version + 1
      ..updatedAt = DateTime.now().toUtc().toIso8601String();
    await _store.put(r);
    final next = [r, ...(state.value ?? []).where((x) => x.id != r.id)].where((x) => !x.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(next);
    sync().ignore();
    return r;
  }

  Future<void> delete(Recipe recipe) => save(recipe.copy()..deleted = true);

  Future<String> sync() async {
    final auth = ref.read(authProvider);
    final api = ref.read(apiProvider);
    if (!api.configured) return 'Sync server not configured. Recipes are saved on this device.';
    final uid = auth.uid ?? (devUid.isNotEmpty ? devUid : null);
    if (uid == null) return 'Sign in to back up and sync your recipes.';
    try {
      final pulled = await SyncService(_store, api).sync(uid);
      await reload();
      return 'Synced. $pulled recipe${pulled == 1 ? '' : 's'} updated.';
    } catch (e) {
      return 'Sync failed: $e';
    }
  }
}

final recipesProvider = AsyncNotifierProvider<RecipesNotifier, List<Recipe>>(RecipesNotifier.new);

final recipeProvider = Provider.family<Recipe?, String>(
  (ref, id) => ref.watch(recipesProvider).value?.where((r) => r.id == id).firstOrNull,
);
