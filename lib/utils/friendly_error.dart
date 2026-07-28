import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/exceptions.dart';

/// Maps any thrown error to a short, customer-appropriate message.
///
/// Raw exception strings (SocketException, stack traces, endpoints, status
/// codes) must never reach the UI — pass errors through here instead, and
/// log the raw error for diagnostics.
///
/// [action] optionally names what failed, e.g. "save the flow" →
/// "Couldn't save the flow. …".
String friendlyError(Object error, {String? action}) {
  final what = action ?? 'do that';

  String message;
  final e = _unwrap(error);

  if (e is TimeoutException) {
    message = "The server is taking too long to respond. Please try again.";
  } else if (e is SocketException ||
      e is HandshakeException ||
      e is WebSocketException ||
      e is HttpException) {
    message =
        "Can't reach the server. Check your connection and try again.";
  } else if (e is PlatformException) {
    message = _platformMessage(e, what);
  } else if (e is LemonadeApiException) {
    message = _apiMessage(e, what);
  } else if (e is FormatException) {
    message = "The server sent an unexpected response. Please try again.";
  } else {
    message = "Something went wrong trying to $what. Please try again.";
  }

  debugPrint('friendlyError(${action ?? '-'}): $error');
  return message;
}

/// Pulls a nested transport error out of wrapper exceptions so the
/// connectivity branches above can match it.
Object _unwrap(Object error) {
  if (error is LemonadeApiException) {
    final cause = error.cause;
    // Separate `is` checks so each branch promotes `cause` to non-null Object.
    if (cause is SocketException) return cause;
    if (cause is TimeoutException) return cause;
    if (cause is HandshakeException) return cause;
    if (cause is WebSocketException) return cause;
    // "Network error: SocketException: …" wrappers that lost the cause.
    final m = error.message.toLowerCase();
    if (m.contains('socketexception') ||
        m.contains('connection refused') ||
        m.contains('connection closed') ||
        m.contains('failed host lookup') ||
        m.contains('network error')) {
      return const SocketException('wrapped');
    }
    if (m.contains('timed out') || m.contains('timeoutexception')) {
      return TimeoutException(null);
    }
  }
  return error;
}

String _apiMessage(LemonadeApiException e, String what) {
  switch (e.statusCode) {
    case 400:
      return "The server couldn't process that request. Please try again.";
    case 401:
      // Capability gating elsewhere shows richer upsell cards; this is the
      // generic fallback.
      return e.message.contains('capability_required')
          ? "Your plan doesn't include this feature yet."
          : "You're signed out or your session expired. Please sign in again.";
    case 402:
      return "There aren't enough funds for that. Add funds and try again.";
    case 403:
      return "You don't have permission to $what.";
    case 404:
      return "That wasn't found on the server. It may have been removed.";
    case 409:
      return "That conflicts with a change made elsewhere. Refresh and try again.";
    case 429:
      return "Too many requests right now. Wait a moment and try again.";
  }
  if (e.statusCode != null && e.statusCode! >= 500) {
    return "The server hit a problem. Please try again in a moment.";
  }
  if (e is StreamProtocolException) {
    return "The connection was interrupted. Please try again.";
  }
  return "Something went wrong trying to $what. Please try again.";
}

String _platformMessage(PlatformException e, String what) {
  final code = e.code.toLowerCase();
  if (code.contains('camera_access_denied') || code.contains('camera')) {
    return "Camera access is off. Enable it for this app in Settings.";
  }
  if (code.contains('photo_access_denied') || code.contains('photo')) {
    return "Photo access is off. Enable it for this app in Settings.";
  }
  if (code.contains('microphone') || code.contains('record')) {
    return "Microphone access is off. Enable it for this app in Settings.";
  }
  return "Something went wrong trying to $what. Please try again.";
}
