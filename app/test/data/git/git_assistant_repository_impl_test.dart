import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/data/repositories/git_assistant_repository_impl.dart';

import 'fakes/fake_git_assistant_datasource.dart';

void main() {
  late FakeGitAssistantDataSource fakeDataSource;
  late GitAssistantRepositoryImpl repository;
  final root = Directory('/repo/raiz');

  setUp(() {
    fakeDataSource = FakeGitAssistantDataSource();
    repository = GitAssistantRepositoryImpl(fakeDataSource);
  });

  group('GitAssistantRepositoryImpl.configureSession', () {
    test('configura com raiz e modelo', () {
      repository.configureSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: root,
        permissions: const AgentPermissions(allowCommands: true),
      );

      expect(fakeDataSource.configuredModels, ['llama3.2:3b']);
      expect(fakeDataSource.configuredRoots, [root.path]);
    });
  });

  group('GitAssistantRepositoryImpl.send', () {
    test(
      'envia com contexto selecionado e devolve resposta e proposta',
      () async {
        fakeDataSource.resultToReturn = AgentTurnResult(
          answer: 'proposta criada',
          proposals: const [
            GitActionProposal(
              type: GitActionType.commit,
              message: 'ajusta parser',
            ),
          ],
        );

        final result = await repository.send(
          input: 'faça o commit',
          context: 'Branch: main\nSelecao:',
        );

        result.when(
          ok: (turn) {
            expect(turn.answer, 'proposta criada');
            expect(turn.proposals, hasLength(1));
            expect(turn.proposals.single.message, 'ajusta parser');
          },
          error: (_) => fail('esperava sucesso'),
        );
        expect(fakeDataSource.sentInputs.single, (
          'faça o commit',
          'Branch: main\nSelecao:',
        ));
      },
    );

    test('falha do agente vira AgentFailureException', () async {
      fakeDataSource.errorToThrow = const AgentException('limite de rodadas');

      final result = await repository.send(input: 'oi');

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) {
          expect(error, isA<AgentFailureException>());
          expect(error.message, contains('limite de rodadas'));
        },
      );
    });

    test('falha do Ollama vira OllamaServerException', () async {
      fakeDataSource.errorToThrow = const OllamaException('servidor caiu');

      final result = await repository.send(input: 'oi');

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) {
          expect(error, isA<OllamaServerException>());
          expect(error.message, contains('servidor caiu'));
        },
      );
    });

    test(
      'falha desconhecida vira UnknownException preservando causa',
      () async {
        final failure = StateError('inesperado');
        fakeDataSource.errorToThrow = failure;

        final result = await repository.send(input: 'oi');

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) {
            expect(error, isA<UnknownException>());
            expect(error.cause, same(failure));
            expect(error.stackTrace, isNotNull);
          },
        );
      },
    );
  });

  group('GitAssistantRepositoryImpl.clearSession', () {
    test('limpa a sessao do datasource', () {
      repository.clearSession();

      expect(fakeDataSource.clearCalls, 1);
    });
  });
}
