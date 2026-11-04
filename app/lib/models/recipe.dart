// Mirrors the Zod schema in packages/parser/src/schema.ts (JSON field names must match the API).
import '../parser/confidence.dart';

class Box {
  const Box({required this.page, required this.x, required this.y, required this.w, required this.h});
  final int page;
  final double x, y, w, h;

  factory Box.fromJson(Map<String, dynamic> j) => Box(
        page: (j['page'] as num).toInt(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
      );
  Map<String, dynamic> toJson() => {'page': page, 'x': x, 'y': y, 'w': w, 'h': h};
}

Box? _box(Object? j) => j == null ? null : Box.fromJson(j as Map<String, dynamic>);
double? _d(Object? v) => (v as num?)?.toDouble();
int? _i(Object? v) => (v as num?)?.toInt();

class IngredientLine {
  IngredientLine({
    required this.id,
    required this.raw,
    this.isSection = false,
    this.quantity,
    this.quantityMax,
    this.unit,
    this.unitRaw,
    required this.item,
    this.note,
    this.confidence = Confidence.high,
    this.provenance = 'manual',
    this.box,
    this.alternatives = const [],
  });

  final String id;
  String raw;
  bool isSection;
  double? quantity;
  double? quantityMax;
  String? unit;
  String? unitRaw;
  String item;
  String? note;
  Confidence confidence;
  String provenance;
  Box? box;
  List<String> alternatives;

  IngredientLine copy() => IngredientLine.fromJson(toJson());

