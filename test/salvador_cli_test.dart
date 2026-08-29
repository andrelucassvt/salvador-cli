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

  test('sem raiz, o registro nao expoe nenhuma ferramenta', () {
    final registry = ToolRegistry(null);

    expect(registry.definitions, isEmpty);
  });

  test('sessao sem raiz nao anuncia ferramentas nem menciona Raiz', () async {
    final client = FakeChatClient([
      AgentMessage(role: 'assistant', content: 'resposta sem workspace'),
    ]);
    final session = AgentSession(client: client);

    final answer = await session.send('oi');

    expect(answer, 'resposta sem workspace');
    expect(client.toolRequests.single, isEmpty);
    expect(client.requests.single.first.content, isNot(contains('Raiz:')));
  });

  test('envia imagens mesmo sem texto de acompanhamento', () async {
    final client = FakeChatClient([
      AgentMessage(role: 'assistant', content: 'vejo uma imagem'),
    ]);
    final session = AgentSession(client: client);

    final result = await session.sendDetailed('', images: ['base64==']);

    expect(result.answer, 'vejo uma imagem');
    expect(client.requests.single.last.images, ['base64==']);
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

  test(
    'leitura permanece disponivel com permissao de somente leitura',
    () async {
      final client = FakeChatClient([
        AgentMessage(role: 'assistant', content: 'ok'),
      ]);
      final session = AgentSession(
        client: client,
        root: root,
        permissions: AgentPermissions.readOnly,
      );

      await session.send('oi');

      expect(client.toolRequests.single.map((tool) => tool.name), [
        'read_file',
      ]);
    },
  );

  test(
    'edicao e comando sao removidos das definicoes conforme permissao',
    () async {
      final client = FakeChatClient([
        AgentMessage(role: 'assistant', content: 'ok'),
      ]);
      final session = AgentSession(
        client: client,
        root: root,
        permissions: const AgentPermissions(allowEdit: false),
      );

      await session.send('oi');

      final names = client.toolRequests.single
          .map((tool) => tool.name)
          .toList();
      expect(names, contains('read_file'));
      expect(names, contains('run_command'));
      expect(names, isNot(contains('write_file')));
      expect(names, isNot(contains('replace_in_file')));
    },
  );

  test(
    'chamada forjada para edicao desabilitada nao toca o filesystem',
    () async {
      final registry = ToolRegistry(
        root,
        permissions: const AgentPermissions(allowEdit: false),
      );

      final result = await registry.execute(
        ToolCall(
          name: 'write_file',
          arguments: {'path': 'nao.txt', 'content': 'nao'},
        ),
      );

      expect(result, contains('ferramenta nao permitida'));
      expect(File('${root.path}/nao.txt').existsSync(), isFalse);
    },
  );

  test(
    'chamada forjada para comando desabilitado nao executa processo',
    () async {
      final registry = ToolRegistry(
        root,
        permissions: const AgentPermissions(allowCommands: false),
      );

      final result = await registry.execute(
        ToolCall(name: 'run_command', arguments: {'command': 'echo x'}),
      );

      expect(result, contains('ferramenta nao permitida'));
    },
  );

  test('read_file rejeita arquivo binario com ERRO sem excecao', () async {
    await File(
      '${root.path}/imagem.dat',
    ).writeAsBytes([0x50, 0x4B, 0x00, 0x01]);
    final registry = ToolRegistry(root);

    final result = await registry.execute(
      ToolCall(name: 'read_file', arguments: {'path': 'imagem.dat'}),
    );

    expect(result, startsWith('ERRO:'));
    expect(result, contains('binario'));
  });

  test('read_file rejeita UTF-8 invalido com ERRO sem excecao', () async {
    await File('${root.path}/latin1.txt').writeAsBytes([0xC3, 0x28, 0x41]);
    final registry = ToolRegistry(root);

    final result = await registry.execute(
      ToolCall(name: 'read_file', arguments: {'path': 'latin1.txt'}),
    );

    expect(result, startsWith('ERRO:'));
    expect(result, contains('UTF-8'));
  });

  test(
    'observador de conclusao recebe chamada e resultado, inclusive ERRO',
    () async {
      final client = FakeChatClient([
        AgentMessage(
          role: 'assistant',
          toolCalls: [
            ToolCall(
              name: 'write_file',
              arguments: {'path': 'ok.txt', 'content': 'x'},
            ),
            ToolCall(name: 'read_file', arguments: {'path': 'ausente.txt'}),
          ],
        ),
        AgentMessage(role: 'assistant', content: 'fim'),
      ]);
      final startedCalls = <String>[];
      final finishedCalls = <String>[];
      final finishedResults = <String>[];
      final session = AgentSession(
        client: client,
        root: root,
        onToolCall: (call) => startedCalls.add(call.name),
        onToolResult: (call, result) {
          finishedCalls.add(call.name);
          finishedResults.add(result);
        },
      );

      await session.send('grava e le');

      expect(startedCalls, ['write_file', 'read_file']);
      expect(finishedCalls, ['write_file', 'read_file']);
      expect(finishedResults, hasLength(2));
      expect(finishedResults.first, contains('OK: arquivo gravado'));
      expect(finishedResults.last, contains('ERRO:'));
      expect(File('${root.path}/ok.txt').readAsStringSync(), 'x');
    },
  );

  group('perfil Git da sessao', () {
    test('expoe consultas e propostas sem run_command', () async {
      final client = FakeChatClient([
        AgentMessage(role: 'assistant', content: 'ok'),
      ]);
      final session = AgentSession(
        client: client,
        root: root,
        gitClient: GitClient(
          processRunner: (executable, arguments) async =>
              ProcessResult(0, 0, '', ''),
        ),
        gitProfile: const GitProfile(),
        permissions: const AgentPermissions(allowCommands: true),
      );

      await session.send('oi');

      final names = client.toolRequests.single
          .map((tool) => tool.name)
          .toList();
      expect(names, contains('git_status'));
      expect(names, contains('git_log'));
      expect(names, contains('git_diff'));
      expect(names, contains('git_show'));
      expect(names, contains('propose_git_action'));
      expect(
        names,
        isNot(contains('run_command')),
        reason: 'o perfil Git nunca expoe shell, mesmo com allowCommands',
      );
    });

    test('propose_git_action acumula proposta sem invocar o runner', () async {
      final runnerCalls = <List<String>>[];
      final client = FakeChatClient([
        AgentMessage(
          role: 'assistant',
          toolCalls: [
            ToolCall(
              name: 'propose_git_action',
              arguments: {
                'type': 'commit',
                'message': 'corrige o parser de status',
              },
            ),
          ],
        ),
        AgentMessage(role: 'assistant', content: 'proposta registrada'),
      ]);
      final proposals = <GitActionProposal>[];
      final session = AgentSession(
        client: client,
        root: root,
        gitClient: GitClient(
          processRunner: (executable, arguments) async {
            runnerCalls.add(arguments);
            return ProcessResult(0, 0, '', '');
          },
        ),
        gitProfile: const GitProfile(),
        onProposal: proposals.add,
      );

      final result = await session.sendDetailed('faça um commit');

      expect(result.proposals, hasLength(1));
      final proposal = result.proposals.single;
      expect(proposal.type, GitActionType.commit);
      expect(proposal.message, 'corrige o parser de status');
      expect(proposals, hasLength(1));
      expect(
        runnerCalls,
        isEmpty,
        reason: 'nenhum processo git pode rodar por causa de uma proposta',
      );
      final toolMessage = client.requests.last
          .where((message) => message.role == 'tool')
          .single;
      expect(toolMessage.content, contains('aprovacao'));
    });

    test(
      'perfil Git respeita allowEdit para escrita durante conflitos',
      () async {
        final client = FakeChatClient([
          AgentMessage(role: 'assistant', content: 'ok'),
        ]);
        final session = AgentSession(
          client: client,
          root: root,
          gitClient: GitClient(
            processRunner: (executable, arguments) async =>
                ProcessResult(0, 0, '', ''),
          ),
          gitProfile: const GitProfile(),
          permissions: const AgentPermissions(allowEdit: false),
        );

        await session.send('oi');

        final names = client.toolRequests.single
            .map((tool) => tool.name)
            .toList();
        expect(names, isNot(contains('write_file')));
        expect(names, isNot(contains('replace_in_file')));
      },
    );
  });
}

class FakeChatClient implements ChatClient {
  FakeChatClient(this.responses);

  final List<AgentMessage> responses;
  final List<List<AgentMessage>> requests = [];
  final List<List<ToolDefinition>> toolRequests = [];
  var _index = 0;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    requests.add(List.of(messages));
    toolRequests.add(List.of(tools));
    return responses[_index++];
  }
}
