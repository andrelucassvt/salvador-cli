import 'dart:convert';

class ToolCall {
  ToolCall({required this.name, required this.arguments, this.id});

  factory ToolCall.fromJson(Map<String, Object?> json) {
    final function = json['function'];
    if (function is! Map) {
      throw const FormatException('Tool call sem campo function valido.');
    }

    final name = function['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Tool call sem nome valido.');
    }

    final rawArguments = function['arguments'];
    final arguments = switch (rawArguments) {
      Map() => rawArguments.cast<String, Object?>(),
      String() => _decodeArguments(rawArguments),
      null => <String, Object?>{},
      _ => throw const FormatException('Argumentos da tool call invalidos.'),
    };

    return ToolCall(
      id: json['id'] as String?,
      name: name,
      arguments: arguments,
    );
  }

  final String? id;
  final String name;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'function': {'name': name, 'arguments': arguments},
  };

  static Map<String, Object?> _decodeArguments(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'Argumentos da tool call devem ser um objeto.',
      );
    }
    return decoded.cast<String, Object?>();
  }
}

class AgentMessage {
  AgentMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolName,
  });

  factory AgentMessage.fromJson(Map<String, Object?> json) {
    final role = json['role'];
    if (role is! String) {
      throw const FormatException('Mensagem sem role valido.');
    }

    final rawCalls = json['tool_calls'];
    final toolCalls = rawCalls is List
        ? rawCalls
              .map(
                (call) =>
                    ToolCall.fromJson((call as Map).cast<String, Object?>()),
              )
              .toList(growable: false)
        : const <ToolCall>[];

    return AgentMessage(
      role: role,
      content: json['content'] as String? ?? '',
      toolCalls: toolCalls,
      toolName: json['tool_name'] as String?,
    );
  }

  final String role;
  final String content;
  final List<ToolCall> toolCalls;
  final String? toolName;

  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls.map((call) => call.toJson()).toList(),
    if (toolName != null) 'tool_name': toolName,
  };
}

class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.properties,
    this.required = const [],
  });

  final String name;
  final String description;
  final Map<String, Object?> properties;
  final List<String> required;

  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    },
  };
}
