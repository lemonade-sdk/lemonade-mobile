import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lemonade_mobile/api/lemonade_client.dart';
import 'package:lemonade_mobile/api/types/chat_message.dart';
import 'package:lemonade_mobile/api/types/chat_request.dart';
import 'package:lemonade_mobile/api/types/chat_response.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/models/thinking_level.dart';

void main() {
  group('ChatCompletionRequest thinking settings', () {
    ChatCompletionRequest request(ThinkingLevel? level) =>
        ChatCompletionRequest(
          model: 'Qwen/Qwen3.8-27B-FP8',
          messages: [ApiChatMessage.user('hello')],
          thinkingLevel: level,
        );

    test('off uses nested chat-template kwargs', () {
      final json = request(ThinkingLevel.off).toWireJson();

      expect(json, isNot(contains('enable_thinking')));
      expect(json['chat_template_kwargs'], {'enable_thinking': false});
    });

    test('effort levels enable thinking with the exact Qwen3.8 values', () {
      for (final level in const [
        ThinkingLevel.low,
        ThinkingLevel.medium,
        ThinkingLevel.xhigh,
      ]) {
        expect(request(level).toWireJson()['chat_template_kwargs'], {
          'enable_thinking': true,
          'reasoning_effort': level.name,
        });
      }
    });

    test('omits template kwargs for models without a thinking setting', () {
      expect(
        request(null).toWireJson(),
        isNot(contains('chat_template_kwargs')),
      );
    });
  });

  test(
    'stream recognizes reasoning as activity and keeps it private',
    () async {
      final frames = [
        {
          'choices': [
            {
              'delta': {'reasoning': 'private thought'},
              'finish_reason': null,
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': 'answer'},
              'finish_reason': null,
            },
          ],
        },
        {
          'choices': [
            {'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
          ],
        },
      ].map((chunk) => 'data: ${jsonEncode(chunk)}\n\n').join();

      final httpClient = MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          Stream.value(utf8.encode('${frames}data: [DONE]\n\n')),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final client = LemonadeApiClient(
        ServerConfig(baseUrl: 'https://example.test/v1', name: 'test'),
        client: httpClient,
      );

      final events = await client.chat
          .stream(
            ChatCompletionRequest(
              model: 'test',
              messages: [ApiChatMessage.user('hello')],
            ),
          )
          .toList();

      expect(events.whereType<ChatReasoningDelta>(), hasLength(1));
      expect(events.whereType<ChatContentDelta>().map((e) => e.text), [
        'answer',
      ]);
      expect(
        events.whereType<ChatStreamFinish>().single.contentSoFar,
        'answer',
      );
    },
  );
}
