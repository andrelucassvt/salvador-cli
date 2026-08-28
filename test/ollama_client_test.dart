import 'dart:async';
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

  test(
    'decodifica nome, tamanho, familia, quantizacao e data de /api/tags',
    () async {
      final server = await serveJson('/api/tags', {
        'models': [
          {
            'name': 'llama3.2:3b',
            'size': 2019393189,
            'modified_at': '2025-03-05T10:00:00.123456789Z',
            'details': {'family': 'llama', 'quantization_level': 'Q4_K_M'},
          },
          {'name': 'gemma2:2b', 'size': 1600000000},
        ],
      });

      final client = OllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final models = await client.listModels();

      expect(models, hasLength(2));
      expect(models.first.name, 'llama3.2:3b');
      expect(models.first.sizeBytes, 2019393189);
      expect(models.first.family, 'llama');
      expect(models.first.quantization, 'Q4_K_M');
      expect(models.first.modifiedAt?.year, 2025);
      expect(models.last.family, isNull);
      expect(models.last.quantization, isNull);
      expect(models.last.modifiedAt, isNull);
    },
  );

  test(
    'combina /api/ps com modelos instalados e tolera campos ausentes',
    () async {
      final server = await serveJson('/api/ps', {
        'models': [
          {
            'name': 'llama3.2:3b',
            'model': 'llama3.2:3b',
            'size': 6000000000,
            'size_vram': 4000000000,
            'context_length': 8192,
            'expires_at': '2026-08-28T15:00:00Z',
          },
          {'name': 'gemma2:2b', 'size': 3000000000},
        ],
      });

      final client = OllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final running = await client.listRunningModels(
        installed: [const OllamaModelInfo(name: 'llama3.2:3b')],
      );

      expect(running, hasLength(2));
      expect(running.first.name, 'llama3.2:3b');
      expect(running.first.sizeBytes, 6000000000);
      expect(running.first.sizeVramBytes, 4000000000);
      expect(running.first.contextLength, 8192);
      expect(running.first.expiresAt?.year, 2026);
      expect(running.first.isInstalled, isTrue);
      expect(running.last.isInstalled, isFalse);
      expect(running.last.sizeVramBytes, 0);
      expect(running.last.contextLength, 0);
      expect(running.last.expiresAt, isNull);
    },
  );

  test('recupera o contexto de um modelo parado via /api/show', () async {
    final server = await serveJson('/api/show', {
      'model': 'llama3.2:3b',
      'model_info': {
        'general.architecture': 'llama',
        'llama.context_length': 8192,
      },
    });

    final client = OllamaClient(
      model: 'llama3.2:3b',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final context = await client.showModel('llama3.2:3b');

    expect(context, 8192);
  });

  test(
    'showModel retorna null quando o contexto nao existe na resposta',
    () async {
      final server = await serveJson('/api/show', {'model': 'gemma2:2b'});

      final client = OllamaClient(
        model: 'gemma2:2b',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final context = await client.showModel('gemma2:2b');

      expect(context, isNull);
    },
  );

  test(
    'preload e unload usam /api/generate com stream false e prompt vazio',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final bodies = <Map<String, Object?>>[];

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/generate');
        bodies.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'done': true}));
        await request.response.close();
      });

      final client = OllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      await client.loadModel(
        'llama3.2:3b',
        keepAlive: const Duration(minutes: 10),
      );
      await client.unloadModel('llama3.2:3b');

      expect(bodies, hasLength(2));
      final load = bodies.first;
      expect(load['model'], 'llama3.2:3b');
      expect(load['prompt'], '');
      expect(load['stream'], isFalse);
      expect(load['keep_alive'], 600);
      final unload = bodies.last;
      expect(unload['model'], 'llama3.2:3b');
      expect(unload['prompt'], '');
      expect(unload['stream'], isFalse);
      expect(unload['keep_alive'], 0);
    },
  );

  test('envia temperatura, num_ctx e keep_alive no /api/chat', () async {
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
          'message': {'role': 'assistant', 'content': 'ok'},
        }),
      );
      await request.response.close();
    });

    final client = OllamaClient(
      model: 'modelo-teste',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      options: const InferenceOptions(
        temperature: 0.4,
        contextLength: 2048,
        keepAlive: Duration(minutes: 30),
      ),
    );
    await client.chat(
      messages: [AgentMessage(role: 'user', content: 'oi')],
      tools: const [],
    );

    expect(requestBody['stream'], isFalse);
    expect(requestBody['keep_alive'], 1800);
    final options = requestBody['options'] as Map<String, Object?>;
    expect(options['temperature'], 0.4);
    expect(options['num_ctx'], 2048);
  });

  test('mantem a temperatura padrao quando nao ha opcoes', () async {
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
          'message': {'role': 'assistant', 'content': 'ok'},
        }),
      );
      await request.response.close();
    });

    final client = OllamaClient(
      model: 'modelo-teste',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    await client.chat(
      messages: [AgentMessage(role: 'user', content: 'oi')],
      tools: const [],
    );

    final options = requestBody['options'] as Map<String, Object?>;
    expect(options['temperature'], 0.1);
    expect(options.containsKey('num_ctx'), isFalse);
    expect(requestBody.containsKey('keep_alive'), isFalse);
  });

  test('transforma status invalido em OllamaException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'modelo nao encontrado'}));
      await request.response.close();
    });

    final client = OllamaClient(
      model: 'modelo-teste',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );

    expect(
      () => client.chat(
        messages: [AgentMessage(role: 'user', content: 'oi')],
        tools: const [],
      ),
      throwsA(
        isA<OllamaException>().having(
          (error) => error.message,
          'message',
          contains('modelo nao encontrado'),
        ),
      ),
    );
  });

  test('transforma timeout do chat em OllamaException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'message': {'role': 'assistant', 'content': 'ok'},
        }),
      );
      await request.response.close();
    });

    final client = OllamaClient(
      model: 'modelo-teste',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      options: const InferenceOptions(timeout: Duration(milliseconds: 20)),
    );

    expect(
      () => client.chat(
        messages: [AgentMessage(role: 'user', content: 'oi')],
        tools: const [],
      ),
      throwsA(isA<OllamaException>()),
    );
  });

  test(
    'testConnection consulta /api/version sem lancar em servidor saudavel',
    () async {
      final server = await serveJson('/api/version', {'version': '0.9.2'});

      final client = OllamaClient(
        model: 'modelo-teste',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(client.testConnection(), completes);
    },
  );

  test(
    'testConnection converte falha do servidor em OllamaException',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.statusCode = 503;
        await request.response.close();
      });

      final client = OllamaClient(
        model: 'modelo-teste',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(() => client.testConnection(), throwsA(isA<OllamaException>()));
    },
  );
}

Future<HttpServer> serveJson(String path, Map<String, Object?> body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  server.listen((request) async {
    expect(request.uri.path, path);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}
