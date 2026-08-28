import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract interface class ChatClient {
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  });
}

class OllamaClient implements ChatClient {
  OllamaClient({
    required this.model,
    Uri? baseUrl,
    HttpClient? httpClient,
    this.options = const InferenceOptions(),
  }) : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:11434'),
       _httpClient = httpClient ?? HttpClient();

  final String model;
  final Uri baseUrl;
  final InferenceOptions options;
  final HttpClient _httpClient;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    final decoded = await _postJson('/api/chat', {
      'model': model,
      'stream': false,
      'messages': messages.map((message) => message.toJson()).toList(),
      'tools': tools.map((tool) => tool.toJson()).toList(),
      'options': {
        'temperature': options.temperature,
        if (options.contextLength != null) 'num_ctx': options.contextLength,
      },
      if (options.keepAlive != null) 'keep_alive': options.keepAlive!.inSeconds,
    });

    final message = decoded['message'];
    if (message is! Map) {
      throw const OllamaException('Resposta sem campo message.');
    }
    return AgentMessage.fromJson(
      message.cast<String, Object?>(),
    ).withMetrics(InferenceMetrics.fromJson(decoded));
  }

  /// Consulta a versao do servidor apenas para validar que ele responde.
  Future<void> testConnection() async {
    await _getJson('/api/version');
  }

  /// Modelos instalados, conforme `/api/tags`.
  Future<List<OllamaModelInfo>> listModels() async {
    final decoded = await _getJson('/api/tags');
    final models = decoded['models'];
    if (models is! List) return const [];
    return models
        .whereType<Map>()
        .map((model) => OllamaModelInfo.fromJson(model.cast<String, Object?>()))
        .toList(growable: false);
  }

  /// Modelos carregados, conforme `/api/ps`, marcando quais ainda estao
  /// instalados a partir da lista fornecida.
  Future<List<OllamaRunningModel>> listRunningModels({
    List<OllamaModelInfo>? installed,
  }) async {
    final installedNames = {
      for (final model in installed ?? const <OllamaModelInfo>[]) model.name,
    };
    final decoded = await _getJson('/api/ps');
    final models = decoded['models'];
    if (models is! List) return const [];
    return models
        .whereType<Map>()
        .map(
          (model) => OllamaRunningModel.fromJson(
            model.cast<String, Object?>(),
            installedNames: installedNames,
          ),
        )
        .toList(growable: false);
  }

  /// Contexto configurado para um modelo, mesmo quando parado, via
  /// `/api/show`. Retorna null quando a resposta nao informa o campo.
  Future<int?> showModel(String name) async {
    final decoded = await _postJson('/api/show', {'model': name});
    final info = decoded['model_info'];
    if (info is! Map) return null;
    for (final entry in info.entries) {
      final key = entry.key;
      if (key == 'context_length' || key.endsWith('.context_length')) {
        return entry.value is num ? (entry.value as num).toInt() : null;
      }
    }
    return null;
  }

  /// Precarrega um modelo com `/api/generate`, prompt vazio e o keep-alive
  /// informado (default de 5 minutos, como o Ollama).
  Future<void> loadModel(
    String name, {
    Duration keepAlive = const Duration(minutes: 5),
  }) async {
    await _generateKeepAlive(name, keepAlive.inSeconds);
  }

  /// Descarrega um modelo imediatamente, com `keep_alive: 0`.
  Future<void> unloadModel(String name) async {
    await _generateKeepAlive(name, 0);
  }

  Future<void> _generateKeepAlive(String name, int keepAliveSeconds) async {
    await _postJson('/api/generate', {
      'model': name,
      'prompt': '',
      'stream': false,
      'keep_alive': keepAliveSeconds,
    });
  }

  Future<Map<String, Object?>> _getJson(String path) async {
    final request = await _httpClient.getUrl(baseUrl.resolve(path));
    return _readJson(request);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final request = await _httpClient.postUrl(baseUrl.resolve(path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return _readJson(request);
  }

  Future<Map<String, Object?>> _readJson(HttpClientRequest request) async {
    final timeout = options.timeout;
    final HttpClientResponse response;
    try {
      response = timeout == null
          ? await request.close()
          : await request.close().timeout(timeout);
    } on TimeoutException {
      throw const OllamaException('Ollama excedeu o limite de tempo.');
    }

    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OllamaException(
        'Ollama respondeu ${response.statusCode}: ${_errorMessage(body)}',
      );
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded.cast<String, Object?>();
      throw const OllamaException(
        'Resposta invalida do Ollama: corpo nao e um objeto JSON.',
      );
    } on FormatException catch (error) {
      throw OllamaException('Resposta invalida do Ollama: ${error.message}');
    }
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Mantem o corpo original quando nao for JSON.
    }
    return body.isEmpty ? 'erro sem detalhes' : body;
  }
}

class OllamaException implements Exception {
  const OllamaException(this.message);

  final String message;

  @override
  String toString() => message;
}
