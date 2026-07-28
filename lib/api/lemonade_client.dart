import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'endpoints/admin_endpoint.dart';
import 'endpoints/audio_endpoint.dart';
import 'endpoints/chat_endpoint.dart';
import 'endpoints/images_endpoint.dart';
import 'endpoints/models_endpoint.dart';
import 'exceptions.dart';
import 'http_errors.dart';
import 'net.dart';
import 'sse/sse_parser.dart';
import '../models/server_config.dart';

/// HTTP + SSE client for a single Lemonade server.
///
/// Holds one [http.Client] for connection pooling. Call [close] when the underlying
/// [ServerConfig] is no longer in use to free sockets.
///
/// Endpoints are exposed via grouped sub-objects ([chat], [images], [audio], [models],
/// [admin]). Each sub-object uses this instance for its request plumbing.
///
/// [abortInFlight] is how Stop works for OpenAI-compatible streaming: the
/// API defines **no cancel request** — the client simply drops the HTTP
/// connection (close the TCP client). That aborts mid-body SSE / downloads;
/// a fresh client is installed so later calls still work.
class LemonadeApiClient {
  final ServerConfig server;
  http.Client _http;

  late final ChatEndpoint chat;
  late final ImagesEndpoint images;
  late final AudioEndpoint audio;
  late final ModelsEndpoint models;
  late final AdminEndpoint admin;

  /// When non-null, this instance does not own [_http] and must not replace
  /// it on abort (tests inject a mock client).
  final bool _ownsHttp;

  LemonadeApiClient(this.server, {http.Client? client})
      : _http = client ?? http.Client(),
        _ownsHttp = client == null {
    chat = ChatEndpoint(this);
    images = ImagesEndpoint(this);
    audio = AudioEndpoint(this);
    models = ModelsEndpoint(this);
    admin = AdminEndpoint(this);
  }

  /// Exposed for endpoints that need the live client (after [abortInFlight]
  /// may have replaced it).
  http.Client get httpClient => _http;

  // ---------------------------------------------------------------------------
  // URL construction
  // ---------------------------------------------------------------------------

  /// Versioned API URL — for `/chat/completions`, `/images/generations`, …
  Uri apiUriFor(String path, {Map<String, String>? query}) {
    final base = server.apiUrl;
    final joined = base.endsWith('/') || path.startsWith('/') ? '$base$path' : '$base/$path';
    final uri = Uri.parse(joined);
    if (query != null && query.isNotEmpty) {
      return uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    return uri;
  }

  /// Root URL — for unversioned paths like `/live` and the WebSocket host.
  ///
  /// Preserves any reverse-proxy path prefix of the base URL: for a server at
  /// `https://host/lemonade/api/v1`, `/live` lives at `https://host/lemonade/live`,
  /// not `https://host/live`. Only the trailing `/api/v1` / `/v1` segment that
  /// [ServerConfig.apiUrl] appends is stripped.
  Uri rootUriFor(String path) {
    final apiUri = Uri.parse(server.apiUrl);
    var prefix = apiUri.path;
    while (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    if (prefix.endsWith('/api/v1')) {
      prefix = prefix.substring(0, prefix.length - '/api/v1'.length);
    } else if (prefix.endsWith('/v1')) {
      prefix = prefix.substring(0, prefix.length - '/v1'.length);
    }
    final rooted = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: '$prefix$rooted',
    );
  }

  // ---------------------------------------------------------------------------
  // Headers
  // ---------------------------------------------------------------------------

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${server.apiKey ?? "lemonade"}',
        // Per-feature cost attribution for the Nexus Router (≤128 chars).
        // Local Lemonade servers ignore the unknown header.
        'X-Nexus-Agent': 'lemonade_mobile',
      };

  Map<String, String> get jsonHeaders => {
        ..._authHeaders,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, String> get sseHeaders => {
        ..._authHeaders,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      };

  Map<String, String> get authOnlyHeaders => Map.of(_authHeaders);

  // ---------------------------------------------------------------------------
  // Internal request helpers (used by endpoints)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    // Mutations are single-shot (no retry) — a resend could duplicate work.
    return _withErrorMapping(uri.path, () async {
      final resp = await _http
          .post(uri, headers: jsonHeaders, body: jsonEncode(body))
          .timeout(timeout ?? kDefaultMutationTimeout);
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return _decodeJsonObject(resp.body);
    });
  }

  Future<Map<String, dynamic>> getJson(Uri uri, {Duration? timeout}) async {
    // Idempotent GET: retried on transient transport errors with backoff.
    return _withErrorMapping(uri.path, () {
      return retryTransientGet(() async {
        final resp = await _http
            .get(uri, headers: authOnlyHeaders)
            .timeout(timeout ?? kDefaultGetTimeout);
        _ensureOk(resp.statusCode, resp.body, uri.path);
        return _decodeJsonObject(resp.body);
      });
    });
  }

