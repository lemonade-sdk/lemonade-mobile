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
import 'sse/sse_parser.dart';
import '../models/server_config.dart';

/// HTTP + SSE client for a single Lemonade server.
///
/// Holds one [http.Client] for connection pooling. Call [close] when the underlying
/// [ServerConfig] is no longer in use to free sockets.
///
/// Endpoints are exposed via grouped sub-objects ([chat], [images], [audio], [models],
/// [admin]). Each sub-object uses this instance for its request plumbing.
class LemonadeApiClient {
  final ServerConfig server;
  final http.Client _http;

  late final ChatEndpoint chat;
  late final ImagesEndpoint images;
  late final AudioEndpoint audio;
  late final ModelsEndpoint models;
  late final AdminEndpoint admin;

  LemonadeApiClient(this.server, {http.Client? client}) : _http = client ?? http.Client() {
    chat = ChatEndpoint(this);
    images = ImagesEndpoint(this);
    audio = AudioEndpoint(this);
    models = ModelsEndpoint(this);
    admin = AdminEndpoint(this);
  }

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
  Uri rootUriFor(String path) {
    final apiUri = Uri.parse(server.apiUrl);
    return Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: path,
    );
  }

  // ---------------------------------------------------------------------------
  // Headers
  // ---------------------------------------------------------------------------

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${server.apiKey ?? "lemonade"}',
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
    return _withErrorMapping(uri.path, () async {
      final req = _http.post(uri, headers: jsonHeaders, body: jsonEncode(body));
      final resp = timeout != null ? await req.timeout(timeout) : await req;
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return _decodeJsonObject(resp.body);
    });
  }

  Future<Map<String, dynamic>> getJson(Uri uri, {Duration? timeout}) async {
    return _withErrorMapping(uri.path, () async {
      final req = _http.get(uri, headers: authOnlyHeaders);
      final resp = timeout != null ? await req.timeout(timeout) : await req;
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return _decodeJsonObject(resp.body);
    });
  }

  Future<Uint8List> postJsonForBytes(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    return _withErrorMapping(uri.path, () async {
      final req = _http.post(uri, headers: jsonHeaders, body: jsonEncode(body));
      final resp = timeout != null ? await req.timeout(timeout) : await req;
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
      final send = _http.send(req);
      final streamed = timeout != null ? await send.timeout(timeout) : await send;
      final body = await streamed.stream.bytesToString();
      _ensureOk(streamed.statusCode, body, uri.path);
      return _decodeJsonObject(body);
    });
  }

  /// Stream SSE from a POST with a JSON body. Used by chat streaming and admin
  /// endpoints that emit progress (e.g. `/v1/pull` with `stream: true`).
  Stream<SseEvent> streamSseFromJsonPost(
    Uri uri,
    Map<String, dynamic> body,
  ) async* {
    final req = http.Request('POST', uri)
      ..headers.addAll(sseHeaders)
      ..body = jsonEncode(body);
    final resp = await _http.send(req);
    if (resp.statusCode != 200) {
      final errBody = await resp.stream.bytesToString();
      _ensureOk(resp.statusCode, errBody, uri.path);
    }
    yield* parseSseStream(resp.stream);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void close() => _http.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _ensureOk(int status, String body, String endpoint) {
    if (status >= 200 && status < 300) return;
    final message = _extractErrorMessage(body) ?? 'HTTP $status';
    switch (status) {
      case 400:
        throw ModelMismatchException(message, endpoint: endpoint);
      case 401:
      case 403:
        throw UnauthorizedException(message, endpoint: endpoint);
      case 404:
        throw NotFoundException(message, endpoint: endpoint);
      default:
        throw ServerException(message, statusCode: status, endpoint: endpoint);
    }
  }

  String? _extractErrorMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) return err['message'] as String;
        if (err is String) return err;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<T> _withErrorMapping<T>(String endpoint, Future<T> Function() run) async {
    try {
      return await run();
    } on LemonadeApiException {
      rethrow;
    } on TimeoutException catch (e) {
      throw ServerException('Request timed out', endpoint: endpoint, cause: e);
    } catch (e) {
      throw ServerException('Network error: $e', endpoint: endpoint, cause: e);
    }
  }
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
