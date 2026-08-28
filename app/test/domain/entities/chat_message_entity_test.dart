import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';

void main() {
  group('ChatMessageEntity', () {
    test('equals_whenSameValuesInDifferentListInstances_returnsTrue', () {
      final a = ChatMessageEntity(
        role: ChatRole.assistant,
        content: 'ola',
        mentionedFiles: ['a.dart', 'b.dart'],
        warnings: const ['aviso'],
      );
      final b = ChatMessageEntity(
        role: ChatRole.assistant,
        content: 'ola',
        mentionedFiles: ['a.dart', 'b.dart'],
        warnings: const ['aviso'],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equals_whenListsDiffer_returnsFalse', () {
      final a = ChatMessageEntity(
        role: ChatRole.user,
        content: 'ola',
        mentionedFiles: const ['a.dart'],
      );
      final b = ChatMessageEntity(
        role: ChatRole.user,
        content: 'ola',
        mentionedFiles: const ['b.dart'],
      );

      expect(a, isNot(equals(b)));
    });

    test('copyWith_whenNoArguments_preservesAllFields', () {
      const original = ChatMessageEntity(
        role: ChatRole.user,
        content: 'ola',
        mentionedFiles: ['a.dart'],
        warnings: ['aviso'],
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('copyWith_whenContentGiven_changesOnlyContent', () {
      const original = ChatMessageEntity(role: ChatRole.user, content: 'ola');

      final copy = original.copyWith(content: 'tchau');

      expect(copy.content, 'tchau');
      expect(copy.role, original.role);
    });
  });
}
