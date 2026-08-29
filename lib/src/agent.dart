import 'dart:io';

import 'context_files.dart';
import 'file_mentions.dart';
import 'models.dart';
import 'ollama_client.dart';
import 'prompt.dart';
import 'tools.dart';

typedef ToolCallObserver = void Function(ToolCall call);
typedef ToolResultObserver = void Function(ToolCall call, String result);

class AgentSession {
  AgentSession({
    required this.client,
    Directory? root,
    this.maxToolRounds = 8,
    this.onToolCall,
    this.onToolResult,
    AgentPermissions permissions = const AgentPermissions(),
    ContextFilesService? contextFiles,
  }) : _tools = ToolRegistry(
         root,
         permissions: permissions,
         contextFiles: contextFiles,
       ),
       _mentions = root == null ? null : FileMentionService(root),
       _systemMessage = AgentMessage(
         role: 'system',
         content: _systemContent(root, contextFiles),
       ) {
    clear();
  }

  final ChatClient client;
  final ToolRegistry _tools;
  final FileMentionService? _mentions;
  final AgentMessage _systemMessage;
  final int maxToolRounds;
  final ToolCallObserver? onToolCall;
  final ToolResultObserver? onToolResult;
  final List<AgentMessage> _messages = [];

  static String _systemContent(
    Directory? root,
    ContextFilesService? contextFiles,
  ) {
    if (root == null) return systemPrompt;
    final agentsMd = contextFiles?.agentsMdContext();
    return '$systemPrompt\nRaiz: ${root.absolute.path}'
        '${agentsMd ?? ''}';
  }

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  void clear() {
    _messages
      ..clear()
      ..add(_systemMessage);
  }

  Future<String> send(String input) async => (await sendDetailed(input)).answer;

  Future<AgentTurnResult> sendDetailed(
    String input, {
    List<String> images = const [],
  }) async {
    if (input.trim().isEmpty && images.isEmpty) {
      return const AgentTurnResult(answer: '');
    }
    final expansion =
        _mentions?.expand(input) ?? MentionExpansion(prompt: input);
    _messages.add(
      AgentMessage(role: 'user', content: expansion.prompt, images: images),
    );
    InferenceMetrics? combinedMetrics;

    for (var round = 0; round <= maxToolRounds; round++) {
      final response = await client.chat(
        messages: List.unmodifiable(_messages),
        tools: _tools.definitions,
      );
      _messages.add(response);
      final metrics = response.metrics;
      if (metrics != null) {
        combinedMetrics = combinedMetrics == null
            ? metrics
            : combinedMetrics + metrics;
      }

      if (response.toolCalls.isEmpty) {
        return AgentTurnResult(
          answer: response.content,
          metrics: combinedMetrics,
          mentionedFiles: expansion.files,
          warnings: expansion.warnings,
        );
      }
      if (round == maxToolRounds) {
        throw AgentException(
          'Limite de $maxToolRounds rodadas de ferramentas atingido.',
        );
      }

      for (final call in response.toolCalls) {
        onToolCall?.call(call);
        final result = await _tools.execute(call);
        onToolResult?.call(call, result);
        _messages.add(
          AgentMessage(role: 'tool', content: result, toolName: call.name),
        );
      }
    }

    throw const AgentException('Loop do agente terminou inesperadamente.');
  }
}

class AgentTurnResult {
  const AgentTurnResult({
    required this.answer,
    this.metrics,
    this.mentionedFiles = const [],
    this.warnings = const [],
  });

  final String answer;
  final InferenceMetrics? metrics;
  final List<String> mentionedFiles;
  final List<String> warnings;
}

class AgentException implements Exception {
  const AgentException(this.message);

  final String message;

  @override
  String toString() => message;
}
