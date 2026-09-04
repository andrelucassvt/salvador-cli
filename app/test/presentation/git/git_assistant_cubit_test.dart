import 'package:bloc_test/bloc_test.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_state.dart';

import 'fakes/fake_git_assistant_repository.dart';

void main() {
  late FakeGitAssistantRepository fakeRepository;
  late GitAssistantCubit cubit;

  setUp(() {
    fakeRepository = FakeGitAssistantRepository();
    cubit = GitAssistantCubit(fakeRepository);
  });

  tearDown(() => cubit.close());

  group('GitAssistantCubit drawer', () {
    blocTest<GitAssistantCubit, GitAssistantState>(
      'abrir, fechar e alternar o drawer',
      build: () => cubit,
      act: (cubit) {
        cubit.openDrawer();
        cubit.closeDrawer();
        cubit.toggleDrawer();
      },
      expect: () => [
        isA<GitAssistantIdle>().having(
          (s) => s.drawerOpen,
          'drawerOpen',
          isTrue,
        ),
        isA<GitAssistantIdle>().having(
          (s) => s.drawerOpen,
          'drawerOpen',
          isFalse,
        ),
        isA<GitAssistantIdle>().having(
          (s) => s.drawerOpen,
          'drawerOpen',
          isTrue,
        ),
      ],
    );

    test('setContext guarda o contexto serializado para o proximo envio', () {
      cubit.setContext('Branch: main');
      expect(fakeRepository.lastContext, isNull);

      cubit.setContext(null);
      expect(fakeRepository.lastContext, isNull);
    });
  });

  group('GitAssistantCubit.send', () {
    blocTest<GitAssistantCubit, GitAssistantState>(
      'sem readiness nao envia e reporta sessionNotReady',
      build: () => cubit,
      act: (cubit) => cubit.send('oi'),
      expect: () => [
        isA<GitAssistantIdle>().having(
          (s) => s.errorKind,
          'errorKind',
          GitAssistantErrorKind.sessionNotReady,
        ),
      ],
      verify: (_) => expect(fakeRepository.sentInputs, isEmpty),
    );

    blocTest<GitAssistantCubit, GitAssistantState>(
      'envia com contexto e registra mensagens e proposta pendente',
      build: () {
        cubit.updateReadiness(true);
        return cubit;
      },
      act: (cubit) async {
        cubit.setContext('Branch: main\nSelecao: refs/heads/main');
        await cubit.send('crie um commit');
      },
      expect: () => [
        isA<GitAssistantIdle>()
            .having((s) => s.sending, 'sending', isTrue)
            .having((s) => s.messages, 'messages', hasLength(1)),
        isA<GitAssistantIdle>()
            .having((s) => s.sending, 'sending', isFalse)
            .having((s) => s.messages, 'messages', hasLength(2))
            .having(
              (s) => s.pendingProposals,
              'pendingProposals',
              hasLength(1),
            ),
      ],
      verify: (_) {
        expect(fakeRepository.sentInputs, ['crie um commit']);
        expect(
          fakeRepository.lastContext,
          'Branch: main\nSelecao: refs/heads/main',
        );
      },
    );

    blocTest<GitAssistantCubit, GitAssistantState>(
      'falha de envio preserva mensagens e reporta sendFailed',
      build: () {
        cubit.updateReadiness(true);
        fakeRepository.nextResult = const Result.error(
          AgentFailureException('Ollama indisponivel'),
        );
        return cubit;
      },
      act: (cubit) => cubit.send('oi'),
      expect: () => [
        isA<GitAssistantIdle>().having((s) => s.sending, 'sending', isTrue),
        isA<GitAssistantIdle>()
            .having((s) => s.sending, 'sending', isFalse)
            .having(
              (s) => s.errorKind,
              'errorKind',
              GitAssistantErrorKind.sendFailed,
            )
            .having((s) => s.messages, 'messages', hasLength(1)),
      ],
    );

    test('atividades de ferramenta aparecem no estado', () async {
      cubit.attachSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: Directory('/repo/raiz'),
        permissions: const AgentPermissions(),
      );
      expect(fakeRepository.configureCalls, 1);
      final activity = ToolActivityEntity(
        call: ToolCall(name: 'git_status', arguments: const {}),
        result: 'Branch: main',
      );
      fakeRepository.emitActivity(activity);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as GitAssistantIdle;
      expect(state.activities, hasLength(1));
      expect(state.activities.single.call.name, 'git_status');
    });

    blocTest<GitAssistantCubit, GitAssistantState>(
      'dismissProposal remove a proposta sem executar nada',
      build: () {
        cubit.updateReadiness(true);
        return cubit;
      },
      seed: () => const GitAssistantIdle(
        pendingProposals: [GitActionProposal(type: GitActionType.fetch)],
      ),
      act: (cubit) => cubit.dismissProposal(
        const GitActionProposal(type: GitActionType.fetch),
      ),
      expect: () => [
        isA<GitAssistantIdle>().having(
          (s) => s.pendingProposals,
          'pendingProposals',
          isEmpty,
        ),
      ],
    );

    blocTest<GitAssistantCubit, GitAssistantState>(
      'newSession limpa mensagens e propostas',
      build: () => cubit,
      seed: () => const GitAssistantIdle(
        messages: [ChatMessageEntity(role: ChatRole.user, content: 'oi')],
        pendingProposals: [
          GitActionProposal(type: GitActionType.stage, paths: ['a.txt']),
        ],
      ),
      act: (cubit) => cubit.newSession(),
      expect: () => [
        isA<GitAssistantIdle>()
            .having((s) => s.messages, 'messages', isEmpty)
            .having((s) => s.pendingProposals, 'pendingProposals', isEmpty),
      ],
      verify: (_) => expect(fakeRepository.clearCalls, 1),
    );
  });
}
