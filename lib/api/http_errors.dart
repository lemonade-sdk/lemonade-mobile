/// Shared HTTP error extraction / status mapping / transport wrapping for
/// [LemonadeApiClient], [NexusAccountClient], and [NexusGatewayClient].
///
/// These three clients previously each had their own copy of this logic and
/// they had diverged (different key priority, truncation, FastAPI detail
/// lists, 400→ModelMismatch). One implementation keeps error UX consistent.
library;

import 'dart:async';
import 'dart:convert';

import 'exceptions.dart';

/// Prefer human-readable server messages; fall back to machine codes and
/// validation lists. Used by every HTTP client in the app.
String? extractHttpErrorMessage(String body, {int truncateAt = 500}) {
  if (body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final parts = <String>[];

      // Prefer message/detail/title (human) over `error` (often a machine
      // code like "voice_node_error"). When both differ, keep both.
      final code = decoded['error'];
      String? codeStr;
      if (code is String && code.isNotEmpty) {
        codeStr = code;
      } else if (code is Map && code['message'] is String) {
        // OpenAI-style: { error: { message, type, code } }
        parts.add(code['message'] as String);
      }

      for (final key in ['message', 'detail', 'title']) {
        final v = decoded[key];
        if (v is String && v.isNotEmpty) {
          if (codeStr != null && codeStr.isNotEmpty && codeStr != v) {
            parts.add('$v ($codeStr)');
          } else {
            parts.add(v);
          }
          codeStr = null; // already incorporated
          break;
        }
        if (key == 'detail' && v is List && v.isNotEmpty) {
          // FastAPI validation: [{loc, msg, type}, …]
          parts.add(v
              .map((e) => e is Map
                  ? (e['msg'] ?? e['message'] ?? e.toString())
                  : e.toString())
              .join('; '));
          break;
        }
      }

      if (parts.isEmpty && codeStr != null) parts.add(codeStr);

      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        parts.add(errors.map((e) => e.toString()).join('; '));
      } else if (errors is Map && errors.isNotEmpty) {
        parts.add(errors.values.map((v) => '$v').join('; '));
      }

      if (parts.isNotEmpty) return parts.join(' ');
    }
  } catch (_) {}
  return body.length > truncateAt ? body.substring(0, truncateAt) : body;
}

/// Map a non-2xx status + body to a typed [LemonadeApiException].
///
/// [map400ToModelMismatch] is Lemonade-specific (context/model mismatch on
/// chat/completions); gateway/account leave 400 as [ServerException].
void ensureHttpOk(
  int status,
  String body,
  String endpoint, {
  bool map400ToModelMismatch = false,
}) {
  if (status >= 200 && status < 300) return;
  final message = extractHttpErrorMessage(body) ?? 'HTTP $status';
  switch (status) {
    case 400:
      if (map400ToModelMismatch) {
        throw ModelMismatchException(message, endpoint: endpoint);
      }
      throw ServerException(message, statusCode: status, endpoint: endpoint);
    case 401:
    case 403:
      throw UnauthorizedException(message, endpoint: endpoint);
    case 404:
      throw NotFoundException(message, endpoint: endpoint);
    default:
      throw ServerException(message, statusCode: status, endpoint: endpoint);
  }
}

/// Decode a JSON object body; non-objects wrap as `{'data': …}`. Empty → `{}`.
Map<String, dynamic> decodeJsonObject(String body) {
  if (body.isEmpty) return const {};
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  return {'data': decoded};
}

/// Wrap a network call so transport failures become typed [ServerException]s
/// carrying [endpoint] and the original [cause]. Already-typed API exceptions
/// rethrow unchanged.
Future<T> withTransportMapping<T>(
  String endpoint,
  Future<T> Function() run,
) async {
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
