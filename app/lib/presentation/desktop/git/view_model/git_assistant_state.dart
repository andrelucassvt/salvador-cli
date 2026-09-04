import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

enum GitAssistantErrorKind { sessionNotReady, sendFailed }

/// Estado da conversa dedicada do assistente Git: mensagens independentes do
/// chat principal, propostas pendentes de aprovacao e controle do drawer.
@immutable
sealed class GitAssistantState {
  const GitAssistantState();

  @override
  String toString();
}

class GitAssistantIdle extends GitAssistantState {
  const GitAssistantIdle({
    this.messages = const [],
    this.activities = const [],
    this.pendingProposals = const [],
    this.sending = false,
    this.drawerOpen = false,
    this.errorKind,
    this.error,
  });

  final List<ChatMessageEntity> messages;
  final List<ToolActivityEntity> activities;
  final List<GitActionProposal> pendingProposals;
  final bool sending;
  final bool drawerOpen;
  final GitAssistantErrorKind? errorKind;
  final Object? error;

  GitAssistantIdle copyWith({
    List<ChatMessageEntity>? messages,
    List<ToolActivityEntity>? activities,
    List<GitActionProposal>? pendingProposals,
    bool? sending,
    bool? drawerOpen,
    GitAssistantErrorKind? errorKind,
    bool clearError = false,
    Object? error,
  }) {
    return GitAssistantIdle(
      messages: messages ?? this.messages,
      activities: activities ?? this.activities,
      pendingProposals: pendingProposals ?? this.pendingProposals,
      sending: sending ?? this.sending,
      drawerOpen: drawerOpen ?? this.drawerOpen,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'GitAssistantIdle(messages: ${messages.length}, '
      'pendingProposals: ${pendingProposals.length}, sending: $sending, '
      'drawerOpen: $drawerOpen, errorKind: $errorKind, error: $error)';
}
