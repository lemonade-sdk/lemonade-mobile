import '../lemonade_client.dart';
import '../types/image_request.dart';
import '../types/image_response.dart';

class ImagesEndpoint {
  final LemonadeApiClient _client;
  ImagesEndpoint(this._client);

  /// `POST /v1/images/generations`
  Future<ImageResponse> generate(
    ImageGenerationRequest request, {
    Duration? timeout,
  }) async {
    final body = await _client.postJson(
      _client.apiUriFor('/images/generations'),
      request.toWireJson(),
      timeout: timeout ?? const Duration(minutes: 4),
    );
    return ImageResponse.fromJson(body);
  }

  /// `POST /v1/images/edits` (multipart/form-data — source image as `image` file).
  Future<ImageResponse> edit(
    ImageEditRequest request, {
    Duration? timeout,
  }) async {
    final fields = <String, String>{
      'model': request.model,
      'prompt': request.prompt,
      'response_format': request.responseFormat,
      'n': '${request.n}',
    };
    if (request.size != null) fields['size'] = request.size!;

    final body = await _client.postMultipart(
      _client.apiUriFor('/images/edits'),
      fields: fields,
      files: [
        MultipartFile(
          field: 'image',
          filename: request.sourceFilename,
          bytes: request.sourceImageBytes,
          mimeType: request.sourceImageMime,
        ),
      ],
      timeout: timeout ?? const Duration(minutes: 4),
    );
    return ImageResponse.fromJson(body);
  }
}
