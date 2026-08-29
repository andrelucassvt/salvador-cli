import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

enum ChatRole { user, assistant }

@immutable
class ChatMessageEntity {
  const ChatMessageEntity({
    required this.role,
    required this.content,
    this.metrics,
    this.mentionedFiles = const [],
    this.attachedFiles = const [],
    this.warnings = const [],
  });

  final ChatRole role;
  final String content;
  final InferenceMetrics? metrics;
  final List<String> mentionedFiles;
  final List<String> attachedFiles;
  final List<String> warnings;

  ChatMessageEntity copyWith({
    ChatRole? role,
    String? content,
    InferenceMetrics? metrics,
    List<String>? mentionedFiles,
    List<String>? attachedFiles,
    List<String>? warnings,
  }) {
    return ChatMessageEntity(
      role: role ?? this.role,
      content: content ?? this.content,
      metrics: metrics ?? this.metrics,
      mentionedFiles: mentionedFiles ?? this.mentionedFiles,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageEntity &&
          role == other.role &&
          content == other.content &&
          metrics == other.metrics &&
          listEquals(mentionedFiles, other.mentionedFiles) &&
          listEquals(attachedFiles, other.attachedFiles) &&
          listEquals(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    role,
    content,
    metrics,
    Object.hashAll(mentionedFiles),
    Object.hashAll(attachedFiles),
    Object.hashAll(warnings),
  );

  @override
  String toString() =>
      'ChatMessageEntity(role: $role, content: $content, '
      'mentionedFiles: $mentionedFiles, attachedFiles: $attachedFiles, '
      'warnings: $warnings)';
}
