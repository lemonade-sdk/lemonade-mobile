// Unit tests for pure app logic. (This file used to hold the stock
// flutter-create counter smoke test, which never matched this app and
// failed on every run.)

import 'package:flutter_test/flutter_test.dart';

import 'package:lemonade_mobile/models/server_config.dart';

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
  });
}
