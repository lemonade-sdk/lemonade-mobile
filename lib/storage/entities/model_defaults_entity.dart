import 'package:isar_community/isar.dart';

part 'model_defaults_entity.g.dart';

/// Singleton — only one row, [id] always 0.
@collection
class ModelDefaultsEntity {
  Id id = 0;

  String? llmModel;
  String? audioToTextModel;
  String? textToAudioModel;
  String? imageGenerationModel;

  /// New for OmniRouter: separate model for image edits.
  String? imageEditModel;

  int schemaVersion = 1;
}
