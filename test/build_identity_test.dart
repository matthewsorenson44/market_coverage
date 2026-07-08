import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

void main() {
  group('shortBuildHash', () {
    test('keeps unknown unchanged', () {
      expect(shortBuildHash('unknown'), 'unknown');
    });

    test('shortens long hashes to twelve characters', () {
      expect(shortBuildHash('1234567890abcdef'), '1234567890ab');
    });

    test('keeps short hashes unchanged', () {
      expect(shortBuildHash('abc123'), 'abc123');
    });
  });
}
