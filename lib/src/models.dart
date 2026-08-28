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
    this.metrics,
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
  final InferenceMetrics? metrics;

  AgentMessage withMetrics(InferenceMetrics value) => AgentMessage(
    role: role,
    content: content,
    toolCalls: toolCalls,
    toolName: toolName,
    metrics: value,
  );

  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls.map((call) => call.toJson()).toList(),
    if (toolName != null) 'tool_name': toolName,
  };
}

/// Technical counters returned by Ollama after one completed generation.
/// Durations are kept in nanoseconds, exactly as the API reports them.
class InferenceMetrics {
  const InferenceMetrics({
    this.promptTokens = 0,
    this.generatedTokens = 0,
    this.promptDurationNanoseconds = 0,
    this.generationDurationNanoseconds = 0,
    this.totalDurationNanoseconds = 0,
    this.loadDurationNanoseconds = 0,
    this.generations = 1,
  });

  factory InferenceMetrics.fromJson(Map<String, Object?> json) =>
      InferenceMetrics(
        promptTokens: _integer(json['prompt_eval_count']),
        generatedTokens: _integer(json['eval_count']),
        promptDurationNanoseconds: _integer(json['prompt_eval_duration']),
        generationDurationNanoseconds: _integer(json['eval_duration']),
        totalDurationNanoseconds: _integer(json['total_duration']),
        loadDurationNanoseconds: _integer(json['load_duration']),
      );

  final int promptTokens;
  final int generatedTokens;
  final int promptDurationNanoseconds;
  final int generationDurationNanoseconds;
  final int totalDurationNanoseconds;
  final int loadDurationNanoseconds;
  final int generations;

  double? get tokensPerSecond => generationDurationNanoseconds > 0
      ? generatedTokens * 1000000000 / generationDurationNanoseconds
      : null;

  double get generationSeconds => generationDurationNanoseconds / 1000000000;
  double get totalSeconds => totalDurationNanoseconds / 1000000000;

  InferenceMetrics operator +(InferenceMetrics other) => InferenceMetrics(
    promptTokens: promptTokens + other.promptTokens,
    generatedTokens: generatedTokens + other.generatedTokens,
    promptDurationNanoseconds:
        promptDurationNanoseconds + other.promptDurationNanoseconds,
    generationDurationNanoseconds:
        generationDurationNanoseconds + other.generationDurationNanoseconds,
    totalDurationNanoseconds:
        totalDurationNanoseconds + other.totalDurationNanoseconds,
    loadDurationNanoseconds:
        loadDurationNanoseconds + other.loadDurationNanoseconds,
    generations: generations + other.generations,
  );

  static int _integer(Object? value) => value is num ? value.toInt() : 0;
}

String formatInferenceMetrics(InferenceMetrics metrics) {
  final rate = metrics.tokensPerSecond;
  final rateText = rate == null ? 'n/d' : '${rate.toStringAsFixed(1)} tok/s';
  final rounds = metrics.generations > 1
      ? ' | ${metrics.generations} geracoes'
      : '';
  return 'metricas> $rateText | ${metrics.generatedTokens} tokens de saida | '
      '${metrics.promptTokens} tokens de entrada | '
      '${metrics.generationSeconds.toStringAsFixed(2)}s gerando | '
      '${metrics.totalSeconds.toStringAsFixed(2)}s total$rounds';
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

/// Parametros de inferencia aplicados a toda chamada de chat do cliente.
/// [temperature] preserva o default atual de 0.1; os demais campos so sao
/// enviados ao Ollama quando definidos.
class InferenceOptions {
  const InferenceOptions({
    this.temperature = 0.1,
    this.contextLength,
    this.keepAlive,
    this.timeout,
  });

  final double temperature;
  final int? contextLength;
  final Duration? keepAlive;
  final Duration? timeout;
}

/// Modelo instalado, conforme retornado por `/api/tags`.
class OllamaModelInfo {
  const OllamaModelInfo({
    required this.name,
    this.sizeBytes = 0,
    this.family,
    this.quantization,
    this.modifiedAt,
  });

  factory OllamaModelInfo.fromJson(Map<String, Object?> json) {
    final details = json['details'];
    final detailsMap = details is Map
        ? details.cast<String, Object?>()
        : const <String, Object?>{};
    return OllamaModelInfo(
      name: json['name'] as String? ?? '',
      sizeBytes: _integer(json['size']),
      family: detailsMap['family'] as String?,
      quantization: detailsMap['quantization_level'] as String?,
      modifiedAt: _dateTime(json['modified_at']),
    );
  }

  final String name;
  final int sizeBytes;
  final String? family;
  final String? quantization;
  final DateTime? modifiedAt;
}

/// Modelo carregado na memoria, conforme retornado por `/api/ps`.
/// [isInstalled] vem da combinacao com a lista de modelos instalados,
/// pois o Ollama mantem modelos carregados mesmo depois de removidos.
class OllamaRunningModel {
  const OllamaRunningModel({
    required this.name,
    this.model,
    this.sizeBytes = 0,
    this.sizeVramBytes = 0,
    this.contextLength = 0,
    this.expiresAt,
    this.isInstalled = false,
  });

  factory OllamaRunningModel.fromJson(
    Map<String, Object?> json, {
    Set<String> installedNames = const {},
  }) => OllamaRunningModel(
    name: json['name'] as String? ?? '',
    model: json['model'] as String?,
    sizeBytes: _integer(json['size']),
    sizeVramBytes: _integer(json['size_vram']),
    contextLength: _integer(json['context_length']),
    expiresAt: _dateTime(json['expires_at']),
    isInstalled: installedNames.contains(json['name']),
  );

  final String name;
  final String? model;
  final int sizeBytes;
  final int sizeVramBytes;
  final int contextLength;
  final DateTime? expiresAt;
  final bool isInstalled;
}

int _integer(Object? value) => value is num ? value.toInt() : 0;

DateTime? _dateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
