import 'dart:convert';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  test('envia o contrato de chat e decodifica tool calls', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    late Map<String, Object?> requestBody;

    server.listen((request) async {
      requestBody =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'write_file',
                  'arguments': {'path': 'a.txt', 'content': 'a'},
                },
              },
            ],
          },
          'prompt_eval_count': 100,
          'prompt_eval_duration': 200000000,
          'eval_count': 25,
          'eval_duration': 500000000,
          'total_duration': 800000000,
          'load_duration': 100000000,
        }),
      );
      await request.response.close();
    });

    final client = OllamaClient(
      model: 'modelo-teste',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final message = await client.chat(
      messages: [AgentMessage(role: 'user', content: 'crie a.txt')],
      tools: const [
        ToolDefinition(
          name: 'write_file',
          description: 'grava',
          properties: {},
        ),
      ],
    );

    expect(requestBody['model'], 'modelo-teste');
    expect(requestBody['stream'], isFalse);
    expect(requestBody['tools'], isA<List<Object?>>());
    expect(message.toolCalls.single.name, 'write_file');
    expect(message.toolCalls.single.arguments['path'], 'a.txt');
    expect(message.metrics?.promptTokens, 100);
    expect(message.metrics?.generatedTokens, 25);
    expect(message.metrics?.tokensPerSecond, 50);
    expect(
      formatInferenceMetrics(message.metrics!),
      'metricas> 50.0 tok/s | 25 tokens de saida | 100 tokens de entrada | '
      '0.50s gerando | 0.80s total',
    );
  });
}
