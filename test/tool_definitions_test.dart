import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/omni/tool_definitions.dart';

void main() {
  test('tool names stay unique and descriptions stay short', () {
    final tools = OmniToolCatalog.all;
    expect(tools.map((tool) => tool.name).toSet().length, tools.length);
    for (final tool in tools) {
      expect(tool.description.trim(), isNotEmpty, reason: tool.name);
      expect(
        tool.description.trim().split(RegExp(r'\s+')).length,
        lessThanOrEqualTo(30),
        reason: tool.name,
      );
    }
  });

  test('the image analysis tool uses the image from the chat', () {
    final tool = OmniToolCatalog.byName('analyze_image');
    final properties = tool.parameters['properties'] as Map<String, dynamic>;

    expect(properties.keys, ['question']);
    expect(tool.parameters['required'], ['question']);
  });

  test('the system prompt lists each available tool once', () {
    final prompt = OmniToolCatalog.buildSystemPrompt(OmniToolCatalog.all);
    for (final tool in OmniToolCatalog.all) {
      expect(RegExp('- ${tool.name}:').allMatches(prompt).length, 1);
    }
  });
}
