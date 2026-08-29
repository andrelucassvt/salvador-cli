import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';

void main() {
  late _ScriptedClient client;
  late ChatAgentDataSource dataSource;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('salvador_chat_agent_');
    client = _ScriptedClient();
    dataSource = ChatAgentDataSource(
      clientFactory: ({required model, required baseUrl, required options}) =>
          client,
    );
  });

  tearDown(() async {
    await dataSource.dispose();
    await root.delete(recursive: true);
  });

  test(
    'configureSession with root exposes Git and preserves run command',
    () async {
      dataSource.configureSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: root,
        permissions: const AgentPermissions(),
        contextFilesEnabled: false,
      );

      final result = await dataSource.send('atualize as refs');

      final toolNames = client.toolRequests.first.map((tool) => tool.name);
      expect(toolNames, containsAll(['git_status', 'git', 'run_command']));
      expect(result.proposals, [
        const GitActionProposal(type: GitActionType.fetch),
      ]);
    },
  );
}

class _ScriptedClient extends OllamaClient {
  _ScriptedClient()
    : super(model: 'llama3.2:3b', baseUrl: Uri.parse('http://127.0.0.1:11434'));

  final List<List<ToolDefinition>> toolRequests = [];
  var _calls = 0;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    toolRequests.add(tools);
    _calls++;
    if (_calls == 1) {
      return AgentMessage(
        role: 'assistant',
        toolCalls: [
          ToolCall(name: 'git', arguments: const {'type': 'fetch'}),
        ],
      );
    }
    return AgentMessage(role: 'assistant', content: 'proposta registrada');
  }
}
