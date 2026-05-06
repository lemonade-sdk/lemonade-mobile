/// Response shape for `/v1/images/generations` and `/v1/images/edits`.
class ImageResponse {
  final List<GeneratedImage> images;

  ImageResponse(this.images);

  factory ImageResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final list = data is List
        ? data
            .whereType<Map<String, dynamic>>()
            .map(GeneratedImage.fromJson)
            .toList()
        : <GeneratedImage>[];
    return ImageResponse(list);
  }
}

class GeneratedImage {
  /// Base64-encoded image data when `response_format=b64_json`. Null if `url` was used.
  final String? b64Json;

  /// Remote URL when `response_format=url`. Null otherwise. (Lemonade typically returns b64.)
  final String? url;

  GeneratedImage({this.b64Json, this.url});

  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
        b64Json: json['b64_json'] as String?,
        url: json['url'] as String?,
      );
}
