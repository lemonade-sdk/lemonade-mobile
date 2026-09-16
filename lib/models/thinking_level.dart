/// Per-model reasoning depth for chat-completion models that support it.
///
/// Qwen3.8 accepts exactly `low`, `medium`, and `xhigh`. Thinking is opt-in in
/// the app, so a model without a saved preference always resolves to [off].
enum ThinkingLevel { off, low, medium, xhigh }

extension ThinkingLevelX on ThinkingLevel {
  String get label => switch (this) {
    ThinkingLevel.off => 'Off',
    ThinkingLevel.low => 'Low',
    ThinkingLevel.medium => 'Medium',
    ThinkingLevel.xhigh => 'XHigh',
  };

  String get wire => name;

  static ThinkingLevel fromWire(String? value) => switch (value) {
    'low' => ThinkingLevel.low,
    'medium' => ThinkingLevel.medium,
    'xhigh' => ThinkingLevel.xhigh,
    _ => ThinkingLevel.off,
  };
}
