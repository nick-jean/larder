import 'recipe.dart';

class LinkReceipt {
  const LinkReceipt({required this.platform, required this.canonicalUrl, this.creatorHandle, this.creatorName, this.captionSnippet, this.thumbnailUrl});
  final String platform;
  final String canonicalUrl;
  final String? creatorHandle;
  final String? creatorName;
  final String? captionSnippet;
  final String? thumbnailUrl;

  factory LinkReceipt.fromJson(Map<String, dynamic> j) => LinkReceipt(
        platform: j['platform'] as String,
        canonicalUrl: j['canonicalUrl'] as String,
        creatorHandle: j['creatorHandle'] as String?,
        creatorName: j['creatorName'] as String?,
        captionSnippet: j['captionSnippet'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
      );
}

class ImportLayer {
  const ImportLayer(this.name, this.status, this.detail);
  final String name; // resolve | oembed | linked_page | caption | user_text
  final String status; // ok | none | skipped | error
  final String? detail;

  String get label => switch (name) {
        'resolve' => 'Opened the link',
        'oembed' => 'Read the public caption',
        'linked_page' => 'Checked the linked recipe page',
        'caption' => 'Parsed the caption',
        _ => 'Your pasted text or screenshot',
      };
}

class ImportResult {
  const ImportResult({this.receipt, this.layers = const [], this.draft, this.needsUserText = false, this.classification = 'recipe', this.message});
  final LinkReceipt? receipt;
  final List<ImportLayer> layers;
  final RecipeDraft? draft;
  final bool needsUserText;
  final String classification; // recipe | not_recipe | unavailable
  final String? message;

  factory ImportResult.fromJson(Map<String, dynamic> j) => ImportResult(
        receipt: j['receipt'] == null ? null : LinkReceipt.fromJson(j['receipt'] as Map<String, dynamic>),
        layers: [
          for (final l in (j['layers'] as List? ?? const []).cast<Map<String, dynamic>>())
            ImportLayer(l['name'] as String, l['status'] as String, l['detail'] as String?),
        ],
        draft: j['draft'] == null ? null : RecipeDraft.fromJson(j['draft'] as Map<String, dynamic>),
        needsUserText: j['needsUserText'] as bool? ?? false,
        classification: j['classification'] as String? ?? 'recipe',
        message: j['message'] as String?,
      );
}
