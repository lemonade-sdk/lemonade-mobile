/// Shared HTTP plumbing for the authenticated Nexus gateway feature clients
/// (Voice, Knowledge). Mirrors [NexusAccountClient]'s URL normalization + error
/// mapping so all gateway calls behave identically; the account/billing client
/// stays separate for historical reasons but shares this contract.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../exceptions.dart';
import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;

/// Base for token-authenticated gateway clients. Construct with the account
/// bearer token (`nxr_<prefix>_<secret>`).
abstract class NexusGatewayClient {
  final String token;
  final http.Client _http;

  NexusGatewayClient({required this.token, http.Client? client})
      : _http = client ?? http.Client();

  // ── URL helpers (identical normalization to NexusAccountClient) ──────
  String get apiBase {
    String url = kNexusGatewayBaseUrl.trim();
    if (!url.contains('://')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api/v1')) return url;
    if (url.endsWith('/v1')) return url;
    if (url.endsWith('/api')) return '$url/v1';
    return '$url/api/v1';
  }

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = apiBase;
    final joined = path.startsWith('/') ? '$base$path' : '$base/$path';
    final u = Uri.parse(joined);
    if (query == null || query.isEmpty) return u;
    final qp = <String, String>{};
    query.forEach((k, v) {
      if (v != null) qp[k] = '$v';
    });
    return u.replace(queryParameters: {...u.queryParameters, ...qp});
  }

  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $token'};

  Map<String, String> get _jsonHeaders => {
        ..._authHeaders,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ── JSON verbs ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getJson(Uri u) => _wrap(u.path, () async {
        final resp = await _http.get(u, headers: _jsonHeaders);
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  Future<Map<String, dynamic>> postJson(Uri u,
          [Map<String, dynamic> body = const {}]) =>
      _wrap(u.path, () async {
        final resp =
            await _http.post(u, headers: _jsonHeaders, body: jsonEncode(body));
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  Future<Map<String, dynamic>> putJson(Uri u,
          [Map<String, dynamic> body = const {}]) =>
      _wrap(u.path, () async {
        final resp =
            await _http.put(u, headers: _jsonHeaders, body: jsonEncode(body));
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  Future<void> delete(Uri u) => _wrap(u.path, () async {
        final resp = await _http.delete(u, headers: _jsonHeaders);
        _ensureOk(resp, u);
      });

  Future<Uint8List> getBytes(Uri u) => _wrap(u.path, () async {
        final resp = await _http.get(u, headers: _authHeaders);
        _ensureOk(resp, u);
        return resp.bodyBytes;
      });

  /// Multipart upload (used for Knowledge PDF ingest).
  Future<Map<String, dynamic>> postMultipart(
    Uri u, {
    Map<String, String> fields = const {},
    required String fileField,
    required String filename,
    required List<int> bytes,
    String? contentType,
  }) =>
      _wrap(u.path, () async {
        final req = http.MultipartRequest('POST', u)
          ..headers.addAll(_authHeaders)
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(fileField, bytes,
              filename: filename));
        final streamed = await _http.send(req);
        final resp = await http.Response.fromStream(streamed);
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  void close() => _http.close();

  // ── Decoding / errors ───────────────────────────────────────────────
  Map<String, dynamic> _decodeObject(String body) {
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  void _ensureOk(http.Response resp, Uri u) {
    final status = resp.statusCode;
    if (status >= 200 && status < 300) return;
    debugPrint('[NexusGateway] $status ${u.path} — '
        '${resp.body.isEmpty ? '(empty)' : resp.body}');
    final message = _extractError(resp.body) ?? 'HTTP $status';
    switch (status) {
      case 401:
      case 403:
        throw UnauthorizedException(message, endpoint: u.path);
      case 404:
        throw NotFoundException(message, endpoint: u.path);
      default:
        throw ServerException(message, statusCode: status, endpoint: u.path);
    }
  }

  String? _extractError(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        // Gateway errors often carry BOTH a machine code (`error`, e.g.
        // "voice_node_error") and the human reason (`message`, e.g. "all
        // lines busy…"). Returning the first key found hid the reason —
        // prefer the message and append the code for context.
        final code = decoded['error'];
        for (final key in ['message', 'detail', 'title']) {
          final v = decoded[key];
          if (v is String && v.isNotEmpty) {
            return (code is String && code.isNotEmpty && code != v)
                ? '$v ($code)'
                : v;
          }
        }
        if (code is String && code.isNotEmpty) return code;
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          return errors.map((e) => e.toString()).join('; ');
        }
        if (errors is Map && errors.isNotEmpty) {
          return errors.values.map((v) => '$v').join('; ');
        }
      }
    } catch (_) {}
    return body.length > 400 ? body.substring(0, 400) : body;
  }

  Future<T> _wrap<T>(String endpoint, Future<T> Function() run) async {
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
