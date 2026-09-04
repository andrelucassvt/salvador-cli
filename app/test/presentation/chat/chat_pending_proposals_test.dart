import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/chat/widgets/chat_widgets.dart';

import 'fakes/fake_chat_repository.dart';
import '../git/fakes/fake_git_repository.dart';

void main() {
  late FakeChatRepository chatRepository;
  late FakeGitRepository gitRepository;
  late ChatCubit cubit;

  setUp(() {
    chatRepository = FakeChatRepository();
    gitRepository = FakeGitRepository();
    cubit = ChatCubit(chatRepository, gitRepository: gitRepository)
      ..attachSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: Directory('/repo/raiz'),
        permissions: const AgentPermissions(),
        contextFilesEnabled: true,
      )
      ..updateReadiness(true);
  });

  tearDown(() => cubit.close());

  Future<void> pumpProposals(WidgetTester tester) async {
    chatRepository.reply = const AgentTurnResult(
      answer: 'proposta pronta',
      proposals: [GitActionProposal(type: GitActionType.fetch)],
    );
    await cubit.send('faça fetch');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ChatCubit>.value(
            value: cubit,
            child: const ChatPendingProposals(),
          ),
        ),
      ),
    );
  }

  testWidgets('revisar abre dialog e confirmar executa proposta', (
    tester,
  ) async {
    await pumpProposals(tester);

    expect(find.byKey(const Key('chat-git-proposal-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-review-proposal-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('git-action-review-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('git-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(gitRepository.executedActions, const [
      GitActionProposal(type: GitActionType.fetch),
    ]);
    expect(find.byKey(const Key('chat-git-proposal-0')), findsNothing);
  });

  testWidgets('cancelar remove proposta sem executar Git', (tester) async {
    await pumpProposals(tester);

    await tester.tap(find.byKey(const Key('chat-cancel-proposal-0')));
    await tester.pump();

    expect(gitRepository.executedActions, isEmpty);
    expect(find.byKey(const Key('chat-git-proposal-0')), findsNothing);
  });
}
