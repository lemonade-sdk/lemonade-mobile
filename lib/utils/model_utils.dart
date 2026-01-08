import 'package:flutter/material.dart';
import 'package:lemonade_mobile/constants/colors.dart';

/// Utility class for model detection and display logic
class ModelUtils {
  /// Check if a model supports vision based on its labels
  static bool isVisionModel(String modelId, List<String> labels) {
    if (modelId.isEmpty) return false;

    // First check labels if available
    if (labels.contains('vision')) {
      return true;
    }

    // Fallback to old logic if labels not available
    final lowerId = modelId.toLowerCase();
    return lowerId.contains('vision') ||
        lowerId.contains('gpt-4v') ||
        lowerId.contains('gpt-4-turbo') ||
        lowerId.contains('claude-3') ||
        lowerId.contains('gemini-1.5') ||
        lowerId.contains('llava') ||
        lowerId.contains('bakllava') ||
        lowerId.contains('moondream') ||
        (lowerId.contains('qwen') && lowerId.contains('vl')) ||
        lowerId.contains('internvl') ||
        lowerId.contains('gemma-3');
  }

  /// Detect model capabilities from labels
  static Set<ModelCapabilities> detectCapabilities(List<String> labels) {
    final capabilities = <ModelCapabilities>{};

    if (labels.contains('vision')) {
      capabilities.add(ModelCapabilities.vision);
    }
    if (labels.contains('image') || labels.contains('generation')) {
      capabilities.add(ModelCapabilities.imageGeneration);
    }
    if (labels.contains('thinking')) {
      capabilities.add(ModelCapabilities.thinking);
    }
    if (capabilities.isEmpty) {
      capabilities.add(ModelCapabilities.textOnly);
    }

    return capabilities;
  }

  /// Check if capabilities represent a text-only model
  static bool isTextOnly(Set<ModelCapabilities> capabilities) {
    return capabilities.contains(ModelCapabilities.textOnly) && capabilities.length == 1;
  }

  /// Check if capabilities include vision support
  static bool supportsVision(Set<ModelCapabilities> capabilities) {
    return capabilities.contains(ModelCapabilities.vision);
  }

  /// Check if capabilities include image generation support
  static bool supportsImageGeneration(Set<ModelCapabilities> capabilities) {
    return capabilities.contains(ModelCapabilities.imageGeneration);
  }

  /// Check if capabilities include thinking support
  static bool supportsThinking(Set<ModelCapabilities> capabilities) {
    return capabilities.contains(ModelCapabilities.thinking);
  }

  /// Build capability icon widget for UI display
  static Widget buildCapabilityIcon(Set<ModelCapabilities> capabilities) {
    // Show icon for the highest priority capability
    if (capabilities.contains(ModelCapabilities.vision)) {
      return Icon(Icons.visibility, size: 16, color: AppColors.capabilityVision);
    } else if (capabilities.contains(ModelCapabilities.imageGeneration)) {
      return Icon(Icons.image, size: 16, color: AppColors.capabilityImageGeneration);
    } else if (capabilities.contains(ModelCapabilities.thinking)) {
      return Icon(Icons.psychology, size: 16, color: AppColors.capabilityTextOnly);
    } else {
      return Icon(Icons.text_fields, size: 16, color: AppColors.capabilityTextOnly);
    }
  }

  /// Build capability text widget for UI display
  static Widget buildCapabilityText(Set<ModelCapabilities> capabilities) {
    final List<String> capabilityNames = [];

    if (capabilities.contains(ModelCapabilities.vision)) {
      capabilityNames.add('Vision');
    }
    if (capabilities.contains(ModelCapabilities.imageGeneration)) {
      capabilityNames.add('Image Gen');
    }
    if (capabilities.contains(ModelCapabilities.thinking)) {
      capabilityNames.add('Thinking');
    }
    if (capabilities.contains(ModelCapabilities.textOnly) && capabilities.length == 1) {
      capabilityNames.add('Text Only');
    }

    final text = capabilityNames.isEmpty ? 'Text Only' : capabilityNames.join(' + ');
    return Text(text, style: const TextStyle(fontSize: 12));
  }
}

enum ModelCapabilities {
  textOnly,
  vision,
  imageGeneration,
  thinking,
}
