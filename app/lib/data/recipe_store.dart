import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/recipe.dart';

/// On-device SQLite library. Everything works offline; [dirty] rows are pushed by sync.
class RecipeStore {
  RecipeStore(this._db);
  final Database _db;

  static Future<RecipeStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'larder.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE recipes (id TEXT PRIMARY KEY, json TEXT NOT NULL, search TEXT NOT NULL, updated_at TEXT NOT NULL, dirty INTEGER NOT NULL)',
          );
          await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        },
      ),
    );
    return RecipeStore(db);
  }

  Future<void> close() => _db.close();

  /// Lower-cased text searched by the library: title, ingredients, tags, creator, site, notes.
  static String searchText(Recipe r) => [
        r.title,
        for (final i in r.ingredients) i.item,
        ...r.tags,
        r.source.creatorHandle ?? '',
        r.source.creatorName ?? '',
        r.source.label,
        r.notes,
      ].join('\n').toLowerCase();

  Recipe _decode(Map<String, Object?> row) => Recipe.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>);

  Future<List<Recipe>> recipes({bool includeDeleted = false}) async {
    final rows = await _db.query('recipes', orderBy: 'updated_at DESC');
    final all = rows.map(_decode);
    return includeDeleted ? all.toList() : all.where((r) => !r.deleted).toList();
  }

  /// Every word must appear somewhere in the recipe's searchable text.
  Future<List<Recipe>> search(String query) async {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return recipes();
    final rows = await _db.query(
      'recipes',
      where: words.map((_) => "search LIKE ? ESCAPE '\\'").join(' AND '),
      whereArgs: [for (final w in words) '%${w.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%'],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_decode).where((r) => !r.deleted).toList();
  }

  Future<Recipe?> recipe(String id) async {
    final rows = await _db.query('recipes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _decode(rows.first);
  }

  Future<void> put(Recipe r, {bool dirty = true}) => _db.insert(
        'recipes',
        {'id': r.id, 'json': jsonEncode(r.toJson()), 'search': searchText(r), 'updated_at': r.updatedAt, 'dirty': dirty ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Recipe>> dirtyRecipes() async => (await _db.query('recipes', where: 'dirty = 1')).map(_decode).toList();

  /// Marks pushed rows clean (unless edited again since) and stores server copies. Returns rows changed locally.
  Future<int> applySync({required List<Recipe> sent, required List<Recipe> received}) async {
    var applied = 0;
    await _db.transaction((txn) async {
      for (final r in sent) {
        await txn.update('recipes', {'dirty': 0}, where: 'id = ? AND json = ?', whereArgs: [r.id, jsonEncode(r.toJson())]);
      }
      for (final r in received) {
        final rows = await txn.query('recipes', where: 'id = ?', whereArgs: [r.id]);
        final local = rows.isEmpty ? null : _decode(rows.first);
        final localDirty = rows.isNotEmpty && rows.first['dirty'] == 1;
        if (local != null && localDirty && (local.version > r.version)) continue;
        await txn.insert(
          'recipes',
          {'id': r.id, 'json': jsonEncode(r.toJson()), 'search': searchText(r), 'updated_at': r.updatedAt, 'dirty': 0},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        applied++;
      }
    });
    return applied;
  }

  Future<int> reassignOwner(String from, String to) async {
    final mine = (await recipes(includeDeleted: true)).where((r) => r.ownerId == from);
    var n = 0;
    for (final r in mine) {
      r.ownerId = to;
      await put(r);
      n++;
    }
    return n;
  }

  Future<String?> getValue(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setValue(String key, String? value) async {
    if (value == null) {
      await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
