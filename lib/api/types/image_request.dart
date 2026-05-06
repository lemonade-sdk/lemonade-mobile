/// Body for `POST /v1/images/generations`.
class ImageGenerationRequest {
  final String model;
  final String prompt;
  final int? width;
  final int? height;
  final int n;
  final String responseFormat; // 'b64_json' | 'url'

  ImageGenerationRequest({
    required this.model,
    required this.prompt,
    this.width,
    this.height,
    this.n = 1,
    this.responseFormat = 'b64_json',
  });

  factory ImageGenerationRequest.bySize({
    required String model,
    required String prompt,
    String? size, // '512x512' style
    int n = 1,
  }) {
    int? w;
    int? h;
    if (size != null) {
      final parts = size.split('x');
      if (parts.length == 2) {
        w = int.tryParse(parts[0]);
        h = int.tryParse(parts[1]);
      }
    }
    return ImageGenerationRequest(
      model: model,
      prompt: prompt,
      width: w,
      height: h,
      n: n,
    );
  }

  Map<String, dynamic> toWireJson() {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'n': n,
      'response_format': responseFormat,
    };
    if (width != null) body['width'] = width;
    if (height != null) body['height'] = height;
    return body;
  }
}

/// Body for `POST /v1/images/edits` (multipart/form-data).
class ImageEditRequest {
  final String model;
  final String prompt;
  final List<int> sourceImageBytes;
  final String sourceImageMime; // e.g. 'image/png'
  final String sourceFilename; // e.g. 'image.png'
  final String? size; // optional, '512x512'
  final int n;
  final String responseFormat;

  ImageEditRequest({
    required this.model,
    required this.prompt,
    required this.sourceImageBytes,
    this.sourceImageMime = 'image/png',
    this.sourceFilename = 'image.png',
    this.size,
    this.n = 1,
    this.responseFormat = 'b64_json',
  });
}
