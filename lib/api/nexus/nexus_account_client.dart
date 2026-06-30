/// Lightweight HTTP client for the Nexus gateway ("Nexus Router") Account /
/// Billing / Usage API. Deliberately SEPARATE from [LemonadeApiClient] (which is
/// per-inference-server): this one targets the single billing gateway and
/// carries the user's ACCOUNT bearer token.
///
/// The gateway host is hardcoded — this client only ever talks to the managed
/// subscription backend, never a local AI server. Inference against the
/// subscription is wired through a normal entry in the server list (see
/// `account_provider.dart`).
///
/// Maps non-2xx to the typed exceptions in `../exceptions.dart`
/// (UnauthorizedException / NotFoundException / ServerException) and extracts
/// error messages from {error}/{errors}/{detail}/{message}. The token is never
/// logged.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../exceptions.dart';
import 'nexus_account_models.dart';

/// The managed subscription gateway. Hardcoded: this is not a local AI server.
const String kNexusGatewayBaseUrl = 'https://api.nexus-projects.ai';

/// Stable app name reported to the gateway as `app_name`. Part of the router's
/// per-device token rotation bucket (user, device_id, app_name) and shown in the
/// account's tokens UI. Keep it constant — changing it re-buckets tokens.
const String kNexusAppName = 'Omni AI Chat';

class NexusAccountClient {
  /// Account bearer token (`nxr_<prefix>_<secret>`). Null for unauthenticated
  /// calls (register / login / plans).
  final String? token;

  final http.Client _http;

  NexusAccountClient({this.token, http.Client? client})
      : _http = client ?? http.Client();

