import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  test('identifica uma instalacao do Ollama', () async {
    final calls = <List<String>>[];
    final discovery = OllamaDiscovery(
      processRunner: (executable, arguments, {environment}) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(1, 0, 'ollama version 1.0', '');
      },
    );

    expect(await discovery.isInstalled(), isTrue);
    expect(calls, [
      ['ollama', '--help'],
    ]);
  });

  test('identifica quando o executavel nao esta instalado', () async {
    final discovery = OllamaDiscovery(
      processRunner: (executable, arguments, {environment}) async {
        throw ProcessException(executable, arguments, 'not found');
      },
    );

    expect(await discovery.isInstalled(), isFalse);
  });

  test('extrai os nomes retornados por ollama list', () async {
    const output =
        '''NAME                      ID              SIZE      MODIFIED
qwen2.5-coder:3b          abc123          1.9 GB    2 days ago
deepseek-coder:latest      def456          776 MB    1 week ago
''';
    final discovery = OllamaDiscovery(
      host: Uri.parse('http://127.0.0.1:11434'),
      processRunner: (executable, arguments, {environment}) async {
        expect(executable, 'ollama');
        expect(arguments, ['list']);
        expect(environment?['OLLAMA_HOST'], 'http://127.0.0.1:11434');
        return ProcessResult(1, 0, output, '');
      },
    );

    expect(await discovery.listModels(), [
      'qwen2.5-coder:3b',
      'deepseek-coder:latest',
    ]);
  });

  test('explica uma falha do ollama list', () async {
    final discovery = OllamaDiscovery(
      processRunner: (executable, arguments, {environment}) async =>
          ProcessResult(1, 1, '', 'daemon indisponivel'),
    );

    expect(
      discovery.listModels,
      throwsA(
        isA<OllamaDiscoveryException>().having(
          (error) => error.message,
          'message',
          'daemon indisponivel',
        ),
      ),
    );
  });
}
