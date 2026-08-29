import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/domain/entities/attached_file_entity.dart';

void main() {
  group('AttachedFileEntity', () {
    test('equals_whenSamePathAndName_returnsTrue', () {
      const a = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');
      const b = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equals_whenPathDiffers_returnsFalse', () {
      const a = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');
      const b = AttachedFileEntity(path: '/tmp/b.txt', name: 'a.txt');

      expect(a, isNot(equals(b)));
    });

    test('copyWith_whenNoArguments_preservesAllFields', () {
      const original = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('copyWith_whenNameGiven_changesOnlyName', () {
      const original = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');

      final copy = original.copyWith(name: 'renamed.txt');

      expect(copy.name, 'renamed.txt');
      expect(copy.path, original.path);
    });

    test('toString_includesPathAndName', () {
      const entity = AttachedFileEntity(path: '/tmp/a.txt', name: 'a.txt');

      expect(entity.toString(), contains('/tmp/a.txt'));
      expect(entity.toString(), contains('a.txt'));
    });
  });
}
