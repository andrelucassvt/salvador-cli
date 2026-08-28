import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const ChatIdle());

  final ChatRepository _repository;
  final DateTime Function() _clock;
  StreamSubscription<ToolActivityEntity>? _activitySubscription;
  bool _ready = false;

  /// Chamado pela View a cada mudanca de `WorkspaceState` (conectado +
  /// modelo em execucao) - substitui a checagem
  /// `connectionState == ready && modelState == running` de
  /// `desktop_controller.dart:544-554`.
  void updateReadiness(bool ready) => _ready = ready;

  void attachSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory root,
    required AgentPermissions permissions,
  }) {
    _repository.configureSession(
      host: host,
      model: model,
      options: options,
      root: root,
      permissions: permissions,
    );
    unawaited(_activitySubscription?.cancel());
    _activitySubscription = _repository.toolActivity.listen(_onActivity);
    emit(const ChatIdle());
  }

  Future<void> send(String input) async {
    final normalized = input.trim();
    final current = state as ChatIdle;
    if (normalized.isEmpty || current.sending) return;
    if (!_ready) {
      emit(current.copyWith(errorKind: ChatErrorKind.sessionNotReady));
      return;
    }

    final withUserMessage = current.copyWith(
      messages: [
        ...current.messages,
        ChatMessageEntity(role: ChatRole.user, content: normalized),
      ],
      sending: true,
      sessionFirstPrompt: current.sessionFirstPrompt ?? normalized,
      sessionStartedAt: current.sessionStartedAt ?? _clock(),
      clearError: true,
    );
    emit(withUserMessage);

    final result = await _repository.send(normalized);
    switch (result) {
      case Error(:final error):
        emit(
          (state as ChatIdle).copyWith(
            sending: false,
            errorKind: ChatErrorKind.sendFailed,
            error: error,
          ),
        );
      case Ok(:final value):
        emit(
          (state as ChatIdle).copyWith(
            sending: false,
            messages: [
              ...(state as ChatIdle).messages,
              ChatMessageEntity(
                role: ChatRole.assistant,
                content: value.answer,
                metrics: value.metrics,
                mentionedFiles: value.mentionedFiles,
                warnings: value.warnings,
              ),
            ],
          ),
        );
    }
  }

  /// Encerra a sessao em andamento: reporta o resumo (se houver primeiro
  /// prompt) via callback para quem persiste (`WorkspaceCubit`, na View) e
  /// limpa mensagens/atividades - porta `newSession()` de
  /// `desktop_controller.dart:479-496`.
  void newSession({
    required void Function(PersistedSessionSummaryEntity summary)
    onSessionEnded,
  }) {
    final summary = (state as ChatIdle).currentSessionSummary;
    if (summary != null) onSessionEnded(summary);
    clearSession();
  }

  void clearSession() {
    _repository.clearSession();
    emit(const ChatIdle());
  }

  void _onActivity(ToolActivityEntity activity) {
    final current = state;
    if (current is! ChatIdle) return;
    emit(current.copyWith(activities: [activity, ...current.activities]));
  }

  @override
  Future<void> close() {
    unawaited(_activitySubscription?.cancel());
    return super.close();
  }
}
