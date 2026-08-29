import 'package:flutter/foundation.dart';
import 'package:salvador_desktop/domain/entities/attached_file_entity.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

enum ChatErrorKind { sessionNotReady, sendFailed }

/// Mesmo padrão de `WorkspaceState`: um único estado de conteúdo, não
/// Initial/Loading/Loaded/Error separados - `sending` e o erro sao campos,
/// porque a lista de mensagens precisa continuar visivel enquanto uma nova
/// resposta carrega.
@immutable
sealed class ChatState {
  const ChatState();

  @override
  String toString();
}

class ChatIdle extends ChatState {
  const ChatIdle({
    this.messages = const [],
    this.activities = const [],
    this.pendingAttachments = const [],
    this.sending = false,
    this.sessionFirstPrompt,
    this.sessionStartedAt,
    this.errorKind,
    this.error,
  });

  static const _maxSessionTitleLength = 80;

  final List<ChatMessageEntity> messages;
  final List<ToolActivityEntity> activities;
  final List<AttachedFileEntity> pendingAttachments;
  final bool sending;
  final String? sessionFirstPrompt;
  final DateTime? sessionStartedAt;
  final ChatErrorKind? errorKind;
  final Object? error;

  /// Resumo em memoria da sessao em andamento, sem historico de mensagens.
  PersistedSessionSummaryEntity? get currentSessionSummary {
    final firstPrompt = sessionFirstPrompt;
    final startedAt = sessionStartedAt;
    if (firstPrompt == null || startedAt == null) return null;
    final title = firstPrompt.length > _maxSessionTitleLength
        ? firstPrompt.substring(0, _maxSessionTitleLength)
        : firstPrompt;
    return PersistedSessionSummaryEntity(
      title: title,
      startedAt: startedAt,
      actionCount: activities.length,
    );
  }

  ChatIdle copyWith({
    List<ChatMessageEntity>? messages,
    List<ToolActivityEntity>? activities,
    List<AttachedFileEntity>? pendingAttachments,
    bool? sending,
    String? sessionFirstPrompt,
    DateTime? sessionStartedAt,
    ChatErrorKind? errorKind,
    bool clearError = false,
    Object? error,
  }) {
    return ChatIdle(
      messages: messages ?? this.messages,
      activities: activities ?? this.activities,
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      sending: sending ?? this.sending,
      sessionFirstPrompt: sessionFirstPrompt ?? this.sessionFirstPrompt,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'ChatIdle(messages: ${messages.length}, activities: ${activities.length}, '
      'pendingAttachments: ${pendingAttachments.length}, sending: $sending, '
      'errorKind: $errorKind, error: $error)';
}
