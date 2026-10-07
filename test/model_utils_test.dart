import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/providers/omni_router_provider.dart';
import 'package:lemonade_mobile/utils/model_utils.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';

void main() {
  test('Qwen3.8 is recognized as thinking-capable without a server label', () {
    final capabilities = ModelUtils.detectCapabilities(
      'Qwen/Qwen3.8-27B-FP8',
      const ['text'],
    );

    expect(capabilities, contains(ModelCapabilities.thinking));
  });

  test('unlabeled vision-family models are recognized as vision', () {
    for (final id in ['llava-1.6-7b', 'qwen2.5-vl-7b-instruct', 'moondream2']) {
      expect(
        ModelUtils.detectCapabilities(id, const []),
        contains(ModelCapabilities.vision),
        reason: id,
      );
    }
  });

  test('a server that labels a model text-only is trusted over its name', () {
    expect(
      ModelUtils.detectCapabilities('qwen2.5-vl-7b-instruct', const ['text']),
      isNot(contains(ModelCapabilities.vision)),
    );
  });

  test('Qwen embedding models are not offered reasoning controls', () {
    final capabilities = ModelUtils.detectCapabilities(
      'Qwen3-Embedding-0.6B-GGUF',
      const ['text'],
    );

    expect(capabilities, isNot(contains(ModelCapabilities.thinking)));
  });

  group('managed subscription server identity', () {
    test('does not classify a user-configured Nexus endpoint as managed', () {
      final server = ServerConfig(
        name: 'My API server',
        baseUrl: 'https://api.nexus-projects.ai/api/v1',
        apiKey: 'secret',
      );

      expect(isNexusGatewayEndpoint(server), isTrue);
      expect(isManagedSubscriptionServer(server), isFalse);
    });

    test('recognizes the account-provisioned server across URL forms', () {
      final server = ServerConfig(
        name: kSubscriptionServerName,
        baseUrl: 'https://api.nexus-projects.ai/api/v1/',
      );

      expect(isManagedSubscriptionServer(server), isTrue);
    });
  });

  group('collection wire model resolution', () {
    final models = <ModelInfo>[
      ModelInfo(
        'NXS-PJX-Chat',
        const ['text'],
        isCollection: true,
        compositeModels: const [
          'Qwen3-Embedding-0.6B',
          'kokoro-v1',
          'Moonshine-Medium-Streaming',
          'Flux-2-Klein-9B-GGUF',
          'Qwen/Qwen3.8-27B-FP8',
        ],
      ),
      ModelInfo('Qwen3-Embedding-0.6B', const ['text']),
      ModelInfo('kokoro-v1', const ['tts']),
      ModelInfo('Moonshine-Medium-Streaming', const ['audio']),
      ModelInfo('Flux-2-Klein-9B-GGUF', const ['image']),
      ModelInfo('Qwen/Qwen3.8-27B-FP8', const ['text']),
    ];

    test('uses the configured chat component, not collection or embedding', () {
      expect(
        resolveWireLlmModel('NXS-PJX-Chat', models),
        'Qwen/Qwen3.8-27B-FP8',
      );
    });

    test('never sends a collection id with no runnable component', () {
      final broken = ModelInfo(
        'NXS-Broken',
        const ['text'],
        isCollection: true,
        compositeModels: const ['Qwen3-Embedding-0.6B', 'kokoro-v1'],
      );

      expect(resolveWireLlmModel('NXS-Broken', [broken, ...models]), isNull);
    });
  });
}
