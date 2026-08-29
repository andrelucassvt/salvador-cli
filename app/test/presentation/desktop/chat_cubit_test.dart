import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_state.dart';

import 'fakes/fake_chat_repository.dart';

void main() {
  late FakeChatRepository fakeRepository;

  setUp(() {
    fakeRepository = FakeChatRepository();
  });

  group('ChatCubit.send', () {
    blocTest<ChatCubit, ChatState>(
      'send_whenNotReady_emitsSessionNotReadyWithoutCallingRepository',
      build: () => ChatCubit(fakeRepository),
      act: (cubit) => cubit.send('oi'),
      expect: () => [
        isA<ChatIdle>().having(
          (s) => s.errorKind,
          'errorKind',
          ChatErrorKind.sessionNotReady,
        ),
      ],
      verify: (_) => expect(fakeRepository.lastMessage, isNull),
    );

    blocTest<ChatCubit, ChatState>(
      'send_whenReady_addsUserMessageThenReply',
      build: () => ChatCubit(fakeRepository)..updateReadiness(true),
      act: (cubit) {
        fakeRepository.reply = const AgentTurnResult(answer: 'resposta');
        return cubit.send('oi');
      },
      expect: () => [
        isA<ChatIdle>()
            .having((s) => s.sending, 'sending', true)
            .having((s) => s.messages, 'messages', hasLength(1)),
        isA<ChatIdle>()
            .having((s) => s.sending, 'sending', false)
            .having((s) => s.messages, 'messages', hasLength(2))
            .having(
              (s) => s.messages.last.content,
              'reply content',
              'resposta',
            ),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'send_whenRepositoryFails_emitsSendFailedKeepingUserMessage',
      build: () => ChatCubit(fakeRepository)..updateReadiness(true),
      act: (cubit) {
        fakeRepository.failure = const AgentFailureException('falhou');
        return cubit.send('oi');
      },
      expect: () => [
        isA<ChatIdle>().having((s) => s.sending, 'sending', true),
        isA<ChatIdle>()
            .having((s) => s.sending, 'sending', false)
            .having((s) => s.errorKind, 'errorKind', ChatErrorKind.sendFailed)
            .having((s) => s.messages, 'messages', hasLength(1)),
      ],
    );
  });

  group('ChatCubit.attachSession', () {
    blocTest<ChatCubit, ChatState>(
      'attachSession_clearsMessagesAndActivities',
      build: () => ChatCubit(fakeRepository),
      seed: () => const ChatIdle(
        messages: [],
        activities: [],
        sessionFirstPrompt: 'prompt antigo',
      ),
      act: (cubit) => cubit.attachSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: Directory.systemTemp,
        permissions: const AgentPermissions(),
      ),
      expect: () => [
        isA<ChatIdle>()
            .having((s) => s.messages, 'messages', isEmpty)
            .having((s) => s.sessionFirstPrompt, 'sessionFirstPrompt', isNull),
      ],
      verify: (_) => expect(fakeRepository.configureCallCount, 1),
    );

    blocTest<ChatCubit, ChatState>(
      'attachSession_withoutRoot_stillConfiguresSession',
      build: () => ChatCubit(fakeRepository),
      act: (cubit) => cubit.attachSession(
        host: Uri.parse('http://127.0.0.1:11434'),
        model: 'llama3.2:3b',
        options: const InferenceOptions(),
        root: null,
        permissions: const AgentPermissions(),
      ),
      verify: (_) {
        expect(fakeRepository.configureCallCount, 1);
        expect(fakeRepository.lastRoot, isNull);
      },
    );
  });

  group('ChatCubit.newSession', () {
    blocTest<ChatCubit, ChatState>(
      'newSession_whenSessionInProgress_reportsSummaryThenClears',
      build: () => ChatCubit(fakeRepository),
      seed: () => ChatIdle(
        sessionFirstPrompt: 'primeiro prompt',
        sessionStartedAt: DateTime(2026, 1, 1),
        activities: const [],
      ),
      act: (cubit) {
        var reported = false;
        cubit.newSession(
          onSessionEnded: (summary) {
            reported = true;
            expect(summary.title, 'primeiro prompt');
          },
        );
        expect(reported, isTrue);
      },
      expect: () => [
        isA<ChatIdle>().having(
          (s) => s.sessionFirstPrompt,
          'sessionFirstPrompt',
          isNull,
        ),
      ],
      verify: (_) => expect(fakeRepository.clearCallCount, 1),
    );
  });
}