  factory IngredientLine.fromJson(Map<String, dynamic> j) => IngredientLine(
        id: j['id'] as String,
        raw: j['raw'] as String? ?? '',
        isSection: j['isSection'] as bool? ?? false,
        quantity: _d(j['quantity']),
        quantityMax: _d(j['quantityMax']),
        unit: j['unit'] as String?,
        unitRaw: j['unitRaw'] as String?,
        item: j['item'] as String? ?? '',
        note: j['note'] as String?,
        confidence: Confidence.parse(j['confidence'] as String?),
        provenance: j['provenance'] as String? ?? 'manual',
        box: _box(j['box']),
        alternatives: (j['alternatives'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'raw': raw,
        'isSection': isSection,
        'quantity': quantity,
        'quantityMax': quantityMax,
        'unit': unit,
        'unitRaw': unitRaw,
        'item': item,
        'note': note,
        'confidence': confidence.name,
        'provenance': provenance,
        if (box != null) 'box': box!.toJson(),
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
      };
}

class StepLine {
  StepLine({required this.id, required this.text, this.confidence = Confidence.high, this.provenance = 'manual', this.box, this.seam = false});

  final String id;
  String text;
  Confidence confidence;
  String provenance;
  Box? box;
  bool seam;

  StepLine copy() => StepLine.fromJson(toJson());

  factory StepLine.fromJson(Map<String, dynamic> j) => StepLine(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        confidence: Confidence.parse(j['confidence'] as String?),
        provenance: j['provenance'] as String? ?? 'manual',
        box: _box(j['box']),
        seam: j['seam'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'confidence': confidence.name,
        'provenance': provenance,
        if (box != null) 'box': box!.toJson(),
        if (seam) 'seam': true,
      };
}

class RecipeDraft {
  RecipeDraft({
    this.title = '',
    this.servings,
    this.yieldText,
    this.prepMinutes,
    this.cookMinutes,
    this.totalMinutes,
    List<IngredientLine>? ingredients,
    List<StepLine>? steps,
    this.titleConfidence = Confidence.high,
    this.servingsConfidence = Confidence.high,
    this.timesConfidence = Confidence.high,
    List<String>? foundIn,
  })  : ingredients = ingredients ?? [],
        steps = steps ?? [],
        foundIn = foundIn ?? [];

  String title;
  double? servings;
  String? yieldText;
  int? prepMinutes;
  int? cookMinutes;
  int? totalMinutes;
  List<IngredientLine> ingredients;
  List<StepLine> steps;
  Confidence titleConfidence;
  Confidence servingsConfidence;
  Confidence timesConfidence;
  List<String> foundIn;

  factory RecipeDraft.fromJson(Map<String, dynamic> j) {
    final fc = (j['fieldConfidence'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RecipeDraft(
      title: j['title'] as String? ?? '',
      servings: _d(j['servings']),
      yieldText: j['yieldText'] as String?,
      prepMinutes: _i(j['prepMinutes']),
      cookMinutes: _i(j['cookMinutes']),
      totalMinutes: _i(j['totalMinutes']),
      ingredients: [for (final e in (j['ingredients'] as List? ?? const [])) IngredientLine.fromJson(e as Map<String, dynamic>)],
      steps: [for (final e in (j['steps'] as List? ?? const [])) StepLine.fromJson(e as Map<String, dynamic>)],
      titleConfidence: Confidence.parse(fc['title'] as String?),
      servingsConfidence: Confidence.parse(fc['servings'] as String?),
      timesConfidence: Confidence.parse(fc['times'] as String?),
      foundIn: (j['foundIn'] as List?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> draftJson() => {
        'title': title,
        'servings': servings,
        'yieldText': yieldText,
        'prepMinutes': prepMinutes,
        'cookMinutes': cookMinutes,
        'totalMinutes': totalMinutes,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'steps': [for (final s in steps) s.toJson()],
        'fieldConfidence': {'title': titleConfidence.name, 'servings': servingsConfidence.name, 'times': timesConfidence.name},
        'foundIn': foundIn,
      };

  /// Lines and fields the review screen should highlight.
  int get lowConfidenceCount =>
      ingredients.where((i) => i.confidence == Confidence.low).length +
      steps.where((s) => s.confidence == Confidence.low || s.seam).length +
      (titleConfidence == Confidence.low ? 1 : 0);
}

class RecipeSource {
  const RecipeSource({
    required this.kind,
    this.url,
    this.creatorHandle,
    this.creatorName,
    this.scanType,
    this.pageCount = 0,
    this.retrievedAt,
  });

  final String kind; // tiktok | instagram | facebook | web | scan | manual
  final String? url;
  final String? creatorHandle;
  final String? creatorName;
  final String? scanType; // cookbook | handwritten | screenshot
  final int pageCount;
  final String? retrievedAt;

  bool get isSocial => kind == 'tiktok' || kind == 'instagram' || kind == 'facebook';

  String get label {
    switch (kind) {
      case 'tiktok':
        return 'TikTok';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'web':
        final host = url == null ? null : Uri.tryParse(url!)?.host.replaceFirst(RegExp(r'^www\.'), '');
        return host ?? 'Web';
      case 'scan':
        return switch (scanType) { 'handwritten' => 'Handwritten card', 'screenshot' => 'Screenshot', _ => 'Cookbook' };
      default:
        return 'Typed';
    }
  }

  factory RecipeSource.fromJson(Map<String, dynamic> j) => RecipeSource(
        kind: j['kind'] as String? ?? 'manual',
        url: j['url'] as String?,
        creatorHandle: j['creatorHandle'] as String?,
        creatorName: j['creatorName'] as String?,
        scanType: j['scanType'] as String?,
        pageCount: _i(j['pageCount']) ?? 0,
        retrievedAt: j['retrievedAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'url': url,
        'creatorHandle': creatorHandle,
        'creatorName': creatorName,
        'scanType': scanType,
        'pageCount': pageCount,
        'retrievedAt': retrievedAt,
      };
}

class Recipe extends RecipeDraft {
  Recipe({
    required this.id,
    this.ownerId = '',
    this.status = 'saved',
    required this.source,
    this.notes = '',
    List<String>? tags,
    List<String>? imageKeys,
    this.thumbnailUrl,
    this.wantToCook = false,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.deleted = false,
    super.title,
    super.servings,
    super.yieldText,
    super.prepMinutes,
    super.cookMinutes,
    super.totalMinutes,
    super.ingredients,
    super.steps,
    super.titleConfidence,
    super.servingsConfidence,
    super.timesConfidence,
    super.foundIn,
  })  : tags = tags ?? [],
        imageKeys = imageKeys ?? [];

  final String id;
  String ownerId;
  String status; // review | saved
  RecipeSource source;
  String notes;
  List<String> tags;
  List<String> imageKeys; // local file paths of source photos
  String? thumbnailUrl;
  bool wantToCook;
  String createdAt;
  String updatedAt;
  int version;
  bool deleted;

  bool get needsReview => status == 'review';

  factory Recipe.fromDraft(
    RecipeDraft d, {
    required String id,
    required RecipeSource source,
    required DateTime now,
    String? thumbnailUrl,
    List<String>? imageKeys,
  }) {
    final j = d.draftJson();
    return Recipe.fromJson({
      ...j,
      'id': id,
      'ownerId': '',
      'status': 'review',
      'source': source.toJson(),
      'notes': '',
      'tags': <String>[],
      'imageKeys': imageKeys ?? <String>[],
      'thumbnailUrl': thumbnailUrl,
      'wantToCook': false,
      'createdAt': now.toUtc().toIso8601String(),
      'updatedAt': now.toUtc().toIso8601String(),
      'version': 0,
      'deleted': false,
    });
  }

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final d = RecipeDraft.fromJson(j);
    return Recipe(
      id: j['id'] as String,
      ownerId: j['ownerId'] as String? ?? '',
      status: j['status'] as String? ?? 'saved',
      source: RecipeSource.fromJson((j['source'] as Map).cast<String, dynamic>()),
      notes: j['notes'] as String? ?? '',
      tags: (j['tags'] as List?)?.cast<String>() ?? [],
      imageKeys: (j['imageKeys'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: j['thumbnailUrl'] as String?,
      wantToCook: j['wantToCook'] as bool? ?? false,
      createdAt: j['createdAt'] as String,
      updatedAt: j['updatedAt'] as String,
      version: _i(j['version']) ?? 0,
      deleted: j['deleted'] as bool? ?? false,
      title: d.title,
      servings: d.servings,
      yieldText: d.yieldText,
      prepMinutes: d.prepMinutes,
      cookMinutes: d.cookMinutes,
      totalMinutes: d.totalMinutes,
      ingredients: d.ingredients,
      steps: d.steps,
      titleConfidence: d.titleConfidence,
      servingsConfidence: d.servingsConfidence,
      timesConfidence: d.timesConfidence,
      foundIn: d.foundIn,
    );
  }

  Recipe copy() => Recipe.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        ...draftJson(),
        'id': id,
        'ownerId': ownerId,
        'status': status,
        'source': source.toJson(),
        'notes': notes,
        'tags': tags,
        'imageKeys': imageKeys,
        'thumbnailUrl': thumbnailUrl,
        'wantToCook': wantToCook,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'version': version,
        'deleted': deleted,
      };
}
