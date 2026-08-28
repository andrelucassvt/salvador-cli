import 'dart:io';

import 'models.dart';
import 'ollama_client.dart';
import 'prompt.dart';
import 'tools.dart';

typedef ToolCallObserver = void Function(ToolCall call);

class AgentSession {
  AgentSession({
    required this.client,
    required Directory root,
    this.maxToolRounds = 8,
    this.onToolCall,
  }) : _tools = ToolRegistry(root),
       _systemMessage = AgentMessage(
         role: 'system',
         content: '$systemPrompt\nRaiz: ${root.absolute.path}',
       ) {
    clear();
  }

  final ChatClient client;
  final ToolRegistry _tools;
  final AgentMessage _systemMessage;
  final int maxToolRounds;
  final ToolCallObserver? onToolCall;
  final List<AgentMessage> _messages = [];

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  void clear() {
    _messages
      ..clear()
      ..add(_systemMessage);
  }

  Future<String> send(String input) async {
    if (input.trim().isEmpty) return '';
    _messages.add(AgentMessage(role: 'user', content: input));

    for (var round = 0; round <= maxToolRounds; round++) {
      final response = await client.chat(
        messages: List.unmodifiable(_messages),
        tools: _tools.definitions,
      );
      _messages.add(response);

      if (response.toolCalls.isEmpty) return response.content;
      if (round == maxToolRounds) {
        throw AgentException(
          'Limite de $maxToolRounds rodadas de ferramentas atingido.',
        );
      }

      for (final call in response.toolCalls) {
        onToolCall?.call(call);
        final result = await _tools.execute(call);
        _messages.add(
          AgentMessage(role: 'tool', content: result, toolName: call.name),
        );
      }
    }

    throw const AgentException('Loop do agente terminou inesperadamente.');
  }
}

class AgentException implements Exception {
  const AgentException(this.message);

  final String message;

  @override
  String toString() => message;
}
