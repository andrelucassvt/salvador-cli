import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/data/repositories/chat_repository_impl.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

import 'fakes/fake_chat_agent_datasource.dart';

void main() {
  late FakeChatAgentDataSource fakeDataSource;
  late ChatRepositoryImpl repository;

  setUp(() {
    fakeDataSource = FakeChatAgentDataSource();
    repository = ChatRepositoryImpl(fakeDataSource);
  });

  test('send_whenDataSourceSucceeds_returnsOkWithReply', () async {
    fakeDataSource.reply = const AgentTurnResult(answer: 'resposta');

    final result = await repository.send('oi');

    result.when(
      ok: (reply) => expect(reply.answer, 'resposta'),
      error: (_) => fail('esperava sucesso'),
    );
  });

  test('send_whenAgentExceptionThrown_returnsAgentFailureException', () async {
    fakeDataSource.exceptionToThrow = const AgentException('falhou');

    final result = await repository.send('oi');

    result.when(
      ok: (_) => fail('esperava erro'),
      error: (error) => expect(error, isA<AgentFailureException>()),
    );
  });

  test('toolActivity_whenDataSourceEmits_repassesEvent', () async {
    final events = <ToolActivityEntity>[];
    final subscription = repository.toolActivity.listen(events.add);

    fakeDataSource.activityController.add(
      ToolActivityEntity(
        call: ToolCall(name: 'read_file', arguments: const {'path': 'a.dart'}),
        result: 'conteudo',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    await subscription.cancel();
  });

  test('configureSession_delegatesToDataSource', () {
    repository.configureSession(
      host: Uri.parse('http://127.0.0.1:11434'),
      model: 'llama3',
      options: const InferenceOptions(),
      root: Directory.systemTemp,
      permissions: const AgentPermissions(),
      contextFilesEnabled: true,
    );

    expect(fakeDataSource.configureCallCount, 1);
  });

  test('clearSession_delegatesToDataSource', () {
    repository.clearSession();

    expect(fakeDataSource.clearCallCount, 1);
  });
}
