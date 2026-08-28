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
  OllamaClient({required this.model, Uri? baseUrl, HttpClient? httpClient})
    : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:11434'),
      _httpClient = httpClient ?? HttpClient();

  final String model;
  final Uri baseUrl;
  final HttpClient _httpClient;

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    final endpoint = baseUrl.resolve('/api/chat');
    final request = await _httpClient.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': model,
        'stream': false,
        'messages': messages.map((message) => message.toJson()).toList(),
        'tools': tools.map((tool) => tool.toJson()).toList(),
        'options': {'temperature': 0.1},
      }),
    );

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OllamaException(
        'Ollama respondeu ${response.statusCode}: ${_errorMessage(body)}',
      );
    }

    try {
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final message = decoded['message'];
      if (message is! Map) {
        throw const FormatException('Resposta sem campo message.');
      }
      return AgentMessage.fromJson(message.cast<String, Object?>());
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
