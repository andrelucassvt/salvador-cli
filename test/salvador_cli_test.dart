import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('leve_cli_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('executa uma tool call de escrita de ponta a ponta', () async {
    final client = FakeChatClient([
      AgentMessage(
        role: 'assistant',
        toolCalls: [
          ToolCall(
            name: 'write_file',
            arguments: {'path': 'hello.txt', 'content': 'ola local'},
          ),
        ],
      ),
      AgentMessage(role: 'assistant', content: 'Arquivo criado.'),
    ]);
    final usedTools = <String>[];
    final session = AgentSession(
      client: client,
      root: root,
      onToolCall: (call) => usedTools.add(call.name),
    );

    final answer = await session.send('crie hello.txt');

    expect(answer, 'Arquivo criado.');
    expect(File('${root.path}/hello.txt').readAsStringSync(), 'ola local');
    expect(usedTools, ['write_file']);
    expect(client.requests, hasLength(2));
    expect(
      client.requests.last
          .where((message) => message.role == 'tool')
          .single
          .content,
      contains('OK: arquivo gravado'),
    );
  });

  test('impede escrita fora da raiz', () async {
    final registry = ToolRegistry(root);

    final result = await registry.execute(
      ToolCall(
        name: 'write_file',
        arguments: {'path': '../escape.txt', 'content': 'nao'},
      ),
    );

    expect(result, contains('acesso fora da raiz'));
    expect(File('${root.parent.path}/escape.txt').existsSync(), isFalse);
  });

  test('aceita argumentos de tool call serializados como JSON', () {
    final call = ToolCall.fromJson({
      'function': {'name': 'read_file', 'arguments': '{"path":"README.md"}'},
    });

    expect(call.name, 'read_file');
    expect(call.arguments, {'path': 'README.md'});
  });

  test('agrega metricas de todas as rodadas da resposta', () async {
    final client = FakeChatClient([
      AgentMessage(
        role: 'assistant',
        toolCalls: [
          ToolCall(name: 'read_file', arguments: {'path': 'a.txt'}),
        ],
        metrics: const InferenceMetrics(
          promptTokens: 10,
          generatedTokens: 4,
          generationDurationNanoseconds: 200000000,
          totalDurationNanoseconds: 300000000,
        ),
      ),
      AgentMessage(
        role: 'assistant',
        content: 'fim',
        metrics: const InferenceMetrics(
          promptTokens: 20,
          generatedTokens: 6,
          generationDurationNanoseconds: 300000000,
          totalDurationNanoseconds: 400000000,
        ),
      ),
    ]);
    await File('${root.path}/a.txt').writeAsString('a');
    final session = AgentSession(client: client, root: root);

    final result = await session.sendDetailed('leia @a.txt');

    expect(result.answer, 'fim');
    expect(result.mentionedFiles, ['a.txt']);
    expect(result.metrics?.promptTokens, 30);
    expect(result.metrics?.generatedTokens, 10);
    expect(result.metrics?.tokensPerSecond, 20);
    expect(result.metrics?.generations, 2);
    expect(client.requests.first.last.content, contains('arquivo mencionado'));
    expect(client.requests.first.last.content, contains('\na\n'));
  });
}

class FakeChatClient implements ChatClient {
  FakeChatClient(this.responses);

  final List<AgentMessage> responses;
  final List<List<AgentMessage>> requests = [];
  var _index = 0;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    requests.add(List.of(messages));
    return responses[_index++];
  }
}
