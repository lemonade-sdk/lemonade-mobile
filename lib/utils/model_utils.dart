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

    // Fallback to old logic if labels not available - check if model name contains 'vision'
    final lowerId = modelId.toLowerCase();
    if (lowerId.contains('vision')) {
      return true;
    }

    // Additional known vision models
    return lowerId.contains('gpt-4v') ||
        lowerId.contains('gpt-4-turbo') ||
        lowerId.contains('claude-3') ||
        lowerId.contains('gemini-1.5') ||
        lowerId.contains('llava') ||
        lowerId.contains('bakllava') ||
        lowerId.contains('moondream') ||
        (lowerId.contains('qwen') && lowerId.contains('vl')) ||
        lowerId.contains('internvl');
  }

  /// Detect model capabilities from model ID and labels
  static Set<ModelCapabilities> detectCapabilities(String modelId, List<String> labels) {
    final capabilities = <ModelCapabilities>{};

    // Check labels first
    if (labels.contains('vision')) {
      capabilities.add(ModelCapabilities.vision);
    }
    if (labels.contains('image') || labels.contains('generation')) {
      capabilities.add(ModelCapabilities.imageGeneration);
    }
    if (labels.contains('thinking')) {
      capabilities.add(ModelCapabilities.thinking);
    }

    // If no capabilities detected from labels, check model name
    if (capabilities.isEmpty) {
      final lowerId = modelId.toLowerCase();

      // Check for vision capability in model name
      if (lowerId.contains('vision')) {
        capabilities.add(ModelCapabilities.vision);
      }

      // Check for image generation capability in model name
      if (lowerId.contains('dall') || lowerId.contains('stable-diffusion') || lowerId.contains('sdxl')) {
        capabilities.add(ModelCapabilities.imageGeneration);
      }

      // Check for thinking capability in model name
      if (lowerId.contains('thinking') || lowerId.contains('o1')) {
        capabilities.add(ModelCapabilities.thinking);
      }
    }

    // If still no capabilities detected, default to text-only
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

  /// Build label tags widget for UI display
  static Widget buildLabelTags(List<String> labels) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: labels.map((label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.blue,
          ),
        ),
      )).toList(),
    );
  }
}

enum ModelCapabilities {
  textOnly,
  vision,
  imageGeneration,
  thinking,
}
