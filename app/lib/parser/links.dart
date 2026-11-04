// Dart port of packages/parser/src/links.ts.
class ClassifiedLink {
  const ClassifiedLink({required this.platform, required this.canonicalUrl, this.creatorHandle, this.postId, this.isShortLink = false});
  final String platform;
  final String canonicalUrl;
  final String? creatorHandle;
  final String? postId;
  final bool isShortLink;
}

final _tracking = RegExp(
  r'^(utm_.*|igsh|igshid|is_from_webapp|sender_device|sender_web_id|_r|_t|fbclid|mibextid|si|share_id|share_app_id|share_link_id|tt_from|u_code|user_id|timestamp|rdid|sharer_language|refer|ref|source|web_id|_d|checksum|sec_uid|share_item_id|preview_pb|region|social_sharing|lang)$',
  caseSensitive: false,
);

Uri? toUrl(String input) {
  final trimmed = input.trim().replaceFirst(RegExp(r'''[)\].,!?'"]+$'''), '');
  if (trimmed.isEmpty || RegExp(r'\s').hasMatch(trimmed)) return null;
  final withScheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(trimmed) ? trimmed : 'https://$trimmed';
  final url = Uri.tryParse(withScheme);
  if (url == null || (url.scheme != 'http' && url.scheme != 'https')) return null;
  if (!url.host.contains('.')) return null;
  return url;
}

String _serialize(Uri url, List<String> query) {
  final path = url.path.isEmpty ? '/' : url.path;
  final port = url.hasPort ? ':${url.port}' : '';
  return 'https://${url.host.toLowerCase()}$port$path${query.isEmpty ? '' : '?${query.join('&')}'}';
}

ClassifiedLink? classifyLink(String input) {
  final url = toUrl(input);
  if (url == null) return null;
  final h = url.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|mobile|web)\.'), '');
  final query = url.query.split('&').where((kv) => kv.isNotEmpty && !_tracking.hasMatch(Uri.decodeQueryComponent(kv.split('=').first))).toList();
  final params = {for (final kv in query) Uri.decodeQueryComponent(kv.split('=').first): Uri.decodeQueryComponent(kv.contains('=') ? kv.substring(kv.indexOf('=') + 1) : '')};
  final full = _serialize(url, query);
  final path = url.path.replaceFirst(RegExp(r'/+$'), '');

  if (h == 'tiktok.com' || h.endsWith('.tiktok.com')) {
    if (h == 'vm.tiktok.com' || h == 'vt.tiktok.com' || path.startsWith('/t/')) {
      return ClassifiedLink(platform: 'tiktok', canonicalUrl: full, isShortLink: true);
    }
    final m = RegExp(r'^/@([\w.-]+)/(?:video|photo)/(\d+)').firstMatch(path);
    final handle = RegExp(r'^/@([\w.-]+)').firstMatch(path)?.group(1);
    return ClassifiedLink(
      platform: 'tiktok',
      canonicalUrl: m != null ? 'https://www.tiktok.com/@${m.group(1)}/video/${m.group(2)}' : full,
      creatorHandle: handle != null ? '@$handle' : null,
      postId: m?.group(2),
    );
  }
  if (h == 'instagram.com' || h == 'instagr.am') {
    final m = RegExp(r'^/(?:[\w.]+/)?(p|reel|reels|tv)/([\w-]+)').firstMatch(path);
    final kind = m == null ? null : (m.group(1) == 'reels' ? 'reel' : m.group(1));
    return ClassifiedLink(
      platform: 'instagram',
      canonicalUrl: m != null ? 'https://www.instagram.com/$kind/${m.group(2)}/' : full,
      postId: m?.group(2),
    );
  }
  if (h == 'facebook.com' || h == 'fb.watch' || h == 'fb.com' || h.endsWith('.facebook.com')) {
    final isShort = h == 'fb.watch' || path.startsWith('/share/');
    final reel = RegExp(r'^/reel/(\d+)').firstMatch(path)?.group(1);
    final video = RegExp(r'/videos/(?:[\w.-]+/)?(\d+)').firstMatch(path)?.group(1);
    final watch = path == '/watch' ? params['v'] : null;
    final owner = RegExp(r'^/([\w.]+)/(?:videos|posts)/').firstMatch(path)?.group(1);
    var canonical = full;
    if (reel != null) {
      canonical = 'https://www.facebook.com/reel/$reel';
    } else if (watch != null) {
      canonical = 'https://www.facebook.com/watch/?v=$watch';
    }
    return ClassifiedLink(platform: 'facebook', canonicalUrl: canonical, creatorHandle: owner, postId: reel ?? video ?? watch, isShortLink: isShort);
  }
  return ClassifiedLink(platform: 'web', canonicalUrl: full);
}

/// First http(s) URL in pasted text, if any (for the clipboard banner and paste field).
String? firstUrl(String text) {
  final m = RegExp(r'''(?:https?://|www\.)[^\s<>"']+''', caseSensitive: false).firstMatch(text);
  return m == null ? null : toUrl(m.group(0)!)?.toString();
}
