import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/src/desktop/desktop_controller.dart';
import 'package:salvador_desktop/src/desktop/desktop_state_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('salvador_desktop_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('sugere e insere menção de arquivo com espaços', () async {
    await File(
      '${root.path}/arquivo com espaço.dart',
    ).writeAsString('void main() {}');
    final controller = DesktopController(initialRoot: root);
    const input = 'revise @arquivo';

    final suggestions = controller.fileSuggestions(input, input.length);
    final result = controller.insertMention(
      input,
      input.length,
      suggestions.single,
    );

    expect(suggestions, ['arquivo com espaço.dart']);
    expect(result, 'revise @"arquivo com espaço.dart" ');
    controller.dispose();
  });

  test('resume atividade de ferramenta por caminho ou comando', () {
    final fileActivity = ToolActivity(
      ToolCall(name: 'read_file', arguments: {'path': 'lib/main.dart'}),
      'OK: conteudo lido',
    );
    final commandActivity = ToolActivity(
      ToolCall(name: 'run_command', arguments: {'command': 'dart test'}),
      'EXIT_CODE: 0',
    );

    expect(fileActivity.summary, 'lib/main.dart');
    expect(commandActivity.summary, 'dart test');
  });

  test(
    'inicializa restaurando preferencias persistidas sem Ollama real',
    () async {
      final stateFile = File('${root.path}/state.json');
      await DesktopStateStore(file: stateFile).save(
        DesktopPersistedState(
          host: Uri.parse('http://192.168.1.50:11434'),
          model: 'llama3.2:3b',
          inference: InferenceOptions(temperature: 0.3, contextLength: 2048),
          permissions: const AgentPermissions(allowEdit: false),
          activeRoot: root.path,
        ),
      );
      final fake = FakeOllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://192.168.1.50:11434'),
        modelsResult: const [
          OllamaModelInfo(name: 'llama3.2:3b'),
          OllamaModelInfo(name: 'gemma2:2b'),
        ],
      );
      final factoryCalls =
          <({String model, Uri baseUrl, InferenceOptions options})>[];
      final controller = DesktopController(
        initialRoot: root,
        store: DesktopStateStore(file: stateFile),
        clientFactory: ({required model, required baseUrl, required options}) {
          factoryCalls.add((model: model, baseUrl: baseUrl, options: options));
          return fake;
        },
      );

      await controller.initialize();

      expect(controller.host, Uri.parse('http://192.168.1.50:11434'));
      expect(controller.selectedModel, 'llama3.2:3b');
      expect(controller.temperature, 0.3);
      expect(controller.contextLength, 2048);
      expect(controller.allowEdit, isFalse);
      expect(controller.connectionState, OllamaConnectionState.ready);
      expect(
        controller.models.map((model) => model.name),
        containsAll(['llama3.2:3b', 'gemma2:2b']),
      );
      expect(
        factoryCalls.any(
          (call) =>
              call.model == 'llama3.2:3b' &&
              call.baseUrl.host == '192.168.1.50' &&
              call.options.temperature == 0.3,
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test(
    'troca de modelo salva selecao, carrega modelo e atualiza /api/ps',
    () async {
      final stateFile = File('${root.path}/state.json');
      final fake = FakeOllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:11434'),
        modelsResult: const [
          OllamaModelInfo(name: 'llama3.2:3b'),
          OllamaModelInfo(name: 'gemma2:2b'),
        ],
      );
      final factoryCalls =
          <({String model, Uri baseUrl, InferenceOptions options})>[];
      final controller = DesktopController(
        initialRoot: root,
        store: DesktopStateStore(file: stateFile),
        clientFactory: ({required model, required baseUrl, required options}) {
          factoryCalls.add((model: model, baseUrl: baseUrl, options: options));
          return fake;
        },
      );
      await controller.initialize();
      expect(controller.selectedModel, 'llama3.2:3b');

      await controller.selectModel('gemma2:2b');

      expect(controller.selectedModel, 'gemma2:2b');
      expect(controller.modelState, ModelRunState.running);
      expect(fake.loadedModels, ['gemma2:2b']);
      expect(factoryCalls.any((call) => call.model == 'gemma2:2b'), isTrue);
      final saved = await DesktopStateStore(file: stateFile).load();
      expect(saved.model, 'gemma2:2b');
      controller.dispose();
    },
  );

  test('inicia, encerra e testa o servidor propagando erros', () async {
    final stateFile = File('${root.path}/state.json');
    final fake = FakeOllamaClient(
      model: 'llama3.2:3b',
      baseUrl: Uri.parse('http://127.0.0.1:11434'),
      modelsResult: const [OllamaModelInfo(name: 'llama3.2:3b')],
    );
    final controller = DesktopController(
      initialRoot: root,
      store: DesktopStateStore(file: stateFile),
      clientFactory: ({required model, required baseUrl, required options}) =>
          fake,
    );
    await controller.initialize();
    expect(controller.modelState, ModelRunState.stopped);

    await controller.startModel();
    expect(controller.modelState, ModelRunState.running);
    expect(fake.loadedModels, ['llama3.2:3b']);

    await controller.stopModel();
    expect(controller.modelState, ModelRunState.stopped);
    expect(fake.unloadedModels, ['llama3.2:3b']);

    final okResult = await controller.testHost('http://127.0.0.1:11434');
    expect(okResult.ok, isTrue);
    expect(okResult.modelCount, 1);
    expect(okResult.latency, isNotNull);

    final invalidResult = await controller.testHost('nao-e-url');
    expect(invalidResult.ok, isFalse);
    expect(invalidResult.error, isNotNull);
    expect(controller.host, Uri.parse('http://127.0.0.1:11434'));

    fake.failConnection = true;
    final failedResult = await controller.testHost('http://127.0.0.1:11434');
    expect(failedResult.ok, isFalse);
    expect(failedResult.error, contains('falha simulada'));
    expect(controller.connectionState, OllamaConnectionState.ready);

    fake.failConnection = false;
    await controller.saveSettings(
      hostText: 'http://127.0.0.1:11434',
      temperature: 0.7,
      contextLength: 4096,
      keepAlive: const Duration(minutes: 15),
      timeout: const Duration(seconds: 40),
      allowEdit: false,
      allowCommands: true,
    );
    expect(controller.temperature, 0.7);
    expect(controller.allowEdit, isFalse);
    expect(controller.allowCommands, isTrue);
    final saved = await DesktopStateStore(file: stateFile).load();
    expect(saved.inference.temperature, 0.7);
    expect(saved.inference.contextLength, 4096);
    expect(saved.inference.keepAlive, const Duration(minutes: 15));
    expect(saved.permissions.allowEdit, isFalse);
    controller.dispose();
  });

  test(
    'host invalido em saveSettings nao descarta o ultimo estado valido',
    () async {
      final stateFile = File('${root.path}/state.json');
      final fake = FakeOllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:11434'),
        modelsResult: const [OllamaModelInfo(name: 'llama3.2:3b')],
      );
      final controller = DesktopController(
        initialRoot: root,
        store: DesktopStateStore(file: stateFile),
        clientFactory: ({required model, required baseUrl, required options}) =>
            fake,
      );
      await controller.initialize();

      await expectLater(
        controller.saveSettings(
          hostText: 'nao-e-url',
          temperature: 0.9,
          contextLength: 2048,
          keepAlive: null,
          timeout: null,
          allowEdit: true,
          allowCommands: true,
        ),
        throwsFormatException,
      );
      expect(controller.host, Uri.parse('http://127.0.0.1:11434'));
      expect(controller.temperature, 0.1);
      expect(controller.connectionState, OllamaConnectionState.ready);
      controller.dispose();
    },
  );

  test('servidor conectado e modelo parado sao estados separados', () async {
    final stateFile = File('${root.path}/state.json');
    final fake = FakeOllamaClient(
      model: 'llama3.2:3b',
      baseUrl: Uri.parse('http://127.0.0.1:11434'),
      modelsResult: const [OllamaModelInfo(name: 'llama3.2:3b')],
    );
    final controller = DesktopController(
      initialRoot: root,
      store: DesktopStateStore(file: stateFile),
      clientFactory: ({required model, required baseUrl, required options}) =>
          fake,
    );
    await controller.initialize();
    expect(controller.connectionState, OllamaConnectionState.ready);
    expect(controller.modelState, ModelRunState.stopped);

    await controller.send('escreva um arquivo');
    expect(controller.messages, isEmpty);
    expect(controller.connectionError, contains('parado'));

    final result = await controller.testHost('http://127.0.0.1:11434');
    expect(result.ok, isTrue);
    expect(controller.connectionState, OllamaConnectionState.ready);
    controller.dispose();
  });

  test(
    'troca de pasta deduplica recentes e nova sessao persiste resumo',
    () async {
      final stateFile = File('${root.path}/state.json');
      final dirA = await Directory('${root.path}/projeto-a').create();
      final dirB = await Directory('${root.path}/projeto-b').create();
      final fake = FakeOllamaClient(
        model: 'llama3.2:3b',
        baseUrl: Uri.parse('http://127.0.0.1:11434'),
        modelsResult: const [OllamaModelInfo(name: 'llama3.2:3b')],
        runningResult: const [
          OllamaRunningModel(name: 'llama3.2:3b', isInstalled: true),
        ],
        chatResponses: [
          AgentMessage(
            role: 'assistant',
            toolCalls: [
              ToolCall(name: 'read_file', arguments: {'path': 'a.txt'}),
            ],
          ),
          AgentMessage(role: 'assistant', content: 'Arquivo lido.'),
        ],
      );
      final controller = DesktopController(
        initialRoot: root,
        store: DesktopStateStore(file: stateFile),
        clientFactory: ({required model, required baseUrl, required options}) =>
            fake,
        clock: () => DateTime(2026, 8, 28, 12),
      );
      await controller.initialize();
      await File('${dirA.path}/a.txt').writeAsString('conteudo');

      await controller.selectRoot(dirA.path);
      await controller.selectRoot(dirB.path);
      await controller.selectRoot(dirA.path);

      expect(controller.recentRoots, [dirA.path, dirB.path]);
      var saved = await DesktopStateStore(file: stateFile).load();
      expect(saved.activeRoot, dirA.path);
      expect(saved.recentRoots, [dirA.path, dirB.path]);

      await controller.send('analise a.txt');
      expect(controller.messages, hasLength(2));
      expect(controller.activities, hasLength(1));

      await controller.newSession();

      expect(controller.messages, isEmpty);
      expect(controller.activities, isEmpty);
      expect(controller.sessions, hasLength(1));
      expect(controller.sessions.single.title, 'analise a.txt');
      expect(controller.sessions.single.actionCount, 1);
      expect(controller.sessions.single.startedAt, DateTime(2026, 8, 28, 12));
      saved = await DesktopStateStore(file: stateFile).load();
      expect(saved.sessions, hasLength(1));
      expect(saved.sessions.single.title, 'analise a.txt');
      controller.dispose();
    },
  );
}

