/// Shared transport helpers for the HTTP clients: default request timeouts and
/// transient-failure retry for idempotent requests.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

/// Default timeout for idempotent JSON GETs.
const Duration kDefaultGetTimeout = Duration(seconds: 30);

/// Default timeout for JSON mutations (POST/PUT/DELETE).
const Duration kDefaultMutationTimeout = Duration(seconds: 60);

/// Default timeout for multipart uploads (large payloads over slow links).
const Duration kDefaultUploadTimeout = Duration(minutes: 5);

/// Default connect/first-byte timeout for SSE requests.
const Duration kDefaultSseConnectTimeout = Duration(seconds: 30);

/// Default idle timeout between SSE events once the stream is open.
const Duration kDefaultSseIdleTimeout = Duration(seconds: 120);

/// True for low-level transport failures still in raw form (before
/// [withTransportMapping] wraps them). Used by [retryTransientGet] which runs
/// *inside* the mapping layer.
bool isTransientTransportError(Object e) =>
    e is SocketException ||
    e is HandshakeException ||
    e is http.ClientException ||
    e is TimeoutException;

/// True for transport-level failures where a silent retry of an already-mapped
/// call makes sense (chat/agent stream drop). Unwraps [LemonadeApiException]
/// causes and stringified "Network error: SocketException…" wrappers.
///
/// Typed request errors (4xx with a status code) are deterministic — retrying
/// them just doubles load/latency, so they return false.
bool isRetryableTransportError(Object e) {
  if (isTransientTransportError(e)) return true;
  if (e is StreamProtocolException) return true;
  if (e is LemonadeApiException) {
    // A real HTTP status means the server answered — not transport.
    if (e.statusCode != null) return false;
    final cause = e.cause;
    if (cause != null && !identical(cause, e)) {
      return isRetryableTransportError(cause);
    }
    final m = e.message.toLowerCase();
    return m.contains('socketexception') ||
        m.contains('clientexception') ||
        m.contains('connection closed') ||
        m.contains('connection reset') ||
        m.contains('failed host lookup') ||
        m.contains('network error') ||
        m.contains('timed out');
  }
  return false;
}

/// Run [attempt], retrying up to [maxExtraAttempts] more times on transient
/// transport errors (see [isTransientTransportError]) with short exponential
/// backoff (300ms, 900ms by default).
///
/// ONLY use this for idempotent requests (GETs). Mutations must stay
/// single-shot — a retried POST can double-charge / double-order.
Future<T> retryTransientGet<T>(
  Future<T> Function() attempt, {
  int maxExtraAttempts = 2,
  Duration firstDelay = const Duration(milliseconds: 300),
}) async {
  var delay = firstDelay;
  for (var tries = 0; ; tries++) {
    try {
      return await attempt();
    } catch (e) {
      if (tries >= maxExtraAttempts || !isTransientTransportError(e)) rethrow;
    }
    await Future<void>.delayed(delay);
    delay *= 3;
  }
}
