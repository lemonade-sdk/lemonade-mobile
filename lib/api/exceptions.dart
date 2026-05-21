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

class UnauthorizedException extends LemonadeApiException {
  UnauthorizedException(super.message, {super.endpoint, super.cause}) : super(statusCode: 401);
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
