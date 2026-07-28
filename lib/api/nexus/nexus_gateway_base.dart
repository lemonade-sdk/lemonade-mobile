/// Shared HTTP plumbing for the authenticated Nexus gateway feature clients
/// (Voice, Knowledge). Mirrors [NexusAccountClient]'s URL normalization + error
/// mapping so all gateway calls behave identically; the account/billing client
/// stays separate for historical reasons but shares this contract.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../http_errors.dart';
import '../net.dart';
import '../url_utils.dart';
import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;

/// Base for token-authenticated gateway clients. Construct with the account
/// bearer token (`nxr_<prefix>_<secret>`).
abstract class NexusGatewayClient {
  final String token;
  final http.Client _http;

  NexusGatewayClient({required this.token, http.Client? client})
      : _http = client ?? http.Client();

  // ── URL helpers (shared with NexusAccountClient via normalizeApiV1Base) ──
  String get apiBase =>
      normalizeApiV1Base(kNexusGatewayBaseUrl, assumeHttps: true);

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
  // GETs are idempotent: default timeout + transient-error retry with backoff.
  // Mutations (POST/PUT/DELETE) are single-shot — a resend could double-order
  // a number, double-charge a top-up, etc. — with a timeout only.
  Future<Map<String, dynamic>> getJson(Uri u, {Duration? timeout}) =>
      _wrap(u.path, () {
        return retryTransientGet(() async {
          final resp = await _http
              .get(u, headers: _jsonHeaders)
              .timeout(timeout ?? kDefaultGetTimeout);
          _ensureOk(resp, u);
          return _decodeObject(resp.body);
        });
      });

  Future<Map<String, dynamic>> postJson(Uri u,
          [Map<String, dynamic> body = const {}, Duration? timeout]) =>
      _wrap(u.path, () async {
        final resp = await _http
            .post(u, headers: _jsonHeaders, body: jsonEncode(body))
            .timeout(timeout ?? kDefaultMutationTimeout);
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  Future<Map<String, dynamic>> putJson(Uri u,
          [Map<String, dynamic> body = const {}, Duration? timeout]) =>
      _wrap(u.path, () async {
        final resp = await _http
            .put(u, headers: _jsonHeaders, body: jsonEncode(body))
            .timeout(timeout ?? kDefaultMutationTimeout);
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  Future<void> delete(Uri u, {Duration? timeout}) => _wrap(u.path, () async {
        final resp = await _http
            .delete(u, headers: _jsonHeaders)
            .timeout(timeout ?? kDefaultMutationTimeout);
        _ensureOk(resp, u);
      });

  Future<Uint8List> getBytes(Uri u, {Duration? timeout}) =>
      _wrap(u.path, () {
        return retryTransientGet(() async {
          final resp = await _http
              .get(u, headers: _authHeaders)
              .timeout(timeout ?? kDefaultUploadTimeout);
          _ensureOk(resp, u);
          return resp.bodyBytes;
        });
      });

  /// Multipart upload (used for Knowledge PDF ingest).
  Future<Map<String, dynamic>> postMultipart(
    Uri u, {
    Map<String, String> fields = const {},
    required String fileField,
    required String filename,
    required List<int> bytes,
    String? contentType,
    Duration? timeout,
  }) =>
      _wrap(u.path, () async {
        final req = http.MultipartRequest('POST', u)
          ..headers.addAll(_authHeaders)
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(fileField, bytes,
              filename: filename));
        final streamed =
            await _http.send(req).timeout(timeout ?? kDefaultUploadTimeout);
        final resp = await http.Response.fromStream(streamed)
            .timeout(timeout ?? kDefaultUploadTimeout);
        _ensureOk(resp, u);
        return _decodeObject(resp.body);
      });

  void close() => _http.close();

  // ── Decoding / errors (shared with account + lemonade clients) ──────
  Map<String, dynamic> _decodeObject(String body) => decodeJsonObject(body);

  void _ensureOk(http.Response resp, Uri u) {
    final status = resp.statusCode;
    if (status < 200 || status >= 300) {
      debugPrint('[NexusGateway] $status ${u.path} — '
          '${resp.body.isEmpty ? '(empty)' : resp.body}');
    }
    ensureHttpOk(status, resp.body, u.path);
  }

  Future<T> _wrap<T>(String endpoint, Future<T> Function() run) =>
      withTransportMapping(endpoint, run);
}
