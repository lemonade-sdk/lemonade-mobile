// Unit tests for pure app logic. (This file used to hold the stock
// flutter-create counter smoke test, which never matched this app and
// failed on every run.)

import 'package:flutter_test/flutter_test.dart';

import 'package:lemonade_mobile/api/exceptions.dart';
import 'package:lemonade_mobile/api/http_errors.dart';
import 'package:lemonade_mobile/api/types/model_info.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/utils/friendly_error.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';

void main() {
  group('ServerConfig.apiUrl normalization', () {
    ServerConfig cfg(String base) => ServerConfig(baseUrl: base, name: 'test');

    test('bare host gets /api/v1 appended', () {
      expect(cfg('http://host:8000').apiUrl, 'http://host:8000/api/v1');
    });

    test('trailing slashes are stripped', () {
      expect(cfg('http://host:8000///').apiUrl, 'http://host:8000/api/v1');
    });

    test('existing /api/v1 is kept as-is', () {
      expect(cfg('http://host:8000/api/v1').apiUrl, 'http://host:8000/api/v1');
      expect(cfg('http://host:8000/api/v1/').apiUrl, 'http://host:8000/api/v1');
    });

    test('external /v1 style is kept as-is', () {
      expect(cfg('https://api.example.com/v1').apiUrl,
          'https://api.example.com/v1');
    });

    test('/api suffix gets /v1 appended', () {
      expect(cfg('http://host:8000/api').apiUrl, 'http://host:8000/api/v1');
    });

    test('a URL typed without a scheme gets http:// (LAN default)', () {
      expect(cfg('192.168.1.5:13305').apiUrl, 'http://192.168.1.5:13305/api/v1');
      expect(cfg('  myhost.local:13305/ ').apiUrl,
          'http://myhost.local:13305/api/v1');
      expect(Uri.parse(cfg('localhost:13305').apiUrl).host, 'localhost');
    });
  });

  group('Nexus gateway endpoint detection', () {
    ServerConfig cfg(String base) => ServerConfig(baseUrl: base, name: 'mine');

    test('matches the router host in any path form', () {
      for (final url in [
        'https://api.nexus-projects.ai',
        'https://api.nexus-projects.ai/',
        'https://api.nexus-projects.ai/v1',
        'https://api.nexus-projects.ai/api/v1',
        'api.nexus-projects.ai',
      ]) {
        expect(isNexusGatewayEndpoint(cfg(url)), isTrue, reason: url);
      }
    });

    test('does not match other hosts', () {
      expect(isNexusGatewayEndpoint(cfg('http://192.168.1.5:13305')), isFalse);
      expect(isNexusGatewayEndpoint(cfg('https://api.openai.com/v1')), isFalse);
    });
  });

  group('model catalog parsing', () {
    test('plain OpenAI-style entries have no downloaded flag', () {
      final m = ApiModelInfo.fromJson({'id': 'gpt-4o-mini', 'object': 'model'});
      // models_provider keeps every model whose flag isn't explicitly false.
      expect(m.downloaded, isNull);
      expect(m.downloaded != false, isTrue);
    });
  });

  group('error mapping', () {
    test('403 keeps its status instead of posing as a 401', () {
      expect(
        () => ensureHttpOk(403, '{"message":"Account suspended"}', '/auth'),
        throwsA(isA<UnauthorizedException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Account suspended')),
      );
    });

    test('a rejected key on a user server says to check the key', () {
      final msg = friendlyError(ApiKeyRejectedException('bad key'));
      expect(msg, contains('API key'));
      expect(msg, isNot(contains('sign in')));
    });

    test('404 keeps a short server reason', () {
      final msg = friendlyError(
          NotFoundException("model 'llama-x' not found", endpoint: '/x'));
      expect(msg, contains("model 'llama-x' not found"));
    });

    test('404 drops raw bodies', () {
      final msg = friendlyError(
          NotFoundException('<html><body>404</body></html>', endpoint: '/x'));
      expect(msg, isNot(contains('<html>')));
    });
  });
}
