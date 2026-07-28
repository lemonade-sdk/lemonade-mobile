import '../api/types/chat_message.dart';
import '../models/chat_message.dart' as ui;
import 'agent_loop.dart';

/// Map a UI [ui.ChatMessage] into the agent-loop [AgentMessage] shape.
///
/// Image parts are only forwarded when they are already `data:` URLs — file
/// paths never reach the model (they are inlined at send time by ChatNotifier).
AgentMessage agentMessageFromUi(ui.ChatMessage m) {
  final role = m.isUser ? 'user' : 'assistant';
  if (!m.hasImages) {
    return AgentMessage(role: role, text: m.textContent);
  }
  final parts = <ApiContentPart>[];
  if (m.textContent.isNotEmpty) parts.add(ApiContentPart.text(m.textContent));
  for (final c in m.content) {
    if (c.type == ui.MessageContentType.image && c.value.startsWith('data:')) {
      parts.add(ApiContentPart.imageUrl(c.value));
    }
  }
  return AgentMessage(role: role, parts: parts);
}