class FakeOllamaClient extends OllamaClient {
  FakeOllamaClient({
    required super.model,
    required super.baseUrl,
    super.options,
    this.modelsResult = const [],
    this.runningResult = const [],
    this.chatResponses = const [],
  });

  List<OllamaModelInfo> modelsResult;
  List<OllamaRunningModel> runningResult;
  final List<AgentMessage> chatResponses;
  bool failConnection = false;
  final List<String> loadedModels = [];
  final List<String> unloadedModels = [];

  @override
  Future<AgentMessage> chat({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    if (chatResponses.isEmpty) {
      throw StateError('FakeOllamaClient sem resposta de chat');
    }
    return chatResponses.removeAt(0);
  }

  @override
  Future<void> testConnection() async {
    if (failConnection) throw const OllamaException('falha simulada');
  }

  @override
  Future<List<OllamaModelInfo>> listModels() async => modelsResult;

  @override
  Future<List<OllamaRunningModel>> listRunningModels({
    List<OllamaModelInfo>? installed,
  }) async => runningResult;

  @override
  Future<int?> showModel(String name) async => null;

  @override
  Future<void> loadModel(
    String name, {
    Duration keepAlive = const Duration(minutes: 5),
  }) async {
    loadedModels.add(name);
    runningResult = [
      ...runningResult,
      OllamaRunningModel(name: name, isInstalled: true),
    ];
  }

  @override
  Future<void> unloadModel(String name) async {
    unloadedModels.add(name);
    runningResult = [
      for (final running in runningResult)
        if (running.name != name) running,
    ];
  }
}
