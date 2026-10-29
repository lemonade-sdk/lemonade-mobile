import 'dart:convert';

class LemonadeApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? endpoint;
  final Object? cause;

  LemonadeApiException(this.message, {this.statusCode, this.endpoint, this.cause});

  @override
  String toString() {
    final parts = <String>['LemonadeApiException: $message'];
    if (statusCode != null) parts.add('status=$statusCode');
    if (endpoint != null) parts.add('endpoint=$endpoint');
    return parts.join(' ');
  }
}

class NotFoundException extends LemonadeApiException {
  NotFoundException(super.message, {super.endpoint, super.cause}) : super(statusCode: 404);
}

/// 401, or 403 when [statusCode] says so — both mean "not allowed", but a 403
/// (suspended account, missing capability) must not read as a bad password.
class UnauthorizedException extends LemonadeApiException {
  UnauthorizedException(super.message, {super.endpoint, super.cause, int statusCode = 401})
      : super(statusCode: statusCode);
}

/// A user-configured server (not the subscription gateway) rejected the API
/// key. There's no account to sign back into — the fix is the key itself.
class ApiKeyRejectedException extends UnauthorizedException {
  ApiKeyRejectedException(super.message, {super.endpoint, super.cause, super.statusCode});
}

/// The Lemonade Nexus mesh refused a request to another device (HTTP 403
/// with a `nexus_*` code): the device has not been granted the service, does
/// not offer it over the mesh, or could not tell which device asked.
/// [message] is written for the user.
class MeshAccessDeniedException extends LemonadeApiException {
  /// `nexus_permission_denied`, `nexus_route_unregistered` or
  /// `nexus_peer_unattributed`.
  final String code;

  /// The permission the device needs, such as `svc:inference`.
  final String? required;

  MeshAccessDeniedException(super.message,
      {required this.code, this.required, super.endpoint})
      : super(statusCode: 403);

  /// Reads a mesh refusal body; null when [body] is not one.
  static MeshAccessDeniedException? tryParse(String body, String endpoint) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final code = decoded['code'];
    if (code is! String || !code.startsWith('nexus_')) return null;
    final required = decoded['required'] as String?;
    final message = switch (code) {
      'nexus_permission_denied' => "That computer hasn't given this device "
          "access${required == null ? '' : ' ($required)'}. Grant it in "
          "Lemonade on the computer, then try again.",
      'nexus_route_unregistered' =>
        "That computer doesn't offer this over the mesh.",
      'nexus_peer_unattributed' =>
        "That computer couldn't tell which device sent the request. "
            "Reconnect the mesh and try again.",
      _ => 'The mesh refused the request ($code).',
    };
    return MeshAccessDeniedException(message,
        code: code, required: required, endpoint: endpoint);
  }
}

/// The mesh port could not route a request to another device: it is
/// offline or unreachable from this device right now, or the name fits
/// several devices (HTTP 409, 502, 503 or 504 with the SDK's `{"error"}`).
/// [message] is the SDK's reason, written for the user.
class MeshRouteException extends LemonadeApiException {
  MeshRouteException(super.message, {required int super.statusCode, super.endpoint});

  static const statuses = {409, 502, 503, 504};

  /// Reads the mesh port's `{"error": "..."}`; null for any other body.
  static MeshRouteException? tryParse(int status, String body, String endpoint) {
    if (!statuses.contains(status)) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final error = decoded['error'];
    if (error is! String || error.isEmpty) return null;
    return MeshRouteException(error, statusCode: status, endpoint: endpoint);
  }
}

class ModelMismatchException extends LemonadeApiException {
  ModelMismatchException(super.message, {super.endpoint, super.cause}) : super(statusCode: 400);
}

class ServerException extends LemonadeApiException {
  ServerException(super.message, {super.statusCode, super.endpoint, super.cause});
}

class StreamProtocolException extends LemonadeApiException {
  StreamProtocolException(super.message, {super.endpoint, super.cause});
}
