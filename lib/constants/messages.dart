/// Centralized message constants for the Lemonade Mobile app.
/// Contains all user-facing strings, error messages, and UI text.
class AppMessages {
  // Error messages
  static const String noServerSelected = 'No server selected. Please select a server in settings.';
  static const String noModelSelected = 'Please select a model from the settings before chatting.';
  static const String modelListSyncing =
      'Still syncing the model list from the server — try again in a moment.';
  static const String noModelSelectedForImage = 'Please select a model from the settings before generating images.';

  // Image generation errors
  static String textOnlyModelError(String model) =>
      'The selected model "$model" is text-only and cannot generate images. Please select a vision-capable model (marked with 👁️) or an image generation model (marked with 🖼️).';

  static String visionModelServerError(String model) =>
      'The selected vision model "$model" cannot generate images on this server. Try selecting an image generation model (marked with 🖼️) or switch to a server that supports image generation.';

  static String imageGenerationServerError(String model) =>
      'Image generation failed on this server. The model "$model" should support image generation, but the server returned an error. Please check your server configuration.';

  static const String imageGenerationTimeout =
      'Image generation request timed out. The server took too long to respond. Please try again or check your server configuration.';

  // Image display errors
  static const String placeholderImageError = 'Model provided placeholder image instead of generated content';
  static const String modelPlaceholderError = 'Model generated a placeholder image. Try a different prompt or model.';
  static const String imageDecodeError = 'Failed to decode image';
  static String base64DecodeError(String error) => 'Error decoding base64 image data: $error';
  static const String invalidImageFormat = 'Invalid image data format';
  static const String malformedImageUrl = 'Malformed image data URL';
  static String imageProcessingError(String error) => 'Error processing image: $error';
  static const String networkImageError = 'Failed to load image from URL';
  static const String localImageError = 'Failed to load local image';

  // Image picking errors
  static String imagePickError(String error) => 'Error picking image: $error';
  static String imageSelectError(String error) => 'Error selecting image: $error';

  // Permissions errors
  static const String cameraPermissionError = 'Camera and photo permissions are required to take photos.';
  static const String photoPermissionError = 'Camera and photo library permissions are required to access photos.';
  static const String cameraPermissionPermanentlyDenied = 'Camera permissions are permanently denied. Please enable them in Settings.';
  static const String photoPermissionPermanentlyDenied = 'Photo library permissions are permanently denied. Please enable them in Settings.';

  // Success messages
  static const String messageCopied = 'Message copied to clipboard';
  static const String codeCopied = 'Code copied to clipboard';

  // UI hints and placeholders
  static const String imageCommandHint = 'Type /image or /draw followed by your prompt...';
  static const String messageWithImageHint = 'Type a message (image attached)...';
  static const String defaultMessageHint = 'Type a message...';

  // Copy hints
  static const String copyHint = 'Long press to copy';

  // Model capability indicators
  static const String visionCapability = 'Vision + Text';
  static const String imageGenerationCapability = 'Image Generation';
  static const String textOnlyCapability = 'Text Only';

  // Loading states
  static const String loadingModels = 'Loading models...';
  static const String noThreads = 'No threads yet';

  // Settings and navigation
  static const String settings = 'Settings';
  static const String model = 'Model';
  static const String threads = 'Threads';
  static const String newThread = 'New Thread';

  // Dialog titles and buttons
  static const String takePhoto = 'Take Photo';
  static const String chooseFromGallery = 'Choose from Gallery';
  static const String deleteThread = 'Delete Thread';

  // Beacon discovery
  static String serverDiscovered(String hostname) =>
      'Server "$hostname" found on network';
  static const String beaconListening = 'Listening for Lemonade servers on the network...';
  static const String beaconInactive = 'Beacon listener is not active';
  static const String noServersDetected = 'No servers detected yet';

  // Generic errors
  static String genericError(String error) => 'Error: $error';

  // Error notices rendered inside assistant chat bubbles.
  //
  // Assistant messages are replayed to the model on later turns, so an error
  // notice persisted as assistant text would pollute the context. There is no
  // Isar schema slot to flag them, so notices are marked with an invisible
  // Unicode character (INVISIBLE SEPARATOR) that the UI renders as nothing and
  // the request builders strip via [stripErrorNotices].
  static const String errorNoticeMarker = '\u2063';

  /// Wrap a user-facing error message so it renders normally in the chat but
  /// is recognizable (and strippable) when building model payloads.
  static String errorNotice(String message) => '$errorNoticeMarker$message';

  /// Appended to a partially-streamed reply when the connection drops mid-turn.
  static final String streamInterruptedNotice =
      errorNotice('⚠ The connection was interrupted — this reply may be incomplete.');

  /// Remove any error-notice lines from [text] before sending it to the model.
  static String stripErrorNotices(String text) {
    if (!text.contains(errorNoticeMarker)) return text;
    return text
        .split('\n')
        .where((line) => !line.trimLeft().startsWith(errorNoticeMarker))
        .join('\n')
        .trim();
  }

  // Server testing
  static const String serverTestFailed = 'Failed to connect to server';

  // Chat history
  static String messagesCount(int count) => '$count messages';
  static String lastUpdated(DateTime date) => 'Last updated: ${date.toString().split(' ')[0]}';

  // Transcription
  static const String transcription = 'Transcription';
  static const String transcriptionCopied = 'Transcription copied to clipboard';
  static const String microphonePermissionRequired = 'Microphone permission is required for transcription.';
  static const String noAudioModels = 'No audio transcription models detected on this server.';
  static String transcriptionFailed(String error) => 'Transcription failed: $error';
  static const String recordingStarted = 'Recording started...';
  static const String processingTranscription = 'Processing transcription...';

  // Model defaults
  static const String modelDefaults = 'Model Defaults';
  static const String modelDefaultsReset = 'All model defaults reset';
  static const String settingsCopied = 'Settings copied';
  static const String settingsPasted = 'Settings pasted to this chat';
  static const String noSettingsToPaste = 'No settings to paste. Long-press a chat thread and select "Copy Settings" first.';

  // Copy settings
  static const String copySettings = 'Copy Settings';
  static const String pasteSettings = 'Paste Settings';
}
