import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/services/file_attachment_service.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/attached_file_entity.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit(
    this._repository, {
    DateTime Function()? clock,
    FileAttachmentService? attachments,
  }) : _clock = clock ?? DateTime.now,
       _attachments = attachments ?? const FileAttachmentService(),
       super(const ChatIdle());

  final ChatRepository _repository;
  final DateTime Function() _clock;
  final FileAttachmentService _attachments;
  StreamSubscription<ToolActivityEntity>? _activitySubscription;
  bool _ready = false;

  void addAttachments(List<String> paths) {
    final current = state as ChatIdle;
    final existing = current.pendingAttachments.map((a) => a.path).toSet();
    final added = <AttachedFileEntity>[
      for (final path in paths)
        if (existing.add(path))
          AttachedFileEntity(
            path: path,
            name: File(path).uri.pathSegments.last,
          ),
    ];
    if (added.isEmpty) return;
    emit(
      current.copyWith(
        pendingAttachments: [...current.pendingAttachments, ...added],
      ),
    );
  }

  void removeAttachment(String path) {
    final current = state as ChatIdle;
    emit(
      current.copyWith(
        pendingAttachments: current.pendingAttachments
            .where((a) => a.path != path)
            .toList(growable: false),
      ),
    );
  }

  /// Chamado pela View a cada mudanca de `WorkspaceState` (conectado +
  /// modelo em execucao).
  void updateReadiness(bool ready) => _ready = ready;

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
    emit(const ChatIdle());
  }

  Future<void> send(String input) async {
    final normalized = input.trim();
    final current = state as ChatIdle;
    if ((normalized.isEmpty && current.pendingAttachments.isEmpty) ||
        current.sending) {
      return;
    }
    if (!_ready) {
      emit(current.copyWith(errorKind: ChatErrorKind.sessionNotReady));
      return;
    }

    final attachedNames = <String>[];
    final attachmentWarnings = <String>[];
    final attachmentBlocks = StringBuffer();
    final images = <String>[];
    for (final attachment in current.pendingAttachments) {
      switch (_attachments.readContent(attachment.path)) {
        case AttachmentContent(:final content):
          attachedNames.add(attachment.name);
          attachmentBlocks
            ..writeln()
            ..writeln('--- arquivo anexado: ${attachment.name} ---')
            ..writeln(content)
            ..writeln('--- fim do arquivo: ${attachment.name} ---');
        case AttachmentImage(:final base64):
          attachedNames.add(attachment.name);
          images.add(base64);
        case AttachmentRejected(:final reason):
          attachmentWarnings.add('${attachment.name} ignorado: $reason.');
      }
    }
    final outgoing = attachmentBlocks.isEmpty
        ? normalized
        : '$normalized\n$attachmentBlocks';

    final withUserMessage = current.copyWith(
      messages: [
        ...current.messages,
        ChatMessageEntity(
          role: ChatRole.user,
          content: normalized,
          attachedFiles: attachedNames,
          warnings: attachmentWarnings,
        ),
      ],
      pendingAttachments: const [],
      sending: true,
      sessionFirstPrompt: current.sessionFirstPrompt ?? normalized,
      sessionStartedAt: current.sessionStartedAt ?? _clock(),
      clearError: true,
    );
    emit(withUserMessage);

    final result = await _repository.send(outgoing, images: images);
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
  /// limpa mensagens/atividades.
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