  Future<Uint8List> postJsonForBytes(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    return _withErrorMapping(uri.path, () async {
      final resp = await _http
          .post(uri, headers: jsonHeaders, body: jsonEncode(body))
          .timeout(timeout ?? kDefaultMutationTimeout);
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return resp.bodyBytes;
    });
  }

  /// POST a multipart/form-data request. [files] entries are
  /// `('field', filename, mime, bytes)`.
  Future<Map<String, dynamic>> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required List<MultipartFile> files,
    Duration? timeout,
  }) async {
    return _withErrorMapping(uri.path, () async {
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_authHeaders);
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(http.MultipartFile.fromBytes(
          f.field,
          f.bytes,
          filename: f.filename,
          contentType: f.mediaType,
        ));
      }
      final streamed = await _http
          .send(req)
          .timeout(timeout ?? kDefaultUploadTimeout);
      // The header timeout above doesn't cover a stalled body; bound it too.
      final body = await streamed.stream
          .bytesToString()
          .timeout(timeout ?? kDefaultUploadTimeout);
      _ensureOk(streamed.statusCode, body, uri.path);
      return _decodeJsonObject(body);
    });
  }

  /// Stream SSE from a POST with a JSON body. Used by chat streaming and admin
  /// endpoints that emit progress (e.g. `/v1/pull` with `stream: true`).
  ///
  /// [connectTimeout] bounds connect + response headers (first byte);
  /// [idleTimeout] bounds the gap between SSE events once the stream is open.
  /// All failures surface as typed [LemonadeApiException]s — a stall throws
  /// [StreamProtocolException]; raw ClientException/SocketException never escape.
  Stream<SseEvent> streamSseFromJsonPost(
    Uri uri,
    Map<String, dynamic> body, {
    Duration connectTimeout = kDefaultSseConnectTimeout,
    Duration idleTimeout = kDefaultSseIdleTimeout,
  }) async* {
    final endpoint = uri.path;
    http.StreamedResponse resp;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(sseHeaders)
        ..body = jsonEncode(body);
      resp = await _http.send(req).timeout(connectTimeout);
    } on TimeoutException catch (e) {
      throw ServerException('Request timed out', endpoint: endpoint, cause: e);
    } catch (e) {
      throw ServerException('Network error: $e', endpoint: endpoint, cause: e);
    }
    if (resp.statusCode != 200) {
      String errBody;
      try {
        errBody = await resp.stream.bytesToString().timeout(connectTimeout);
      } catch (_) {
        errBody = '';
      }
      _ensureOk(resp.statusCode, errBody, endpoint);
    }
    // Idle guard: if the body goes quiet for [idleTimeout] the stream is
    // considered dead — surface an error and close instead of hanging forever.
    final guarded = resp.stream.timeout(idleTimeout, onTimeout: (sink) {
      sink.addError(TimeoutException(
        'No SSE data for ${idleTimeout.inSeconds}s',
        idleTimeout,
      ));
      sink.close();
    });
    try {
      await for (final event in parseSseStream(guarded)) {
        yield event;
      }
    } on LemonadeApiException {
      rethrow;
    } on TimeoutException catch (e) {
      throw StreamProtocolException(
        'Stream stalled: no data for ${idleTimeout.inSeconds}s',
        endpoint: endpoint,
        cause: e,
      );
    } catch (e) {
      throw StreamProtocolException(
        'Stream error: $e',
        endpoint: endpoint,
        cause: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Abort in-flight work the OpenAI-compatible way: **close the connection**.
  ///
  /// Chat Completions streaming (`stream: true`) has no cancel/stop request
  /// in the wire protocol — generation stops when the client disconnects.
  /// Closing [_http] tears down every open body (SSE tokens, image download,
  /// multipart) mid-stream. A new [http.Client] is installed so the next
  /// call works. No-op when a test-injected client is in use.
  void abortInFlight() {
    if (!_ownsHttp) return;
    try {
      _http.close();
    } catch (_) {}
    _http = http.Client();
  }

  void close() {
    try {
      _http.close();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _ensureOk(int status, String body, String endpoint) => ensureHttpOk(
        status,
        body,
        endpoint,
        map400ToModelMismatch: true,
      );

  Map<String, dynamic> _decodeJsonObject(String body) => decodeJsonObject(body);

  Future<T> _withErrorMapping<T>(String endpoint, Future<T> Function() run) =>
      withTransportMapping(endpoint, run);
}

class MultipartFile {
  final String field;
  final String filename;
  final List<int> bytes;
  final String? mimeType;

  MultipartFile({
    required this.field,
    required this.filename,
    required this.bytes,
    this.mimeType,
  });

  MediaType? get mediaType {
    if (mimeType == null) return null;
    final parts = mimeType!.split('/');
    if (parts.length != 2) return null;
    return MediaType(parts[0], parts[1]);
  }
}
