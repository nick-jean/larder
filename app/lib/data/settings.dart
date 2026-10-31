import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../parser/quantity.dart';
import 'recipe_store.dart';

class Settings {
  const Settings({required this.guestId, this.clipboardBanner = true, this.units = UnitSystem.us, this.dismissedClipboard});

  final String guestId;
  final bool clipboardBanner;
  final UnitSystem units;

  /// Last clipboard link the user dismissed, so the banner doesn't nag about it again.
  final String? dismissedClipboard;

  Settings copyWith({bool? clipboardBanner, UnitSystem? units, String? dismissedClipboard}) => Settings(
        guestId: guestId,
        clipboardBanner: clipboardBanner ?? this.clipboardBanner,
        units: units ?? this.units,
        dismissedClipboard: dismissedClipboard ?? this.dismissedClipboard,
      );

  static Future<Settings> load(RecipeStore store) async {
    final raw = await store.getValue('settings');
    if (raw == null) {
      final s = Settings(guestId: 'guest-${const Uuid().v4()}');
      await s.save(store);
      return s;
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return Settings(
      guestId: j['guestId'] as String,
      clipboardBanner: j['clipboardBanner'] as bool? ?? true,
      units: j['units'] == 'metric' ? UnitSystem.metric : UnitSystem.us,
      dismissedClipboard: j['dismissedClipboard'] as String?,
    );
  }

  Future<void> save(RecipeStore store) => store.setValue(
        'settings',
        jsonEncode({'guestId': guestId, 'clipboardBanner': clipboardBanner, 'units': units.name, 'dismissedClipboard': dismissedClipboard}),
      );
}
