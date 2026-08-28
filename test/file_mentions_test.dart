import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('leve_mentions_test_');
    await Directory('${root.path}/lib/src').create(recursive: true);
    await File(
      '${root.path}/lib/src/agent.dart',
    ).writeAsString('class Agent {}');
    await File('${root.path}/README.md').writeAsString('# Projeto');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('sugere arquivos a partir da mencao ativa', () {
    final mentions = FileMentionService(root);
    const input = 'explique @agent';

    final active = mentions.activeMention(input, input.length);

    expect(active?.query, 'agent');
    expect(mentions.suggest(active!.query), ['lib/src/agent.dart']);
  });

  test('anexa o conteudo de arquivos mencionados ao prompt', () {
    final mentions = FileMentionService(root);

    final expansion = mentions.expand(
      'compare @README.md com @lib/src/agent.dart',
    );

    expect(expansion.files, ['README.md', 'lib/src/agent.dart']);
    expect(expansion.prompt, contains('# Projeto'));
    expect(expansion.prompt, contains('class Agent {}'));
    expect(expansion.prompt, startsWith('compare @README.md'));
  });

  test('nao permite mencao fora da raiz', () async {
    final outside = File('${root.parent.path}/fora_mentions.txt');
    await outside.writeAsString('segredo');
    addTearDown(() async {
      if (outside.existsSync()) await outside.delete();
    });
    final mentions = FileMentionService(root);

    final expansion = mentions.expand('leia @../fora_mentions.txt');

    expect(expansion.files, isEmpty);
    expect(expansion.prompt, isNot(contains('segredo')));
    expect(expansion.warnings.single, contains('fora da raiz'));
  });
}
