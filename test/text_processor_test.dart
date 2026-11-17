import 'package:flutter_test/flutter_test.dart';
import 'package:flux_origin/utils/text_processor.dart';

void main() {
  group('TextProcessor.smartSplit', () {
    test('splits normal ASCII sentences cleanly without cutting mid-sentence', () {
      const text1 = 'Hello world. This is a test. Another sentence.';
      final chunks1 = TextProcessor.smartSplit(text1, targetSize: 20);
      expect(chunks1, isNotEmpty);
      expect(chunks1.join(' '), contains('Hello world.'));
      expect(chunks1.join(' '), contains('Another sentence.'));
    });

    test('extends look-forward beyond targetSize to finish current sentence', () {
      final text4 = '${'A' * 90}. ${'B' * 10}';
      final chunks4 = TextProcessor.smartSplit(text4, targetSize: 80);
      expect(chunks4, isNotEmpty);
      expect(chunks4.first.length, greaterThan(80));
      expect(chunks4.first, startsWith('AAAA'));
      expect(chunks4.first, endsWith('.'));
    });

    test('splits CJK novels on Chinese sentence terminators', () {
      final cjk =
          '林凡站在山巅望着云海翻涌。他缓缓抽出腰间的长剑，剑气凌厉无比！远方的钟声骤然响起？' * 20;
      final chunks = TextProcessor.smartSplit(cjk, targetSize: 120);
      expect(chunks.length, greaterThan(2));
      for (var i = 0; i < chunks.length - 1; i++) {
        expect(
          RegExp(r'[。！？\n]$').hasMatch(chunks[i]),
          isTrue,
          reason: 'Chunk $i should end cleanly on a CJK sentence terminator',
        );
      }
    });
  });
}
