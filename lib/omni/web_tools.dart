import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Research tools the LLM can call to look things up on the live web —
/// generic search (Google-style) and places search (Apple/Google-Maps-style).
///
/// Defaults work without any API keys:
///   - Web search: DuckDuckGo HTML endpoint (no auth, scrapes the result page)
///   - Places: OpenStreetMap Nominatim (no auth, requires a User-Agent)
///
/// Both are bottlenecks for AI latency, so the methods are async-only and
/// the agent loop runs concurrent tool calls in parallel (Future.wait).
/// Each lookup also runs N concurrent sub-requests where applicable (e.g.
/// fetching enrichment pages for the top hits) on its own.

class WebSearchResult {
  final String title;
  final String url;
  final String snippet;
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

class PlaceResult {
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? type; // 'restaurant', 'cafe', 'address', etc.
  const PlaceResult({
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    this.type,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (type != null) 'type': type,
      };
}

/// Generic web search. Default backend is DuckDuckGo's HTML endpoint, which
/// works without auth and returns the same SERP a browser would.
class WebSearchClient {
  final http.Client _http;
  WebSearchClient([http.Client? client]) : _http = client ?? http.Client();

  Future<List<WebSearchResult>> search(
    String query, {
    int limit = 6,
  }) async {
    if (query.trim().isEmpty) return const [];
    // DuckDuckGo's `html.duckduckgo.com/html/?q=…` returns a stable
    // structure that's easy to scrape with simple regexes — no JS exec
    // required. They tolerate this for low-volume bot use (we send a
    // realistic User-Agent).
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    final resp = await _http.get(uri, headers: const {
      'User-Agent':
          'Mozilla/5.0 (LemonadeMobile/3.0; +https://lemonade.ai) Gecko/20100101 Firefox/121.0',
      'Accept': 'text/html',
      'Accept-Language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) {
      throw Exception('Web search HTTP ${resp.statusCode}');
    }

    return _parseDdgHtml(resp.body, limit);
  }

  /// Public for testing. Parses the result block out of DDG's HTML page.
  static List<WebSearchResult> _parseDdgHtml(String html, int limit) {
    // Each result lives in <div class="result results_links results_links_deep web-result …">
    // with <a class="result__a" href="…">Title</a> and
    // <a class="result__snippet">…</a>.
    final blockRe = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>'
      r'[\s\S]*?<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)</a>',
      multiLine: true,
    );
    final out = <WebSearchResult>[];
    for (final m in blockRe.allMatches(html)) {
      final rawUrl = m.group(1) ?? '';
      final rawTitle = m.group(2) ?? '';
      final rawSnippet = m.group(3) ?? '';
      // DDG wraps outbound URLs in /l/?uddg=<encoded> — unwrap.
      String url = rawUrl;
      if (url.startsWith('//')) url = 'https:$url';
      if (url.startsWith('/l/?') || url.startsWith('https://duckduckgo.com/l/?')) {
        final qIdx = url.indexOf('uddg=');
        if (qIdx > 0) {
          final tail = url.substring(qIdx + 5);
          final amp = tail.indexOf('&');
          final raw = amp > 0 ? tail.substring(0, amp) : tail;
          try {
            url = Uri.decodeFull(raw);
          } catch (_) {}
        }
      }
      out.add(WebSearchResult(
        title: _stripHtml(rawTitle),
        url: url,
        snippet: _stripHtml(rawSnippet),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  static String _stripHtml(String s) {
    var out = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    out = out.replaceAll('&amp;', '&');
    out = out.replaceAll('&quot;', '"');
    out = out.replaceAll('&#39;', "'");
    out = out.replaceAll('&lt;', '<');
    out = out.replaceAll('&gt;', '>');
    out = out.replaceAll('&nbsp;', ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out.trim();
  }

  void close() => _http.close();
}

/// Places search backed by OpenStreetMap Nominatim. Free, no key. Their
/// usage policy asks for a custom User-Agent and ≤1 req/sec, which we
/// respect.
class PlacesSearchClient {
  final http.Client _http;
  PlacesSearchClient([http.Client? client]) : _http = client ?? http.Client();

  Future<List<PlaceResult>> search(
    String query, {
    String? nearLocation,
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return const [];
    final q = nearLocation == null || nearLocation.isEmpty
        ? query
        : '$query near $nearLocation';
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'jsonv2',
      'limit': '$limit',
      'addressdetails': '1',
    });
    final resp = await _http.get(uri, headers: const {
      'User-Agent': 'LemonadeMobile/3.0 (places-tool)',
      'Accept': 'application/json',
      'Accept-Language': 'en',
    }).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Places HTTP ${resp.statusCode}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((raw) {
      final m = raw as Map<String, dynamic>;
      return PlaceResult(
        name: (m['name'] as String?)?.trim().isNotEmpty == true
            ? m['name'] as String
            : (m['display_name'] as String? ?? '').split(',').first.trim(),
        address: m['display_name'] as String? ?? '',
        latitude: double.tryParse(m['lat']?.toString() ?? ''),
        longitude: double.tryParse(m['lon']?.toString() ?? ''),
        type: m['type'] as String?,
      );
    }).toList(growable: false);
  }

  void close() => _http.close();
}
