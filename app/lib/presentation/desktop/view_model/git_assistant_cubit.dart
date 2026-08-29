import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/domain/interfaces/git_assistant_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_assistant_state.dart';

class GitAssistantCubit extends Cubit<GitAssistantState> {
  GitAssistantCubit(this._repository) : super(const GitAssistantIdle());

  final GitAssistantRepository _repository;
  StreamSubscription<ToolActivityEntity>? _activitySubscription;
  bool _ready = false;
  String? _context;

  void updateReadiness(bool ready) => _ready = ready;

  /// Chamado pela View a cada mudanca de `WorkspaceState`: configura a
  /// sessao dedicada e reinicia a conversa do assistente.
  void attachSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
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
    emit(const GitAssistantIdle());
  }

  void openDrawer() {
    final current = state as GitAssistantIdle;
    if (current.drawerOpen) return;
    emit(current.copyWith(drawerOpen: true, clearError: true));
  }

  void closeDrawer() {
    final current = state as GitAssistantIdle;
    if (!current.drawerOpen) return;
    emit(current.copyWith(drawerOpen: false));
  }

  void toggleDrawer() {
    final current = state as GitAssistantIdle;
    emit(current.copyWith(drawerOpen: !current.drawerOpen, clearError: true));
  }

  /// Contexto serializado da selecao atual (ref/commit/arquivo); null zera.
  void setContext(String? context) => _context = context;

  Future<void> send(String input) async {
    final normalized = input.trim();
    final current = state as GitAssistantIdle;
    if (normalized.isEmpty || current.sending) return;
    if (!_ready) {
      emit(current.copyWith(errorKind: GitAssistantErrorKind.sessionNotReady));
      return;
    }

    emit(
      current.copyWith(
        sending: true,
        messages: [
          ...current.messages,
          ChatMessageEntity(role: ChatRole.user, content: normalized),
        ],
        clearError: true,
      ),
    );

    final result = await _repository.send(input: normalized, context: _context);
    final latest = state as GitAssistantIdle;
    switch (result) {
      case Ok(:final value):
        emit(
          latest.copyWith(
            sending: false,
            messages: [
              ...latest.messages,
              ChatMessageEntity(
                role: ChatRole.assistant,
                content: value.answer,
              ),
            ],
            pendingProposals: [...latest.pendingProposals, ...value.proposals],
          ),
        );
      case Error(:final error):
        emit(
          latest.copyWith(
            sending: false,
            errorKind: GitAssistantErrorKind.sendFailed,
            error: error,
          ),
        );
    }
  }

  /// Remove uma proposta pendente sem executar nada (cancelamento).
  void dismissProposal(GitActionProposal proposal) {
    final current = state as GitAssistantIdle;
    emit(
      current.copyWith(
        pendingProposals: current.pendingProposals
            .where((pending) => pending != proposal)
            .toList(growable: false),
      ),
    );
  }

  void newSession() {
    _repository.clearSession();
    emit(const GitAssistantIdle());
  }

  void _onActivity(ToolActivityEntity activity) {
    final current = state as GitAssistantIdle;
    emit(current.copyWith(activities: [...current.activities, activity]));
  }
}
