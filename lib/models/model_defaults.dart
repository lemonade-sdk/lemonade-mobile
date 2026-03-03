class ModelDefaults {
  final String? llmModel;
  final String? audioToTextModel;
  final String? textToAudioModel;
  final String? imageGenerationModel;

  const ModelDefaults({
    this.llmModel,
    this.audioToTextModel,
    this.textToAudioModel,
    this.imageGenerationModel,
  });

  Map<String, dynamic> toJson() {
    return {
      'llmModel': llmModel,
      'audioToTextModel': audioToTextModel,
      'textToAudioModel': textToAudioModel,
      'imageGenerationModel': imageGenerationModel,
    };
  }

  factory ModelDefaults.fromJson(Map<String, dynamic> json) {
    return ModelDefaults(
      llmModel: json['llmModel'] as String?,
      audioToTextModel: json['audioToTextModel'] as String?,
      textToAudioModel: json['textToAudioModel'] as String?,
      imageGenerationModel: json['imageGenerationModel'] as String?,
    );
  }

  ModelDefaults copyWith({
    String? llmModel,
    String? audioToTextModel,
    String? textToAudioModel,
    String? imageGenerationModel,
    bool clearLlm = false,
    bool clearAudioToText = false,
    bool clearTextToAudio = false,
    bool clearImageGeneration = false,
  }) {
    return ModelDefaults(
      llmModel: clearLlm ? null : (llmModel ?? this.llmModel),
      audioToTextModel: clearAudioToText ? null : (audioToTextModel ?? this.audioToTextModel),
      textToAudioModel: clearTextToAudio ? null : (textToAudioModel ?? this.textToAudioModel),
      imageGenerationModel: clearImageGeneration ? null : (imageGenerationModel ?? this.imageGenerationModel),
    );
  }

  bool get isEmpty =>
      llmModel == null &&
      audioToTextModel == null &&
      textToAudioModel == null &&
      imageGenerationModel == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelDefaults &&
          runtimeType == other.runtimeType &&
          llmModel == other.llmModel &&
          audioToTextModel == other.audioToTextModel &&
          textToAudioModel == other.textToAudioModel &&
          imageGenerationModel == other.imageGenerationModel;

  @override
  int get hashCode =>
      llmModel.hashCode ^
      audioToTextModel.hashCode ^
      textToAudioModel.hashCode ^
      imageGenerationModel.hashCode;
}