  // ── URL helpers ─────────────────────────────────────────────────────
  // Mirrors ServerConfig.apiUrl: normalize the hardcoded gateway to a
  // `/api/v1` base.
  String get _apiBase {
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

  Uri _uri(String path) {
    final base = _apiBase;
    final joined = path.startsWith('/') ? '$base$path' : '$base/$path';
    return Uri.parse(joined);
  }

  Map<String, String> get _authHeaders {
    final t = token?.trim();
    if (t == null || t.isEmpty) return const {};
    return {'Authorization': 'Bearer $t'};
  }

  Map<String, String> get _jsonHeaders => {
        ..._authHeaders,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ── Auth ────────────────────────────────────────────────────────────

  /// POST /auth/register → AuthResult (token + user + client). 400 surfaces the
  /// server's validation messages (e.g. weak password) via ServerException.
  ///
  /// The optional [deviceId]/[deviceName]/[appName] enable per-device tokens
  /// (multiple devices stay signed in at once). Omitting them is the legacy
  /// single-token behavior.
  Future<AuthResult> register({
    required String clientName,
    required String email,
    required String password,
    String? deviceId,
    String? deviceName,
    String? appName,
  }) async {
    final json = await _postJson(_uri('/auth/register'), {
      'client_name': clientName,
      'email': email,
      'password': password,
      ..._deviceFields(deviceId, deviceName, appName),
    });
    return AuthResult.fromJson(json);
  }

  /// POST /auth/login → AuthResult. 401 → UnauthorizedException.
  ///
  /// See [register] for the optional per-device fields. Re-logging in with the
  /// same [deviceId]+[appName] rotates only this device's token.
  Future<AuthResult> login({
    required String email,
    required String password,
    String? deviceId,
    String? deviceName,
    String? appName,
  }) async {
    final json = await _postJson(_uri('/auth/login'), {
      'email': email,
      'password': password,
      ..._deviceFields(deviceId, deviceName, appName),
    });
    return AuthResult.fromJson(json);
  }

  /// snake_case device identity fields, omitting any that are blank (≤200 chars
  /// each per the router contract).
  Map<String, String> _deviceFields(
      String? deviceId, String? deviceName, String? appName) {
    String? clip(String? v) {
      final t = v?.trim();
      if (t == null || t.isEmpty) return null;
      return t.length > 200 ? t.substring(0, 200) : t;
    }

    final id = clip(deviceId);
    final name = clip(deviceName);
    final app = clip(appName);
    return {
      if (id != null) 'device_id': id,
      if (name != null) 'device_name': name,
      if (app != null) 'app_name': app,
    };
  }

  // ── Billing / Plans ─────────────────────────────────────────────────

  /// GET /plans (no auth) → catalog of plans + add-ons.
  Future<PlanCatalog> fetchPlans() async {
    final json = await _getJson(_uri('/plans'));
    return PlanCatalog.fromJson(json);
  }

  /// POST /billing/checkout (auth) → Stripe Checkout URL to open in a browser.
  Future<String> startCheckout({
    required String plan,
    List<String> addons = const [],
  }) async {
    final json = await _postJson(_uri('/billing/checkout'), {
      'plan': plan,
      'addons': addons,
    });
    return (json['url'] ?? '') as String;
  }

  /// POST /billing/portal (auth) → Stripe billing-portal URL.
  Future<String> openBillingPortal() async {
    final json = await _postJson(_uri('/billing/portal'), const {});
    return (json['url'] ?? '') as String;
  }

  // ── In-app plan management (already-subscribed accounts) ─────────────
  // Immediate proration; the server re-syncs entitlements inline. Throws on
  // 409 no_subscription (→ run checkout) and 400 audience.

  /// POST /billing/change-plan — upgrade OR downgrade the AI tier.
  Future<void> changePlan(String plan) =>
      _postJson(_uri('/billing/change-plan'), {'plan': plan}).then((_) {});

  /// POST /billing/add-package — add a Business add-on (e.g. `phone_system`) or
  /// bump its quantity. Numbers use the numbers flow, not this.
  Future<void> addPackage(String key, {int quantity = 1}) =>
      _postJson(_uri('/billing/add-package'), {'key': key, 'quantity': quantity})
          .then((_) {});

  /// POST /billing/remove-package — drop an add-on line. 404 not_on_subscription
  /// if the package isn't on the subscription.
  Future<void> removePackage(String key) =>
      _postJson(_uri('/billing/remove-package'), {'key': key}).then((_) {});

  /// GET /billing/subscription — current plan + the ACTIVE add-on lines. Source
  /// of truth for which add-ons are on the subscription (so the picker shows an
  /// accurate Add/Remove state per add-on, not a heuristic).
  Future<SubscriptionDetail> fetchSubscription() async {
    final json = await _getJson(_uri('/billing/subscription'));
    return SubscriptionDetail.fromJson(json);
  }

  /// POST /billing/cancel — cancel the WHOLE subscription. [atPeriodEnd] true
  /// (default) keeps access until the paid period ends; false ends it now.
  /// 409 no_subscription if there's nothing to cancel.
  Future<void> cancelSubscription({bool atPeriodEnd = true}) =>
      _postJson(_uri('/billing/cancel'), {'atPeriodEnd': atPeriodEnd})
          .then((_) {});

  // ── Usage / Account ─────────────────────────────────────────────────

  // NOTE: the router has no standalone GET /usage endpoint. Capacity/limits
  // come from GET /account (subscription.*), and consumption comes from
  // GET /usage/agents (summed token totals).

  /// GET /account (auth) → account + subscription summary.
  Future<AccountSummary> fetchAccount() async {
    final json = await _getJson(_uri('/account'));
    return AccountSummary.fromJson(json);
  }

  /// GET /usage/agents (auth) → per-agent cost breakdown. [days] windows the
  /// scan; null defaults to the current billing period server-side.
  Future<AgentUsageReport> fetchAgentUsage({int? days}) async {
    final path = days == null ? '/usage/agents' : '/usage/agents?days=$days';
    final json = await _getJson(_uri(path));
    return AgentUsageReport.fromJson(json);
  }

  void close() => _http.close();

  // ── Core request helpers ────────────────────────────────────────────

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> body) {
    return _withErrorMapping(uri.path, () async {
      final resp =
          await _http.post(uri, headers: _jsonHeaders, body: jsonEncode(body));
      _logIfError(resp, uri);
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return _decodeJsonObject(resp.body);
    });
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) {
    return _withErrorMapping(uri.path, () async {
      final resp = await _http.get(uri, headers: _jsonHeaders);
      _logIfError(resp, uri);
      _ensureOk(resp.statusCode, resp.body, uri.path);
      return _decodeJsonObject(resp.body);
    });
  }

  void _logIfError(http.Response resp, Uri uri) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Never log Authorization headers or the token; only status + body.
      debugPrint('[Nexus] ${resp.statusCode} ${uri.path} — '
          '${resp.body.isEmpty ? '(empty body)' : resp.body}');
    }
  }

  // ── Error handling (mirrors LemonadeApiClient) ──────────────────────

  void _ensureOk(int status, String body, String endpoint) {
    if (status >= 200 && status < 300) return;
    final message = _extractErrorMessage(body) ?? 'HTTP $status';
    switch (status) {
      case 401:
      case 403:
        throw UnauthorizedException(message, endpoint: endpoint);
      case 404:
        throw NotFoundException(message, endpoint: endpoint);
      default:
        // 400 (validation) and 5xx → ServerException carrying the server text.
        throw ServerException(message, statusCode: status, endpoint: endpoint);
    }
  }

  /// Extracts a human message from the gateway's error envelopes. The C# router
  /// returns {error, errors[]}; FastAPI-style services use {detail}; some use
  /// {message}. Concatenate field-level `errors` when present.
  String? _extractErrorMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final parts = <String>[];
        final err = decoded['error'];
        if (err is String && err.isNotEmpty) parts.add(err);
        if (err is Map && err['message'] is String) {
          parts.add(err['message'] as String);
        }
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          parts.add(errors.map((e) => e.toString()).join('; '));
        }
        if (parts.isEmpty && decoded['message'] is String) {
          parts.add(decoded['message'] as String);
        }
        if (parts.isEmpty) {
          final detail = decoded['detail'];
          if (detail is String) {
            parts.add(detail);
          } else if (detail is List && detail.isNotEmpty) {
            parts.add(detail
                .map((e) => e is Map
                    ? (e['msg'] ?? e['message'] ?? e.toString())
                    : e.toString())
                .join('; '));
          }
        }
        if (parts.isNotEmpty) return parts.join(' ');
      }
    } catch (_) {}
    return body.length > 500 ? body.substring(0, 500) : body;
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.isEmpty) return const {};
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
